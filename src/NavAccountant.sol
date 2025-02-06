// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract NavAccountant is OwnableRoles {
  address[] public navTokens;

  /// @dev The role for the admin
  uint8 public constant ADMIN_ROLE = 1;

  address public immutable ETH_STRATEGY;
  error AmountIsZero();

  struct NavValue {
    address token;
    uint256 value;
  }

  constructor(address _governor, address _ethStrategy) {
    _initializeOwner(_governor);
    ETH_STRATEGY = _ethStrategy;
  }

  function addNavToken(address _navToken) public onlyOwnerOrRoles(ADMIN_ROLE) {
    navTokens.push(_navToken);
  }

  function removeNavToken(address _navToken) public onlyOwnerOrRoles(ADMIN_ROLE) {
    uint256 i = 0;
    uint256 len = navTokens.length;
    for (;i < len;) {
      if (navTokens[i] == _navToken) {
        navTokens[i] = navTokens[len - 1];
        navTokens.pop();
        break;
      }
      unchecked {
        ++i;
      }
    }
  }

  function getNavValue(uint256 _amount, uint256 _discount) external view returns (NavValue[] memory navValues) {
    if(_amount == 0) {
      revert AmountIsZero();
    }
    uint256 totalSupply = IERC20(ETH_STRATEGY).totalSupply();
    navValues = new NavValue[](navTokens.length + 1);
    uint256 i = 0;
    uint256 len = navTokens.length;
    for (; i < len;) {
      address navToken = navTokens[i];
      uint256 value = IERC20(navToken).balanceOf(owner());
      uint256 proportion = value * _amount / totalSupply;
      if(value > 0 && proportion == 0) {
        proportion = 1;
      }
      if(_discount > 0) {
        proportion = proportion * (100 - _discount) / 100;
      }
      navValues[i] = NavValue({
        token: navToken,
        value: proportion
      });
      unchecked {
        ++i;
      }
    }
    navValues[i+1] = NavValue({
      token: address(0),
      value: owner().balance
    });
  }
}
