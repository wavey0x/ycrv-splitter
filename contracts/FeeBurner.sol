// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
    @title Yearn Curve Fee Burner
    @author Yearn Finance
    @notice Receiver contract for tokens earned by Yearn's veCRV position to be converted to crvUSD.
 */
contract FeeBurner is Ownable2Step {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    ///@notice Check if an address is an approved guardian of this contract
    address public guardian;

    ///@notice Check if an address is approved to spend tokens from this contract
    mapping(address => bool) public isTokenSpender;

    // spender => tokens they have been approved to spend. to view this use getApprovals(spender)
    mapping(address => EnumerableSet.AddressSet) internal spenderApprovals;

    event SpenderApproved(address indexed spender);
    event SpenderRevoked(address indexed spender);
    event GuardianSet(address indexed guardian);

    constructor(address _guardian) {
        guardian = _guardian;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Check if a spender has the ability to spend any tokens from this contract.
     * @param _spender Address to check for tokens approvals
     * @return tokens Addresses of tokens this spender can pull
     */
    function getApprovals(
        address _spender
    ) public view returns (address[] memory tokens) {
        return spenderApprovals[_spender].values();
    }

    /* ========== GUARDIAN FUNCTIONS ========== */

    /**
     * @notice Approve a previously approved spender to spend a list of tokens
     * @param _spender Address to allow to spend tokens
     * @param _tokens Addresses of tokens to allow
     */
    function giveTokenAllowance(
        address _spender,
        address[] memory _tokens
    ) external {
        require(
            msg.sender == guardian || msg.sender == owner(),
            "not approved"
        );
        require(isTokenSpender[_spender], "unapproved spender");
        for (uint256 i; i < _tokens.length; ++i) {
            IERC20(_tokens[i]).forceApprove(_spender, type(uint256).max);
            spenderApprovals[_spender].add(_tokens[i]);
        }
    }

    /**
     * @notice Revoke a previously approved spender from spending a list of tokens
     * @param _spender Address to revoke spending tokens
     * @param _tokens Addresses of tokens to revoke
     */
    function revokeTokenAllowance(
        address _spender,
        address[] memory _tokens
    ) external {
        require(
            msg.sender == guardian || msg.sender == owner(),
            "not approved"
        );
        for (uint256 i; i < _tokens.length; ++i) {
            IERC20(_tokens[i]).forceApprove(_spender, 0);
            spenderApprovals[_spender].remove(_tokens[i]);
        }
    }

    /**
     * @notice Revoke future approval for an address to spend any token held by this contract.
     * @dev Note that this clears all of their existing approvals as well
     * @param _spender Address to revoke from spending tokens
     */
    function revokeTokenSpender(address _spender) external {
        require(
            msg.sender == guardian || msg.sender == owner(),
            "not approved"
        );
        require(isTokenSpender[_spender], "not a spender");
        isTokenSpender[_spender] = false;
        emit SpenderRevoked(_spender);

        // revoke all of their approvals as well
        address[] memory tokens = spenderApprovals[_spender].values();
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).forceApprove(_spender, 0);
            spenderApprovals[_spender].remove(tokens[i]);
        }
    }

    /* ========== OWNER-ONLY FUNCTIONS ========== */

    /**
     * @notice Transfer out any token as needed
     * @dev Should only be used as an emergency function
     * @param _token Token to transfer out
     * @param _receiver Address to send the token to
     * @param _amount Amount of token to transfer
     */
    function transferToken(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    /**
     * @notice Approve (allowlist) an address to spend any token held by this contract.
     * @dev Use with great caution! Note that individual tokens must still be approved.
     * @param _spender Address to allow to spend tokens
     */
    function approveTokenSpender(address _spender) external onlyOwner {
        isTokenSpender[_spender] = true;
        emit SpenderApproved(_spender);
    }

    /**
     * @notice Grant guardian role to an address
     * @dev Guardian can add tokens for approved spenders, revoke spenders, and revoke tokens
     * @param _guardian Address to grant guardian role
     */
    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
        emit GuardianSet(_guardian);
    }
}
