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
        address,
        address
    ) external view returns (VotedSlope memory);
}

contract YCRVSplitter {

    uint public constant PRECISION = 1e18;
    address public constant VOTER = 0xF147b8125d2ef93FB6965Db97D6746952a133934;
    address public constant POOL = 0x99f5aCc8EC2Da2BC0771c32814EFF52b712de1E5;
    address public constant VE = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    IGaugeController public constant GAUGE_CONTROLLER = IGaugeController(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);
    address public constant YBS = 0xE9A115b77A1057C918F997c32663FdcE24FB873f;
    IERC20 public constant YCRV = IERC20(0xFCc5c47bE19d06BF83eB04298b026F81069ff65b);
    IERC20 public constant VAULT = IERC20(0x27B5739e22ad9033bcBf192059122d163b60349D);
    IERC20 public constant YVECRV = IERC20(0xc5bDdf9843308380375a611c18B50Fb9341f502A);

    uint public ybsBribeRatio = 9e17;
    address public owner = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public guardian = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    address[] public discretionaryGauges;
    address[] public ycrvGauges;

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
        uint leftoverRatio;
    }

    constructor() public {
        discretionaryGauges.push(0x05255C5BD33672b9FEA4129C13274D1E6193312d); // YFI/ETH
        discretionaryGauges.push(0x138cC21D15b7A06F929Fc6CFC88d2b830796F4f1); // ETH/yETH
        ycrvGauges.push(0xEEBC06d495c96E57542A6d829184A907A02ef602); // CRV/yCRV
    }

    modifier onlyAdmins() {
        require(msg.sender == owner || msg.sender == guardian, "Sender is not an admin");
        _;
    }

    function yearnVeBalance() internal view returns (uint) {
        return IERC20(VE).balanceOf(VOTER);
    }

    function getBaseBalances(uint partnerBalances) public view returns (BaseBalances memory base) {
        base.veTotal = yearnVeBalance();
        base.ybs = ybsBalance();
        base.lp = YCRV.balanceOf(POOL);
        base.partners = partnerBalances;
        uint recognizedPositions = base.ybs + base.lp + partnerBalances;
        uint ycrvTotalSupply = YCRV.totalSupply();
        require(recognizedPositions < ycrvTotalSupply, "PartnerBalanceTooHigh");
        base.loose = ycrvTotalSupply - recognizedPositions;
        base.unmigrated = unmigrated();
        base.untokenized = base.veTotal - recognizedPositions - base.loose - base.unmigrated;
        return base;
    }

    function getAdminFeeSplitRatios(BaseBalances memory base) internal view returns (Split memory adminFeeSplits) {
        adminFeeSplits.ybsRatio = PRECISION * base.ybs / (base.veTotal - base.untokenized);
        adminFeeSplits.leftoverRatio = PRECISION - (adminFeeSplits.ybsRatio);
    }

    function getBribeSplitRatios(BaseBalances memory base, uint partnerBalances) internal view returns (Split memory bribeSplits) {
        uint nonBribeVotes = getDiscretionaryVotes() + getYcrvVotes() + partnerBalances;
        uint totalBribeVotes = base.veTotal - nonBribeVotes;
        bribeSplits.ybsRatio = base.ybs * ybsBribeRatio / totalBribeVotes;
        bribeSplits.treasuryRatio = PRECISION * (base.untokenized - getDiscretionaryVotes()) / totalBribeVotes;
        bribeSplits.leftoverRatio = PRECISION - bribeSplits.ybsRatio - bribeSplits.treasuryRatio;
    }

    function getSplits(uint partnerBalances) public view returns (Split memory adminFeeSplits, Split memory bribeSplits) {
        BaseBalances memory base = getBaseBalances(partnerBalances);
        adminFeeSplits = getAdminFeeSplitRatios(base);
        bribeSplits = getBribeSplitRatios(base, partnerBalances);
    }

    function getDiscretionaryVotes() public view returns (uint) {
        return sumGaugeBias(discretionaryGauges);
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
}