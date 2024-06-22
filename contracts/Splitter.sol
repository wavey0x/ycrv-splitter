// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGaugeController {
    struct VotedSlope {
        uint slope;
        uint power;
        uint end;
    }
    function vote_user_slopes(address user, address gauge) external view returns (VotedSlope memory);
}

interface IProxy {
    function claim(address recipient) external;
    function approvedAdminFeeClaimers(address claimer) external view returns (bool approved);
}

interface IVoter {
    function strategy() external view returns(IProxy);
}

interface IDistributor {
    function depositReward(uint amount) external;
    function rewardToken() external view returns (IERC20);
}

interface IVault {
    function deposit(uint amount, address receiver) external returns (uint);
    function asset() external view returns (IERC20);
    function approve(address, uint) external returns (bool);
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
}

contract YCRVSplitter {
    using SafeERC20 for IERC20;

    uint public constant PRECISION = 1e18;
    address public constant VOTER = 0xF147b8125d2ef93FB6965Db97D6746952a133934;
    address public constant POOL = 0x99f5aCc8EC2Da2BC0771c32814EFF52b712de1E5;
    address public constant VE = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant VAULT = 0x27B5739e22ad9033bcBf192059122d163b60349D;
    IGaugeController public constant GAUGE_CONTROLLER = IGaugeController(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);
    address public constant YBS = 0xE9A115b77A1057C918F997c32663FdcE24FB873f;
    IERC20 public constant YCRV = IERC20(0xFCc5c47bE19d06BF83eB04298b026F81069ff65b);
    IERC20 public constant YVECRV = IERC20(0xc5bDdf9843308380375a611c18B50Fb9341f502A);
    IERC20 public constant CRVUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IDistributor public constant REWARD_DISTRIBUTOR = IDistributor(0xB226c52EB411326CdB54824a88aBaFDAAfF16D3d);

    IVault public immutable REWARD_TOKEN; // V3 vault
    address public immutable RECEIVER;
    bool public permissionlessSplitsAllowed;
    uint public ybsVoteIncentiveRatio = 9e17;
    address public owner = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public guardian = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    Recipients recipients;
    address[] public discretionaryGauges;
    address[] public ycrvGauges;
    address[] public partnerGauges;
    mapping(address caller => bool approved) public approvedSplitCallers;

    event AdminFeeSplit(uint ybs, uint treasury, uint remainder);
    event VoteIncentiveSplit(uint ybs, uint treasury, uint remainder);

    struct BaseBalances {
        uint ybs;
        uint lp;
        uint loose;
        uint unmigrated;
        uint partners;
        uint untokenized;
        uint veTotal;
    }

    struct Split {
        uint ybsRatio;
        uint treasuryRatio;
        uint remainderRatio;
    }

    struct Recipients {
        address treasury;
        address remainderTarget;
    }

    constructor(address _receiver) public {
        discretionaryGauges.push(0x05255C5BD33672b9FEA4129C13274D1E6193312d); // YFI/ETH
        discretionaryGauges.push(0x138cC21D15b7A06F929Fc6CFC88d2b830796F4f1); // ETH/yETH
        ycrvGauges.push(0xEEBC06d495c96E57542A6d829184A907A02ef602); // CRV/yCRV
        partnerGauges.push(0x6070fBD4E608ee5391189E7205d70cc4A274c017); // Threshold
        REWARD_TOKEN = IVault(address(REWARD_DISTRIBUTOR.rewardToken()));
        REWARD_TOKEN.approve(address(REWARD_DISTRIBUTOR), type(uint).max);
        CRVUSD.approve(address(REWARD_TOKEN), type(uint).max);
        recipients.treasury = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
        recipients.remainderTarget = 0x794f80E899c772de9E326eC83cCfD8D94e208B49;
        RECEIVER = _receiver;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "!Owner");
        _;
    }

    modifier onlyAdmins() {
        require(msg.sender == owner || msg.sender == guardian, "!Admin");
        _;
    }

    function executeSplit() external {
        require(
            permissionlessSplitsAllowed ||
            approvedSplitCallers[msg.sender] ||
            msg.sender == owner ||
            msg.sender == guardian
        );
        (Split memory adminFeeSplits, Split memory voteIncentiveSplits) = getSplits();
        uint amount = _claimAdminFees();
        _sendAdminFees(amount, adminFeeSplits);
        _sendVoteIncentives(voteIncentiveSplits);
    }

    function executeManualSplit(Split memory adminFeeSplits, Split memory voteIncentiveSplits) external onlyOwner {
        uint total = adminFeeSplits.ybsRatio + adminFeeSplits.remainderRatio + adminFeeSplits.treasuryRatio;
        require(total == PRECISION, "adminFeeSplits sum !100%");
        total = voteIncentiveSplits.ybsRatio + voteIncentiveSplits.remainderRatio + voteIncentiveSplits.treasuryRatio;
        require(total == PRECISION, "voteIncentiveSplits sum !100%");
        uint amount = _claimAdminFees();
        _sendAdminFees(amount, adminFeeSplits);
        _sendVoteIncentives(voteIncentiveSplits);
    }

    function depositAdminFeesAndSplit(uint _amount) external onlyAdmins {
        CRVUSD.transferFrom(msg.sender, address(this), _amount);
        (Split memory adminFeeSplits, Split memory voteIncentiveSplits) = getSplits();
        _sendAdminFees(_amount, adminFeeSplits);
        _sendVoteIncentives(voteIncentiveSplits);
    }

    function _sendVoteIncentives(Split memory voteIncentiveSplits) internal returns(uint amount) {
        amount = CRVUSD.balanceOf(RECEIVER);
        CRVUSD.transferFrom(RECEIVER, address(this), amount);
        amount = _depositToVault(CRVUSD.balanceOf(address(this)));
        if (amount == 0) return 0;
        if (voteIncentiveSplits.ybsRatio > 0) {
            voteIncentiveSplits.ybsRatio = voteIncentiveSplits.ybsRatio * amount / PRECISION;
            REWARD_DISTRIBUTOR.depositReward(voteIncentiveSplits.ybsRatio);
        }
        if (voteIncentiveSplits.treasuryRatio > 0) {
            voteIncentiveSplits.treasuryRatio = voteIncentiveSplits.treasuryRatio * amount / PRECISION;
            REWARD_TOKEN.transfer(recipients.treasury, voteIncentiveSplits.treasuryRatio);
        }
        if (voteIncentiveSplits.remainderRatio > 0) {
            voteIncentiveSplits.remainderRatio = voteIncentiveSplits.remainderRatio * amount / PRECISION;
            REWARD_TOKEN.transfer(recipients.remainderTarget, voteIncentiveSplits.remainderRatio);
        }
        emit VoteIncentiveSplit(voteIncentiveSplits.ybsRatio, voteIncentiveSplits.treasuryRatio, voteIncentiveSplits.remainderRatio);
        return amount;
    }

    function _claimAdminFees() internal returns (uint amount) {
        IProxy proxy = _getProxy();
        if (!proxy.approvedAdminFeeClaimers(address(this))) return 0;
        amount = REWARD_TOKEN.balanceOf(address(this));
        proxy.claim(address(this));
        return REWARD_TOKEN.balanceOf(address(this)) - amount;
    }

    function _sendAdminFees(uint _amount, Split memory adminFeeSplits) internal returns (uint) {
        _amount = _depositToVault(_amount);
        if (_amount == 0) return 0;
        if (adminFeeSplits.ybsRatio > 0) {
            adminFeeSplits.ybsRatio = adminFeeSplits.ybsRatio * _amount / PRECISION;
            REWARD_DISTRIBUTOR.depositReward(adminFeeSplits.ybsRatio);
        }
        if (adminFeeSplits.treasuryRatio > 0) {
            adminFeeSplits.treasuryRatio = adminFeeSplits.treasuryRatio * _amount / PRECISION;
            REWARD_TOKEN.transfer(recipients.treasury, adminFeeSplits.treasuryRatio);
        }
        if (adminFeeSplits.remainderRatio > 0) {
            adminFeeSplits.remainderRatio = adminFeeSplits.remainderRatio * _amount / PRECISION;
            REWARD_TOKEN.transfer(recipients.remainderTarget, adminFeeSplits.remainderRatio);
        }
        emit AdminFeeSplit(adminFeeSplits.ybsRatio, adminFeeSplits.treasuryRatio, adminFeeSplits.remainderRatio);
        return _amount;
    }

    function yearnVeBalance() internal view returns (uint) {
        return IERC20(VE).balanceOf(VOTER);
    }

    function getBaseBalances() public view returns (BaseBalances memory base) {
        base.veTotal = yearnVeBalance();
        base.ybs = ybsBalance();
        base.lp = YCRV.balanceOf(POOL);
        base.partners = getPartnerVotes();
        uint recognizedPositions = base.ybs + base.lp + base.partners;
        uint ycrvTotalSupply = YCRV.totalSupply();
        require(recognizedPositions < ycrvTotalSupply, "PartnerBalanceTooHigh");
        base.loose = ycrvTotalSupply - recognizedPositions;
        base.unmigrated = unmigrated();
        base.untokenized = base.veTotal - recognizedPositions - base.loose - base.unmigrated;
        return base;
    }

    function getAdminFeeSplitRatios(BaseBalances memory base) internal view returns (Split memory adminFeeSplits) {
        adminFeeSplits.ybsRatio = PRECISION * base.ybs / (base.veTotal - base.untokenized);
        adminFeeSplits.remainderRatio = PRECISION - (adminFeeSplits.ybsRatio);
    }

    function getVoteIncentiveSplitRatios(BaseBalances memory base) internal view returns (Split memory voteIncentiveSplits) {
        uint nonVoteIncentiveVotes = getDiscretionaryVotes() + getYcrvVotes() + getPartnerVotes();
        uint totalVoteIncentiveVotes = base.veTotal - nonVoteIncentiveVotes;
        if (totalVoteIncentiveVotes == 0) return Split(0, 0, PRECISION);
        voteIncentiveSplits.ybsRatio = base.ybs * ybsVoteIncentiveRatio / totalVoteIncentiveVotes;
        voteIncentiveSplits.treasuryRatio = PRECISION * (base.untokenized - getDiscretionaryVotes()) / totalVoteIncentiveVotes;
        voteIncentiveSplits.remainderRatio = PRECISION - voteIncentiveSplits.ybsRatio - voteIncentiveSplits.treasuryRatio;
    }

    function getSplits() public view returns (Split memory adminFeeSplits, Split memory voteIncentiveSplits) {
        BaseBalances memory base = getBaseBalances();
        adminFeeSplits = getAdminFeeSplitRatios(base);
        voteIncentiveSplits = getVoteIncentiveSplitRatios(base);
    }

    /// @dev Deposits full balance of crvUSD
    /// @param _amount Amount to deposit
    /// @return amount Total balance of reward token
    function _depositToVault(uint _amount) internal returns(uint) {
        if (_amount == 0) return 0;
        REWARD_TOKEN.deposit(_amount, address(this));
        return REWARD_TOKEN.balanceOf(address(this));
    }

    function getDiscretionaryVotes() public view returns (uint) {
        return sumGaugeBias(discretionaryGauges);
    }

    function getPartnerVotes() public view returns (uint) {
        return sumGaugeBias(partnerGauges);
    }

    function getYcrvVotes() public view returns (uint) {
        return sumGaugeBias(ycrvGauges);
    }

    function unmigrated() internal view returns (uint) {
        uint migrated = YVECRV.balanceOf(address(YCRV));
        return YVECRV.totalSupply() - migrated;
    }

    function ybsBalance() internal view returns (uint) {
        return (
            YCRV.balanceOf(address(YBS)) +
            YCRV.balanceOf(address(VAULT))
        );
    }

    function sumGaugeBias(address[] memory gauges) internal view returns (uint) {
        uint biasTotal;
        uint currentWeekTimestamp = getCurrentWeekStartTime();
        for(uint i; i < gauges.length; i++){
            IGaugeController.VotedSlope memory slopeData = GAUGE_CONTROLLER.vote_user_slopes(VOTER, gauges[i]);
            uint end = slopeData.end;
            if (currentWeekTimestamp + 1 weeks < end) biasTotal += slopeData.slope * (end - currentWeekTimestamp);
        }
        return biasTotal;
    }

    function getCurrentWeekStartTime() internal view returns (uint) {
        return block.timestamp / 1 weeks * 1 weeks;
    }

    function setDiscretionaryGauges(address[] memory _gauges) external onlyAdmins {
        delete discretionaryGauges;
        discretionaryGauges = _gauges;
    }

    function setYCrvGauges(address[] memory _gauges) external onlyAdmins {
        delete ycrvGauges;
        ycrvGauges = _gauges;
    }

    function setPartnerGauges(address[] memory _gauges) external onlyAdmins {
        delete partnerGauges;
        partnerGauges = _gauges;
    }

    function sweep(IERC20 token, uint amount) external onlyOwner {
        token.safeTransfer(owner, amount);
    }

    function setRecipients(address _treasury, address _remainderTarget) external onlyOwner {
        require(_treasury != address(0) && _remainderTarget != address(0), "Invalid target");
        recipients.treasury = _treasury;
        recipients.remainderTarget = _remainderTarget;
    }

    function setPermissionlessSplitsAllowed(bool _allowed) external onlyOwner{
        permissionlessSplitsAllowed = _allowed;
    }

    function setApprovedSplitCaller(address _caller, bool _approved) external onlyOwner {
        approvedSplitCallers[_caller] = _approved;
    }

    function _getProxy() internal returns (IProxy) {
        return IVoter(VOTER).strategy();
    }
}