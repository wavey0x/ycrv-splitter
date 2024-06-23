// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGaugeController {
    struct VotedSlope {
        uint slope;
        uint power;
        uint end;
    }

    function vote_user_slopes(
        address user,
        address gauge
    ) external view returns (VotedSlope memory);

    function gauge_types(address gauge) external view returns (int128);
}

interface IProxy {
    function claimAdminFees() external returns (uint);

    function canClaim() external view returns (bool);
}

interface IVoter {
    function strategy() external view returns (IProxy);
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
    IGaugeController public constant GAUGE_CONTROLLER =
        IGaugeController(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);
    address public constant YBS = 0xE9A115b77A1057C918F997c32663FdcE24FB873f;
    IERC20 public constant YCRV =
        IERC20(0xFCc5c47bE19d06BF83eB04298b026F81069ff65b);
    IERC20 public constant YVECRV =
        IERC20(0xc5bDdf9843308380375a611c18B50Fb9341f502A);
    IERC20 public constant CRVUSD =
        IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IVault public constant REWARD_TOKEN =
        IVault(0xBF319dDC2Edc1Eb6FDf9910E39b37Be221C8805F); // V3 vault

    address public immutable FEE_BURNER;
    uint public ybsVoteIncentiveRatio = 9e17;
    address public owner = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public guardian = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    Recipients recipients;
    uint public ycrvGaugesLength;
    uint public partnerGaugesLength;
    uint public discretionaryGaugesLength;
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
        address ybs;
        address treasury;
        address remainderTarget;
    }

    constructor(
        address _feeBurner,
        address _receiver2,
        address[] memory ycrvGauges,
        address[] memory partnerGauges,
        address[] memory discretionaryGauges
    ) public {
        _setYCrvGauges(ycrvGauges);
        _setPartnerGauges(partnerGauges);
        _setDiscretionaryGauges(discretionaryGauges);

        recipients.ybs = _receiver2;
        recipients.treasury = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
        recipients.remainderTarget = 0x794f80E899c772de9E326eC83cCfD8D94e208B49;
        FEE_BURNER = _feeBurner;

        CRVUSD.approve(address(REWARD_TOKEN), type(uint).max);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "!Owner");
        _;
    }

    modifier onlyAdmins() {
        require(msg.sender == owner || msg.sender == guardian, "!Admin");
        _;
    }

    /// @notice Split according to on-chain calculations.
    function executeSplit() external {
        require(
            approvedSplitCallers[msg.sender] ||
                msg.sender == owner ||
                msg.sender == guardian
        );
        (
            Split memory adminFeeSplits,
            Split memory voteIncentiveSplits
        ) = getSplits();
        uint amount = _claimAdminFees();
        _sendAdminFees(amount, adminFeeSplits);
        _sendVoteIncentives(voteIncentiveSplits);
    }

    /// @notice Supply manual split values to override on-chain claculations.
    function executeManualSplit(
        Split memory adminFeeSplits,
        Split memory voteIncentiveSplits
    ) external onlyOwner {
        uint total = adminFeeSplits.ybsRatio +
            adminFeeSplits.remainderRatio +
            adminFeeSplits.treasuryRatio;
        require(total == PRECISION, "adminFeeSplits sum !100%");
        total =
            voteIncentiveSplits.ybsRatio +
            voteIncentiveSplits.remainderRatio +
            voteIncentiveSplits.treasuryRatio;
        require(total == PRECISION, "voteIncentiveSplits sum !100%");
        uint amount = _claimAdminFees();
        _sendAdminFees(amount, adminFeeSplits);
        _sendVoteIncentives(voteIncentiveSplits);
    }

    /// @dev Allow admins to manually push crvUSD as admin fees. Nice to have in event
    ///      where admin fees might flow to old receiver.
    function depositAdminFeesAndSplit(uint _amount) external onlyAdmins {
        CRVUSD.transferFrom(msg.sender, address(this), _amount);
        (
            Split memory adminFeeSplits,
            Split memory voteIncentiveSplits
        ) = getSplits();
        _sendAdminFees(_amount, adminFeeSplits);
        _sendVoteIncentives(voteIncentiveSplits);
    }

    function _sendVoteIncentives(
        Split memory splits
    ) internal returns (uint amount) {
        amount = CRVUSD.balanceOf(FEE_BURNER);
        CRVUSD.transferFrom(FEE_BURNER, address(this), amount);
        amount = _depositToVault(CRVUSD.balanceOf(address(this)));
        if (amount == 0) return 0;
        if (splits.ybsRatio > 0) {
            splits.ybsRatio = (splits.ybsRatio * amount) / PRECISION;
            REWARD_TOKEN.transfer(recipients.ybs, splits.ybsRatio);
        }
        if (splits.treasuryRatio > 0) {
            splits.treasuryRatio = (splits.treasuryRatio * amount) / PRECISION;
            REWARD_TOKEN.transfer(recipients.treasury, splits.treasuryRatio);
        }
        if (splits.remainderRatio > 0) {
            splits.remainderRatio =
                (splits.remainderRatio * amount) /
                PRECISION;
            REWARD_TOKEN.transfer(
                recipients.remainderTarget,
                splits.remainderRatio
            );
        }
        emit VoteIncentiveSplit(
            splits.ybsRatio,
            splits.treasuryRatio,
            splits.remainderRatio
        );
        return amount;
    }

    function _claimAdminFees() internal returns (uint amount) {
        IProxy proxy = _getProxy();
        if (!proxy.canClaim()) return 0;
        amount = proxy.claimAdminFees();
    }

    function _sendAdminFees(
        uint _amount,
        Split memory splits
    ) internal returns (uint) {
        _amount = _depositToVault(_amount);
        if (_amount == 0) return 0;
        if (splits.ybsRatio > 0) {
            splits.ybsRatio = (splits.ybsRatio * _amount) / PRECISION;
            REWARD_TOKEN.transfer(recipients.ybs, splits.ybsRatio);
        }
        if (splits.treasuryRatio > 0) {
            splits.treasuryRatio = (splits.treasuryRatio * _amount) / PRECISION;
            REWARD_TOKEN.transfer(recipients.treasury, splits.treasuryRatio);
        }
        if (splits.remainderRatio > 0) {
            splits.remainderRatio =
                (splits.remainderRatio * _amount) /
                PRECISION;
            REWARD_TOKEN.transfer(
                recipients.remainderTarget,
                splits.remainderRatio
            );
        }
        emit AdminFeeSplit(
            splits.ybsRatio,
            splits.treasuryRatio,
            splits.remainderRatio
        );
        return _amount;
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
        base.untokenized =
            base.veTotal -
            recognizedPositions -
            base.loose -
            base.unmigrated;
        return base;
    }

    function getAdminFeeSplitRatios(
        BaseBalances memory base
    ) internal view returns (Split memory splits) {
        splits.ybsRatio =
            (PRECISION * base.ybs) /
            (base.veTotal - base.untokenized);
        splits.remainderRatio = PRECISION - (splits.ybsRatio);
    }

    function getVoteIncentiveSplitRatios(
        BaseBalances memory base
    ) internal view returns (Split memory splits) {
        uint nonVoteIncentiveVotes = getDiscretionaryVotes() +
            getYcrvVotes() +
            getPartnerVotes();
        uint totalVoteIncentiveVotes = base.veTotal - nonVoteIncentiveVotes;
        if (totalVoteIncentiveVotes == 0) return Split(0, 0, PRECISION);
        splits.ybsRatio =
            (base.ybs * ybsVoteIncentiveRatio) /
            totalVoteIncentiveVotes;
        splits.treasuryRatio =
            (PRECISION * (base.untokenized - getDiscretionaryVotes())) /
            totalVoteIncentiveVotes;
        splits.remainderRatio =
            PRECISION -
            splits.ybsRatio -
            splits.treasuryRatio;
    }

    /// @notice Preview split ratios.
    function getSplits()
        public
        view
        returns (Split memory adminFeeSplits, Split memory voteIncentiveSplits)
    {
        BaseBalances memory base = getBaseBalances();
        adminFeeSplits = getAdminFeeSplitRatios(base);
        voteIncentiveSplits = getVoteIncentiveSplitRatios(base);
    }

    /// @dev Deposits full balance of crvUSD.
    /// @param _amount Amount to deposit.
    /// @return amount Total balance of reward token.
    function _depositToVault(uint _amount) internal returns (uint) {
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
        return (YCRV.balanceOf(address(YBS)) + YCRV.balanceOf(address(VAULT)));
    }

    function yearnVeBalance() internal view returns (uint) {
        return IERC20(VE).balanceOf(VOTER);
    }

    /// @dev Sum all active bias (veCRV contributed by Yearn) for a list of gauges.
    function sumGaugeBias(
        address[] memory gauges
    ) internal view returns (uint) {
        uint biasTotal;
        uint currentWeekTimestamp = getCurrentWeekStartTime();
        for (uint i; i < gauges.length; i++) {
            IGaugeController.VotedSlope memory slopeData = GAUGE_CONTROLLER
                .vote_user_slopes(VOTER, gauges[i]);
            uint end = slopeData.end;
            if (currentWeekTimestamp + 1 weeks < end)
                biasTotal += slopeData.slope * (end - currentWeekTimestamp);
        }
        return biasTotal;
    }

    function getCurrentWeekStartTime() internal view returns (uint) {
        return (block.timestamp / 1 weeks) * 1 weeks;
    }

    /// @notice Manually specify gauges used for yCRV voting.
    function setYCrvGauges(address[] memory _gauges) external onlyAdmins {
        _setYCrvGauges(_gauges);
    }

    function _setYCrvGauges(address[] memory _gauges) internal {
        require(_validateGaugeList(_gauges), "Invalid gauge list");
        delete ycrvGauges;
        ycrvGauges = _gauges;
        ycrvGaugesLength = _gauges.length;
    }

    /// @notice Manually specify gauges used for partner voting.
    function setPartnerGauges(address[] memory _gauges) external onlyAdmins {
        _setPartnerGauges(_gauges);
    }

    function _setPartnerGauges(address[] memory _gauges) internal {
        require(_validateGaugeList(_gauges), "Invalid gauge list");
        delete partnerGauges;
        partnerGauges = _gauges;
        partnerGaugesLength = _gauges.length;
    }

    /// @notice Manually specify gauges that Yearn elects to use its own veCRV balance to vote for.
    function setDiscretionaryGauges(
        address[] memory _gauges
    ) external onlyAdmins {
        _setDiscretionaryGauges(_gauges);
    }

    function _setDiscretionaryGauges(address[] memory _gauges) internal {
        require(_validateGaugeList(_gauges), "Invalid gauge list");
        delete discretionaryGauges;
        discretionaryGauges = _gauges;
        discretionaryGaugesLength = _gauges.length;
    }

    function sweep(IERC20 token, uint amount) external onlyOwner {
        token.safeTransfer(owner, amount);
    }

    function setRecipients(
        address _ybs,
        address _treasury,
        address _remainderTarget
    ) external onlyOwner {
        require(
            _ybs != address(0) &&
                _treasury != address(0) &&
                _remainderTarget != address(0),
            "Invalid target"
        );
        recipients.ybs = _ybs;
        recipients.treasury = _treasury;
        recipients.remainderTarget = _remainderTarget;
    }

    function setApprovedSplitCaller(
        address _caller,
        bool _approved
    ) external onlyOwner {
        approvedSplitCallers[_caller] = _approved;
    }

    function _getProxy() internal returns (IProxy) {
        return IVoter(VOTER).strategy();
    }

    /// @dev Prevents duplicates and unapproved gauges
    function _validateGaugeList(
        address[] memory _gauges
    ) internal returns (bool) {
        for (uint i = 0; i < _gauges.length; i++) {
            for (uint k = 0; k < i; k++) {
                // Loop through only the part of the array that has been processed
                if (i != k && _gauges[i] == _gauges[k]) {
                    return false;
                }
            }
            // Reverts if Curve gov has not approved this address.
            try GAUGE_CONTROLLER.gauge_types(_gauges[i]) {} catch {
                return false;
            }
        }
        return true;
    }
}
