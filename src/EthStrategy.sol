// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {ERC20Votes} from "solady/src/tokens/ERC20Votes.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

contract EthStrategy is ERC20Votes, OwnableRoles {
    /// @dev The role for the minter is able to mint unlimited tokens
    uint8 public constant MINTER_ROLE = 1;
    /// @dev The role of the pauser can pause transfers of tokens
    uint8 public constant PAUSER_ROLE = 2;
    /// @dev The transfer pause status, minting is still allowed
    bool public isTransferPaused = true;
    /// @dev The error for when a transfer is attempted but transfers are paused (minting is still allowed)

    error TransferPaused();
    /// @notice The constructor for the EthStrategy contract, initializes the owner
    /// @param _governor The address of the governor (owner())

    constructor(address _governor) {
        _initializeOwner(_governor);
    }
    /// @inheritdoc ERC20

    function name() public view virtual override returns (string memory) {
        return "EthStrategy";
    }
    /// @inheritdoc ERC20

    function symbol() public view virtual override returns (string memory) {
        return "ETHSR";
    }
    /// @notice A function to mint tokens, only callable by the owner or roles
    /// @param _to The address to mint the tokens to
    /// @param _amount The amount of tokens to mint

    function mint(address _to, uint256 _amount) public onlyOwnerOrRoles(MINTER_ROLE) {
        _mint(_to, _amount);
    }
    /// @notice OpenZeppelin IVotes implementation uses a different method than the Solady implementation (getPastTotalSupply vs. getPastVotesTotalSupply)
    /// @param timepoint The timepoint to get the past total supply for
    /// @return The past total supply

    function getPastTotalSupply(uint256 timepoint) public view virtual returns (uint256) {
        return getPastVotesTotalSupply(timepoint);
    }
    /// @inheritdoc ERC20

    function _beforeTokenTransfer(address from, address, uint256) internal virtual override {
        if (from != address(0) && isTransferPaused) {
            revert TransferPaused();
        }
    }
    /// @notice An external function to set the transfer pause status,
    /// @param _isTransferPaused The new transfer pause status

    function setIsTransferPaused(bool _isTransferPaused) public onlyOwnerOrRoles(PAUSER_ROLE) {
        isTransferPaused = _isTransferPaused;
    }
}
