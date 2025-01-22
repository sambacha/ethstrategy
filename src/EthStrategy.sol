// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {ERC20Votes} from "solady/src/tokens/ERC20Votes.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

contract EthStrategy is ERC20Votes, OwnableRoles {
    constructor(address _governor, address[] memory _minters) {
        _initializeOwner(_governor);
        _grantRoles(msg.sender, 1);
        for(uint256 i = 0; i < _minters.length; i++) {
            _grantRoles(_minters[i], 2);
        }
    }
    function name() public view virtual override returns (string memory) {
        return "EthStrategy";
    }

    function symbol() public view virtual override returns (string memory) {
        return "ETHSR";
    }

    function mint(address _to, uint256 _amount) public onlyOwnerOrRoles(2) {
        _mint(_to, _amount);
    }

}

