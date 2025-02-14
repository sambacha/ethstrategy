// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./EthStrategy.sol";

contract NavOptions is OwnableRoles, ERC20 {
    /// @dev The role for the admin
    uint8 public constant ADMIN_ROLE = 1;
    address public immutable ETH_STRATEGY;

    constructor(address _ethStrategy) {
        _initializeOwner(_ethStrategy);
        ETH_STRATEGY = _ethStrategy;
    }

    function name() public view virtual override returns (string memory) {
        return "EthStrategy Options";
    }

    function symbol() public view virtual override returns (string memory) {
        return "oETHxr";
    }

    function mint(address _to, uint256 _amount) external onlyRoles(ADMIN_ROLE) {
        _mint(_to, _amount);
    }

    function redeem(uint256 _amount) external payable {
        IEthStrategy ethStrategy = IEthStrategy(ETH_STRATEGY);
        IEthStrategy.NavValue[] memory navValues = ethStrategy.getNavValue(_amount, 0);
        _burn(msg.sender, _amount);
        for (uint256 i = 0; i < navValues.length; i++) {
            IEthStrategy.NavValue memory navValue = navValues[i];
            if (navValue.token == address(0)) {
                SafeTransferLib.safeTransferETH(address(ethStrategy), navValue.value);
                if (navValue.value < msg.value) {
                    SafeTransferLib.safeTransferETH(msg.sender, msg.value - navValue.value);
                }
            } else {
                SafeTransferLib.safeTransferFrom(navValue.token, msg.sender, address(ethStrategy), navValue.value);
            }
        }
        ethStrategy.mint(msg.sender, _amount);
    }
}
