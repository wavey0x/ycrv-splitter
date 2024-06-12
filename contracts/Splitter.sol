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

    IVault public rewardToken; // V3 vault
    IERC20 public adminFeeToken; // May or may not be crvUSD
    uint public ybsBribeRatio = 9e17;
    address public owner = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public guardian = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    Recipients recipients;
    address[] public discretionaryGauges;
    address[] public ycrvGauges;
    address[] public partnerGauges;

    event AdminFeeSplit(uint ybs, uint treasury, uint reminder);
    event BribeSplit(uint ybs, uint treasury, uint reminder);

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

    constructor() public {
        discretionaryGauges.push(0x05255C5BD33672b9FEA4129C13274D1E6193312d); // YFI/ETH
        discretionaryGauges.push(0x138cC21D15b7A06F929Fc6CFC88d2b830796F4f1); // ETH/yETH
        ycrvGauges.push(0xEEBC06d495c96E57542A6d829184A907A02ef602); // CRV/yCRV
        partnerGauges.push(0x6070fBD4E608ee5391189E7205d70cc4A274c017); // Threshold
        rewardToken = IVault(address(REWARD_DISTRIBUTOR.rewardToken()));
        rewardToken.approve(address(REWARD_DISTRIBUTOR), type(uint).max);
        recipients.treasury = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
        recipients.remainderTarget = 0x794f80E899c772de9E326eC83cCfD8D94e208B49;
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
        (Split memory adminFeeSplits, Split memory bribeSplits) = getSplits();
        _claimAndSendAdminFees(adminFeeSplits);
        _sendBribes(bribeSplits);
    }

    function executeManualSplit(Split memory adminFeeSplits, Split memory bribeSplits) external {
        uint total = adminFeeSplits.ybsRatio + adminFeeSplits.remainderRatio + adminFeeSplits.treasuryRatio;
        require(total == PRECISION, "adminFeeSplits sum !100%");
        total = bribeSplits.ybsRatio + bribeSplits.remainderRatio + bribeSplits.treasuryRatio;
        require(total == PRECISION, "bribeSplits sum !100%");
        _claimAndSendAdminFees(adminFeeSplits);
        _sendBribes(bribeSplits);
    }

    function _sendBribes(Split memory bribeSplits) internal returns(uint amount) {
        amount = _depositToVault(CRVUSD.balanceOf(address(this)));
        if (amount == 0) return 0;
        if (bribeSplits.ybsRatio > 0) {
            bribeSplits.ybsRatio = bribeSplits.ybsRatio * amount / PRECISION;
            REWARD_DISTRIBUTOR.depositReward(bribeSplits.ybsRatio);
        }
        if (bribeSplits.treasuryRatio > 0) {
            bribeSplits.treasuryRatio = bribeSplits.treasuryRatio * amount / PRECISION;
            rewardToken.transfer(recipients.treasury, bribeSplits.treasuryRatio);
        }
        if (bribeSplits.remainderRatio > 0) {
            bribeSplits.remainderRatio = bribeSplits.remainderRatio * amount / PRECISION;
            rewardToken.transfer(recipients.remainderTarget, bribeSplits.remainderRatio);
        }
        emit BribeSplit(bribeSplits.ybsRatio, bribeSplits.treasuryRatio, bribeSplits.remainderRatio);
        return amount;
    }

    function _claimAndSendAdminFees(Split memory adminFeeSplits) internal returns (uint amount) {
        IERC20 _adminFeeToken = adminFeeToken;
        amount = adminFeeToken.balanceOf(address(this));
        _getProxy().claim(address(this));
        amount = adminFeeToken.balanceOf(address(this)) - amount;
        amount = _depositToVault(amount);
        if (amount == 0) return 0;
        if (adminFeeSplits.ybsRatio > 0) {
            adminFeeSplits.ybsRatio = adminFeeSplits.ybsRatio * amount;
            REWARD_DISTRIBUTOR.depositReward(adminFeeSplits.ybsRatio);
        }
        if (adminFeeSplits.treasuryRatio > 0) {
            adminFeeSplits.treasuryRatio = adminFeeSplits.treasuryRatio * amount;
            rewardToken.transfer(recipients.treasury, adminFeeSplits.treasuryRatio);
        }
        if (adminFeeSplits.remainderRatio > 0) {
            adminFeeSplits.remainderRatio = adminFeeSplits.remainderRatio * amount;
            rewardToken.transfer(recipients.remainderTarget, adminFeeSplits.remainderRatio);
        }
        emit AdminFeeSplit(adminFeeSplits.ybsRatio, adminFeeSplits.treasuryRatio, adminFeeSplits.remainderRatio);
        return amount;
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

    function getBribeSplitRatios(BaseBalances memory base) internal view returns (Split memory bribeSplits) {
        uint nonBribeVotes = getDiscretionaryVotes() + getYcrvVotes() + getPartnerVotes();
        uint totalBribeVotes = base.veTotal - nonBribeVotes;
        if (totalBribeVotes == 0) return Split(0, 0, PRECISION);
        bribeSplits.ybsRatio = base.ybs * ybsBribeRatio / totalBribeVotes;
        bribeSplits.treasuryRatio = PRECISION * (base.untokenized - getDiscretionaryVotes()) / totalBribeVotes;
        bribeSplits.remainderRatio = PRECISION - bribeSplits.ybsRatio - bribeSplits.treasuryRatio;
    }

    function getSplits() public view returns (Split memory adminFeeSplits, Split memory bribeSplits) {
        BaseBalances memory base = getBaseBalances();
        adminFeeSplits = getAdminFeeSplitRatios(base);
        bribeSplits = getBribeSplitRatios(base);
    }

    /// @dev Deposits full balance of crvUSD
    /// @param amount Amount to deposit
    /// @return amount Total balance of reward token
    function _depositToVault(uint amount) internal returns(uint) {
        rewardToken.deposit(amount, address(this));
        return rewardToken.balanceOf(address(this));
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

    function setAdminFeeToken(IERC20 _adminFeeToken) external onlyAdmins {
        adminFeeToken = _adminFeeToken;
    }

    function sweep(IERC20 token, uint amount) external onlyOwner {
        token.safeTransfer(owner, amount);
    }

    function setRecipients(address _treasury, address _remainderTarget) external onlyOwner {
        require(_treasury != address(0) && _remainderTarget != address(0), "Invalid target");
        recipients.treasury = _treasury;
        recipients.remainderTarget = _remainderTarget;
    }

    function _getProxy() internal returns (IProxy) {
        return IVoter(VOTER).strategy();
    }
}