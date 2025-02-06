// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {NavAccountant} from "./NavAccountant.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./DutchAuction.sol";

interface INavAccountant {
  function getNavValue(uint256 _amount, uint256 _discount) external view returns (NavAccountant.NavValue[] memory navValues);
}

contract NavOptions is OwnableRoles, ERC20 {

    /// @dev The role for the admin
    uint8 public constant ADMIN_ROLE = 1;
    address public immutable NAV_ACCOUNTANT;
    address public immutable ETH_STRATEGY;
    uint256 public immutable MINT_CAP; // percentage in basis points
    uint256 public constant DENOMINATOR_BP = 100_00;

    error MintCapExceeded();

    constructor(address _governor, address ethStrategy, address navAccountant, uint256 mintCap) {
        _initializeOwner(_governor);
        ETH_STRATEGY = ethStrategy;
        NAV_ACCOUNTANT = navAccountant;
        MINT_CAP = mintCap;
    }

    function name() public view virtual override returns (string memory) {
      return "EthStrategy Options";
    }

    function symbol() public view virtual override returns (string memory) {
      return "oETHxr";
    }

    function mint(address _to, uint256 _amount) external onlyOwnerOrRoles(ADMIN_ROLE) {
        uint256 totalSupply = totalSupply();
        uint256 maxMint = totalSupply * MINT_CAP / DENOMINATOR_BP;
        if (totalSupply + _amount > maxMint) {
          revert MintCapExceeded();
        }
        _mint(_to, _amount);
    }

    function redeem(uint256 _amount) payable external {
      _burn(msg.sender, _amount);
      NavAccountant.NavValue[] memory navValues = INavAccountant(NAV_ACCOUNTANT).getNavValue(_amount, 0);
      for (uint256 i = 0; i < navValues.length; i++) {
        NavAccountant.NavValue memory navValue = navValues[i];
        if (navValue.token == address(0)) {
          SafeTransferLib.safeTransferETH(owner(), navValue.value);
        } else {
          SafeTransferLib.safeTransferFrom(navValue.token, msg.sender, owner(), navValue.value);
        }
      }
      IEthStrategy(ETH_STRATEGY).mint(msg.sender, _amount);
    }
}
