// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {INavAccountant} from "./EthStrategy.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./DutchAuction.sol";

contract NavOptions is OwnableRoles, ERC20 {

    /// @dev The role for the admin
    uint8 public constant ADMIN_ROLE = 3;
    address public immutable NAV_ACCOUNTANT;
    address public immutable ETH_STRATEGY;

    constructor(address _governor, address ethStrategy, address navAccountant) {
        _initializeOwner(_governor);
        ETH_STRATEGY = ethStrategy;
        NAV_ACCOUNTANT = navAccountant;
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

    function redeem(uint256 _amount) payable external {
      _burn(msg.sender, _amount);
      INavAccountant.NavValue[] memory navValues = INavAccountant(NAV_ACCOUNTANT).getNavValue(_amount, 0);
      for (uint256 i = 0; i < navValues.length; i++) {
        INavAccountant.NavValue memory navValue = navValues[i];
        if (navValue.token == address(0)) {
          SafeTransferLib.safeTransferETH(owner(), navValue.value);
          if(navValue.value < msg.value) {
            SafeTransferLib.safeTransferETH(msg.sender, msg.value - navValue.value);
          }
        } else {
          SafeTransferLib.safeTransferFrom(navValue.token, msg.sender, owner(), navValue.value);
        }
      }
      IEthStrategy(ETH_STRATEGY).mint(msg.sender, _amount);
    }
}
