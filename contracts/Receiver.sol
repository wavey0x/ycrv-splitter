// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IDistributor {
    function depositReward(uint amount) external;

    function rewardToken() external view returns (IERC20);
}

contract Receiver {
    using SafeERC20 for IERC20;

    IDistributor public immutable DISTRIBUTOR;
    IERC20 public immutable REWARD_TOKEN;
    address public owner;
    address public pendingOwner;
    address public guardian;
    bool public paused;
    uint public performanceFee = 1_000;
    address public feeRecipient;
    mapping(address spender => bool approved) public approvedSpenders;

    event SpenderApproved(address indexed spender, bool indexed approved);
    event OwnershipTransferred(address indexed pendingOwner);
    event GuardianSet(address indexed guardian);

    constructor(
        address _owner,
        address _guardian,
        address _feeRecipient,
        IDistributor _distributor
    ) {
        owner = _owner;
        guardian = _guardian;
        feeRecipient = _feeRecipient;
        DISTRIBUTOR = _distributor;
        REWARD_TOKEN = _distributor.rewardToken();
        REWARD_TOKEN.approve(address(DISTRIBUTOR), type(uint).max);
    }

    modifier _onlyOwner() {
        require(msg.sender == owner, "!Owner");
        _;
    }

    modifier _onlyAdmins() {
        require(msg.sender == owner || msg.sender == guardian, "!Admin");
        _;
    }

    /**
        @notice Permissionless deposit into rewards contract.
        @return amount amount of YVCRVUSD tokens added to staker.
    */
    function depositRewards() external returns (uint amount) {
        require(!paused, "paused");
        amount = REWARD_TOKEN.balanceOf(address(this));
        if (amount == 0) return 0;
        uint fee = (amount * performanceFee) / 10_000;
        if (fee > 0) {
            amount -= fee;
            REWARD_TOKEN.safeTransfer(feeRecipient, fee);
        }
        if (amount > 0) DISTRIBUTOR.depositReward(amount);
    }

    function transferToken(
        IERC20 token,
        address receiver,
        uint256 amount
    ) external {
        require(approvedSpenders[msg.sender], "!Approved");
        _transfer(token, receiver, amount);
    }

    function transferManyTokens(
        IERC20[] memory tokens,
        address receiver,
        uint256[] memory amounts
    ) external {
        require(approvedSpenders[msg.sender], "!Approved");
        require(tokens.length == amounts.length, "Array lengths dont match");
        for (uint i; i < tokens.length; i++) {
            _transfer(tokens[i], receiver, amounts[i]);
        }
    }

    function _transfer(
        IERC20 token,
        address receiver,
        uint256 amount
    ) internal {
        token.safeTransfer(receiver, amount);
    }

    function setApprovedSpender(
        address _spender,
        bool _approved
    ) external _onlyOwner {
        if (msg.sender == guardian) {
            require(_approved == false, "Guardian may only disable");
        }
        require(approvedSpenders[_spender] != _approved, "!Update");
        approvedSpenders[_spender] = _approved;
        emit SpenderApproved(_spender, _approved);
    }

    function setPaused(bool _paused) external _onlyAdmins {
        paused = _paused;
    }

    function setPerformanceFee(uint _performanceFee) external _onlyOwner {
        require(_performanceFee <= 10_000, "Too high");
        performanceFee = _performanceFee;
    }

    function setFeeRecipient(address _feeRecipient) external _onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setOwner(address _pendingOwner) external _onlyOwner {
        pendingOwner = _pendingOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "!Pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(pendingOwner);
    }

    function setGuardian(address _guardian) external _onlyOwner {
        guardian = _guardian;
        emit GuardianSet(_guardian);
    }
}
