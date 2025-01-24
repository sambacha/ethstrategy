// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {ERC20Votes} from "solady/src/tokens/ERC20Votes.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

contract EthStrategy is ERC20Votes, OwnableRoles {
    uint8 public constant MINTER_ROLE = 1;
    constructor(address _governor) {
        _initializeOwner(_governor);
    }
    function name() public view virtual override returns (string memory) {
        return "EthStrategy";
    }

    function symbol() public view virtual override returns (string memory) {
        return "ETHSR";
    }

    function mint(address _to, uint256 _amount) public onlyOwnerOrRoles(MINTER_ROLE) {
        _mint(_to, _amount);
    }

}

