// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface FeeDistribution {
    function claim_many(address[20] calldata) external returns (bool);
    function last_token_time() external view returns (uint256);
    function time_cursor() external view returns (uint256);
    function time_cursor_of(address) external view returns (uint256);
}

library SafeProxy {
    function safeExecute(
        IProxy proxy,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        (bool success, ) = proxy.execute(to, value, data);
        require(success);
    }
}

interface IProxy {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);
}

contract StrategyProxy {
    using SafeERC20 for IERC20;
    using SafeProxy for IProxy;

    uint256 private constant WEEK = 604800; // Number of seconds in a week

    /// @notice Yearn's voter proxy. Typically referred to as "voter".
    IProxy public constant proxy = IProxy(0xF147b8125d2ef93FB6965Db97D6746952a133934);
    IERC20 public constant CRVUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    /// @notice Recipient of weekly 3CRV admin fees. Default of yveCRV address.
    address public adminFeeRecipient;

    /// @notice Curve's fee distributor contract.
    FeeDistribution public constant feeDistribution = FeeDistribution(0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914);

    /// @notice Current governance address.
    address public governance;

    // Events so that indexers can keep track of key actions
    event GovernanceSet(address indexed governance);

    constructor(address _adminFeeRecipient) public {
        governance = msg.sender;
        adminFeeRecipient = _adminFeeRecipient;
    }
    
    /// @notice Set governance address.
    /// @dev Must be called by current governance.
    /// @param _governance Address to set as governance.
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        require(_governance != governance, "already set");
        governance = _governance;
        emit GovernanceSet(_governance);
    }

    /// @notice Claim share of weekly admin fees from Curve fee distributor.
    /// @dev Admin fees become available every Thursday at 00:00 UTC
    function claimAdminFees() external returns (uint amount) {
        require(msg.sender == adminFeeRecipient, "!authorized");
        if (canClaim()) {
            address p = address(proxy);
            feeDistribution.claim_many([p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p]);
        }
        amount = CRVUSD.balanceOf(address(proxy));
        if (amount > 0) {
            proxy.safeExecute(address(CRVUSD), 0, abi.encodeWithSignature("transfer(address,uint256)", adminFeeRecipient, amount));
        }
    }

    /// @notice Claim share of weekly admin fees from Curve fee distributor.
    /// @dev Admin fees become available every Thursday, so we run this expensive
    ///  logic only once per week. May only be called by feeRecipient.
    function forceClaimAdminFees(address _recipient) external returns (uint amount) {
        if (canClaim()) {
            address p = address(proxy);
            feeDistribution.claim_many([p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p]);
        }
        amount = CRVUSD.balanceOf(address(proxy));
        if (amount > 0) {
            proxy.safeExecute(address(CRVUSD), 0, abi.encodeWithSignature("transfer(address,uint256)", _recipient, amount));
        }
    }

    function setAdminFeeRecipient(address _recipient) external {
        require(msg.sender == governance, "!governance");
        adminFeeRecipient = _recipient;
    }

    /// @notice Check if it is possible to make an admin fee claim.
    function canClaim() public view returns (bool) {
        uint weekStart = block.timestamp / WEEK * WEEK;
        uint lastClaimWeek = feeDistribution.time_cursor_of(address(proxy));
        uint lastCheckpoint = feeDistribution.last_token_time();
        if (
            block.timestamp > lastClaimWeek + 1 weeks &&
            lastCheckpoint > weekStart
        ) return true;
        return false;
    }

    function _transferBalance(address _token) internal {
        proxy.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, IERC20(_token).balanceOf(address(proxy))));
    }
}