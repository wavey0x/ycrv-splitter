// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Receiver1 {
    using SafeERC20 for IERC20;

    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier _onlyOwner() {
        require(msg.sender == owner, "!Owner");
        _;
    }

    function transferToken(
        IERC20 token,
        address receiver,
        uint256 amount
    ) external _onlyOwner {
        token.safeTransfer(receiver, amount);
    }

    function setTokenApproval(
        IERC20 token,
        address spender,
        uint256 amount
    ) external _onlyOwner {
        token.safeApprove(spender, amount);
    }

    function setOwner(address _owner) external _onlyOwner {
        owner = _owner;
    }
}