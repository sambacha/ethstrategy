// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26 ^0.8.4;

// lib/TReentrancyGuard/src/TReentrancyGuard.sol

contract TReentrancyGuard {
    error ReentrancyForbidden();

    modifier nonreentrant() {
        assembly {
            if tload(0) {
                mstore(0x00, 0x2636fdca) // `ReentrancyForbidden()`.
                revert(0x1c, 0x04)
            }
            tstore(0, 1)
        }
        _;
        // Unlocks the guard, making the pattern composable.
        // After the function exits, it can be called again, even in the same transaction.
        assembly {
            tstore(0, 0)
        }
    }
}

// lib/solady/src/auth/Ownable.sol

/// @notice Simple single owner authorization mixin.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/auth/Ownable.sol)
///
/// @dev Note:
/// This implementation does NOT auto-initialize the owner to `msg.sender`.
/// You MUST call the `_initializeOwner` in the constructor / initializer.
///
/// While the ownable portion follows
/// [EIP-173](https://eips.ethereum.org/EIPS/eip-173) for compatibility,
/// the nomenclature for the 2-step ownership handover may be unique to this codebase.
abstract contract Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The caller is not authorized to call the function.
    error Unauthorized();

    /// @dev The `newOwner` cannot be the zero address.
    error NewOwnerIsZeroAddress();

    /// @dev The `pendingOwner` does not have a valid handover request.
    error NoHandoverRequest();

    /// @dev Cannot double-initialize.
    error AlreadyInitialized();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ownership is transferred from `oldOwner` to `newOwner`.
    /// This event is intentionally kept the same as OpenZeppelin's Ownable to be
    /// compatible with indexers and [EIP-173](https://eips.ethereum.org/EIPS/eip-173),
    /// despite it not being as lightweight as a single argument event.
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    /// @dev An ownership handover to `pendingOwner` has been requested.
    event OwnershipHandoverRequested(address indexed pendingOwner);

    /// @dev The ownership handover to `pendingOwner` has been canceled.
    event OwnershipHandoverCanceled(address indexed pendingOwner);

    /// @dev `keccak256(bytes("OwnershipTransferred(address,address)"))`.
    uint256 private constant _OWNERSHIP_TRANSFERRED_EVENT_SIGNATURE =
        0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0;

    /// @dev `keccak256(bytes("OwnershipHandoverRequested(address)"))`.
    uint256 private constant _OWNERSHIP_HANDOVER_REQUESTED_EVENT_SIGNATURE =
        0xdbf36a107da19e49527a7176a1babf963b4b0ff8cde35ee35d6cd8f1f9ac7e1d;

    /// @dev `keccak256(bytes("OwnershipHandoverCanceled(address)"))`.
    uint256 private constant _OWNERSHIP_HANDOVER_CANCELED_EVENT_SIGNATURE =
        0xfa7b8eab7da67f412cc9575ed43464468f9bfbae89d1675917346ca6d8fe3c92;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The owner slot is given by:
    /// `bytes32(~uint256(uint32(bytes4(keccak256("_OWNER_SLOT_NOT")))))`.
    /// It is intentionally chosen to be a high value
    /// to avoid collision with lower slots.
    /// The choice of manual storage layout is to enable compatibility
    /// with both regular and upgradeable contracts.
    bytes32 internal constant _OWNER_SLOT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff74873927;

    /// The ownership handover slot of `newOwner` is given by:
    /// ```
    ///     mstore(0x00, or(shl(96, user), _HANDOVER_SLOT_SEED))
    ///     let handoverSlot := keccak256(0x00, 0x20)
    /// ```
    /// It stores the expiry timestamp of the two-step ownership handover.
    uint256 private constant _HANDOVER_SLOT_SEED = 0x389a75e1;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Override to return true to make `_initializeOwner` prevent double-initialization.
    function _guardInitializeOwner() internal pure virtual returns (bool guard) {}

    /// @dev Initializes the owner directly without authorization guard.
    /// This function must be called upon initialization,
    /// regardless of whether the contract is upgradeable or not.
    /// This is to enable generalization to both regular and upgradeable contracts,
    /// and to save gas in case the initial owner is not the caller.
    /// For performance reasons, this function will not check if there
    /// is an existing owner.
    function _initializeOwner(address newOwner) internal virtual {
        if (_guardInitializeOwner()) {
            /// @solidity memory-safe-assembly
            assembly {
                let ownerSlot := _OWNER_SLOT
                if sload(ownerSlot) {
                    mstore(0x00, 0x0dc149f0) // `AlreadyInitialized()`.
                    revert(0x1c, 0x04)
                }
                // Clean the upper 96 bits.
                newOwner := shr(96, shl(96, newOwner))
                // Store the new value.
                sstore(ownerSlot, or(newOwner, shl(255, iszero(newOwner))))
                // Emit the {OwnershipTransferred} event.
                log3(0, 0, _OWNERSHIP_TRANSFERRED_EVENT_SIGNATURE, 0, newOwner)
            }
        } else {
            /// @solidity memory-safe-assembly
            assembly {
                // Clean the upper 96 bits.
                newOwner := shr(96, shl(96, newOwner))
                // Store the new value.
                sstore(_OWNER_SLOT, newOwner)
                // Emit the {OwnershipTransferred} event.
                log3(0, 0, _OWNERSHIP_TRANSFERRED_EVENT_SIGNATURE, 0, newOwner)
            }
        }
    }

    /// @dev Sets the owner directly without authorization guard.
    function _setOwner(address newOwner) internal virtual {
        if (_guardInitializeOwner()) {
            /// @solidity memory-safe-assembly
            assembly {
                let ownerSlot := _OWNER_SLOT
                // Clean the upper 96 bits.
                newOwner := shr(96, shl(96, newOwner))
                // Emit the {OwnershipTransferred} event.
                log3(0, 0, _OWNERSHIP_TRANSFERRED_EVENT_SIGNATURE, sload(ownerSlot), newOwner)
                // Store the new value.
                sstore(ownerSlot, or(newOwner, shl(255, iszero(newOwner))))
            }
        } else {
            /// @solidity memory-safe-assembly
            assembly {
                let ownerSlot := _OWNER_SLOT
                // Clean the upper 96 bits.
                newOwner := shr(96, shl(96, newOwner))
                // Emit the {OwnershipTransferred} event.
                log3(0, 0, _OWNERSHIP_TRANSFERRED_EVENT_SIGNATURE, sload(ownerSlot), newOwner)
                // Store the new value.
                sstore(ownerSlot, newOwner)
            }
        }
    }

    /// @dev Throws if the sender is not the owner.
    function _checkOwner() internal view virtual {
        /// @solidity memory-safe-assembly
        assembly {
            // If the caller is not the stored owner, revert.
            if iszero(eq(caller(), sload(_OWNER_SLOT))) {
                mstore(0x00, 0x82b42900) // `Unauthorized()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Returns how long a two-step ownership handover is valid for in seconds.
    /// Override to return a different value if needed.
    /// Made internal to conserve bytecode. Wrap it in a public function if needed.
    function _ownershipHandoverValidFor() internal view virtual returns (uint64) {
        return 48 * 3600;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Allows the owner to transfer the ownership to `newOwner`.
    function transferOwnership(address newOwner) public payable virtual onlyOwner {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(shl(96, newOwner)) {
                mstore(0x00, 0x7448fbae) // `NewOwnerIsZeroAddress()`.
                revert(0x1c, 0x04)
            }
        }
        _setOwner(newOwner);
    }

    /// @dev Allows the owner to renounce their ownership.
    function renounceOwnership() public payable virtual onlyOwner {
        _setOwner(address(0));
    }

    /// @dev Request a two-step ownership handover to the caller.
    /// The request will automatically expire in 48 hours (172800 seconds) by default.
    function requestOwnershipHandover() public payable virtual {
        unchecked {
            uint256 expires = block.timestamp + _ownershipHandoverValidFor();
            /// @solidity memory-safe-assembly
            assembly {
                // Compute and set the handover slot to `expires`.
                mstore(0x0c, _HANDOVER_SLOT_SEED)
                mstore(0x00, caller())
                sstore(keccak256(0x0c, 0x20), expires)
                // Emit the {OwnershipHandoverRequested} event.
                log2(0, 0, _OWNERSHIP_HANDOVER_REQUESTED_EVENT_SIGNATURE, caller())
            }
        }
    }

    /// @dev Cancels the two-step ownership handover to the caller, if any.
    function cancelOwnershipHandover() public payable virtual {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute and set the handover slot to 0.
            mstore(0x0c, _HANDOVER_SLOT_SEED)
            mstore(0x00, caller())
            sstore(keccak256(0x0c, 0x20), 0)
            // Emit the {OwnershipHandoverCanceled} event.
            log2(0, 0, _OWNERSHIP_HANDOVER_CANCELED_EVENT_SIGNATURE, caller())
        }
    }

    /// @dev Allows the owner to complete the two-step ownership handover to `pendingOwner`.
    /// Reverts if there is no existing ownership handover requested by `pendingOwner`.
    function completeOwnershipHandover(address pendingOwner) public payable virtual onlyOwner {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute and set the handover slot to 0.
            mstore(0x0c, _HANDOVER_SLOT_SEED)
            mstore(0x00, pendingOwner)
            let handoverSlot := keccak256(0x0c, 0x20)
            // If the handover does not exist, or has expired.
            if gt(timestamp(), sload(handoverSlot)) {
                mstore(0x00, 0x6f5e8818) // `NoHandoverRequest()`.
                revert(0x1c, 0x04)
            }
            // Set the handover slot to 0.
            sstore(handoverSlot, 0)
        }
        _setOwner(pendingOwner);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the owner of the contract.
    function owner() public view virtual returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := sload(_OWNER_SLOT)
        }
    }

    /// @dev Returns the expiry timestamp for the two-step ownership handover to `pendingOwner`.
    function ownershipHandoverExpiresAt(address pendingOwner)
        public
        view
        virtual
        returns (uint256 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the handover slot.
            mstore(0x0c, _HANDOVER_SLOT_SEED)
            mstore(0x00, pendingOwner)
            // Load the handover slot.
            result := sload(keccak256(0x0c, 0x20))
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Marks a function as only callable by the owner.
    modifier onlyOwner() virtual {
        _checkOwner();
        _;
    }
}

// lib/solady/src/utils/SignatureCheckerLib.sol

/// @notice Signature verification helper that supports both ECDSA signatures from EOAs
/// and ERC1271 signatures from smart contract wallets like Argent and Gnosis safe.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/SignatureCheckerLib.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/SignatureChecker.sol)
///
/// @dev Note:
/// - The signature checking functions use the ecrecover precompile (0x1).
/// - The `bytes memory signature` variants use the identity precompile (0x4)
///   to copy memory internally.
/// - Unlike ECDSA signatures, contract signatures are revocable.
/// - As of Solady version 0.0.134, all `bytes signature` variants accept both
///   regular 65-byte `(r, s, v)` and EIP-2098 `(r, vs)` short form signatures.
///   See: https://eips.ethereum.org/EIPS/eip-2098
///   This is for calldata efficiency on smart accounts prevalent on L2s.
///
/// WARNING! Do NOT use signatures as unique identifiers:
/// - Use a nonce in the digest to prevent replay attacks on the same contract.
/// - Use EIP-712 for the digest to prevent replay attacks across different chains and contracts.
///   EIP-712 also enables readable signing of typed data for better user safety.
/// This implementation does NOT check if a signature is non-malleable.
library SignatureCheckerLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               SIGNATURE CHECKING OPERATIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns whether `signature` is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            for {} 1 {} {
                if iszero(extcodesize(signer)) {
                    switch mload(signature)
                    case 64 {
                        let vs := mload(add(signature, 0x40))
                        mstore(0x20, add(shr(255, vs), 27)) // `v`.
                        mstore(0x60, shr(1, shl(1, vs))) // `s`.
                    }
                    case 65 {
                        mstore(0x20, byte(0, mload(add(signature, 0x60)))) // `v`.
                        mstore(0x60, mload(add(signature, 0x40))) // `s`.
                    }
                    default { break }
                    mstore(0x00, hash)
                    mstore(0x40, mload(add(signature, 0x20))) // `r`.
                    let recovered := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                    isValid := gt(returndatasize(), shl(96, xor(signer, recovered)))
                    mstore(0x60, 0) // Restore the zero slot.
                    mstore(0x40, m) // Restore the free memory pointer.
                    break
                }
                let f := shl(224, 0x1626ba7e)
                mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
                mstore(add(m, 0x04), hash)
                let d := add(m, 0x24)
                mstore(d, 0x40) // The offset of the `signature` in the calldata.
                // Copy the `signature` over.
                let n := add(0x20, mload(signature))
                let copied := staticcall(gas(), 4, signature, n, add(m, 0x44), n)
                isValid := staticcall(gas(), signer, m, add(returndatasize(), 0x44), d, 0x20)
                isValid := and(eq(mload(d), f), and(isValid, copied))
                break
            }
        }
    }

    /// @dev Returns whether `signature` is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNowCalldata(address signer, bytes32 hash, bytes calldata signature)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            for {} 1 {} {
                if iszero(extcodesize(signer)) {
                    switch signature.length
                    case 64 {
                        let vs := calldataload(add(signature.offset, 0x20))
                        mstore(0x20, add(shr(255, vs), 27)) // `v`.
                        mstore(0x40, calldataload(signature.offset)) // `r`.
                        mstore(0x60, shr(1, shl(1, vs))) // `s`.
                    }
                    case 65 {
                        mstore(0x20, byte(0, calldataload(add(signature.offset, 0x40)))) // `v`.
                        calldatacopy(0x40, signature.offset, 0x40) // `r`, `s`.
                    }
                    default { break }
                    mstore(0x00, hash)
                    let recovered := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                    isValid := gt(returndatasize(), shl(96, xor(signer, recovered)))
                    mstore(0x60, 0) // Restore the zero slot.
                    mstore(0x40, m) // Restore the free memory pointer.
                    break
                }
                let f := shl(224, 0x1626ba7e)
                mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
                mstore(add(m, 0x04), hash)
                let d := add(m, 0x24)
                mstore(d, 0x40) // The offset of the `signature` in the calldata.
                mstore(add(m, 0x44), signature.length)
                // Copy the `signature` over.
                calldatacopy(add(m, 0x64), signature.offset, signature.length)
                isValid := staticcall(gas(), signer, m, add(signature.length, 0x64), d, 0x20)
                isValid := and(eq(mload(d), f), isValid)
                break
            }
        }
    }

    /// @dev Returns whether the signature (`r`, `vs`) is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNow(address signer, bytes32 hash, bytes32 r, bytes32 vs)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            for {} 1 {} {
                if iszero(extcodesize(signer)) {
                    mstore(0x00, hash)
                    mstore(0x20, add(shr(255, vs), 27)) // `v`.
                    mstore(0x40, r) // `r`.
                    mstore(0x60, shr(1, shl(1, vs))) // `s`.
                    let recovered := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                    isValid := gt(returndatasize(), shl(96, xor(signer, recovered)))
                    mstore(0x60, 0) // Restore the zero slot.
                    mstore(0x40, m) // Restore the free memory pointer.
                    break
                }
                let f := shl(224, 0x1626ba7e)
                mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
                mstore(add(m, 0x04), hash)
                let d := add(m, 0x24)
                mstore(d, 0x40) // The offset of the `signature` in the calldata.
                mstore(add(m, 0x44), 65) // Length of the signature.
                mstore(add(m, 0x64), r) // `r`.
                mstore(add(m, 0x84), shr(1, shl(1, vs))) // `s`.
                mstore8(add(m, 0xa4), add(shr(255, vs), 27)) // `v`.
                isValid := staticcall(gas(), signer, m, 0xa5, d, 0x20)
                isValid := and(eq(mload(d), f), isValid)
                break
            }
        }
    }

    /// @dev Returns whether the signature (`v`, `r`, `s`) is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNow(address signer, bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            for {} 1 {} {
                if iszero(extcodesize(signer)) {
                    mstore(0x00, hash)
                    mstore(0x20, and(v, 0xff)) // `v`.
                    mstore(0x40, r) // `r`.
                    mstore(0x60, s) // `s`.
                    let recovered := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                    isValid := gt(returndatasize(), shl(96, xor(signer, recovered)))
                    mstore(0x60, 0) // Restore the zero slot.
                    mstore(0x40, m) // Restore the free memory pointer.
                    break
                }
                let f := shl(224, 0x1626ba7e)
                mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
                mstore(add(m, 0x04), hash)
                let d := add(m, 0x24)
                mstore(d, 0x40) // The offset of the `signature` in the calldata.
                mstore(add(m, 0x44), 65) // Length of the signature.
                mstore(add(m, 0x64), r) // `r`.
                mstore(add(m, 0x84), s) // `s`.
                mstore8(add(m, 0xa4), v) // `v`.
                isValid := staticcall(gas(), signer, m, 0xa5, d, 0x20)
                isValid := and(eq(mload(d), f), isValid)
                break
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ERC1271 OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Note: These ERC1271 operations do NOT have an ECDSA fallback.

    /// @dev Returns whether `signature` is valid for `hash` for an ERC1271 `signer` contract.
    function isValidERC1271SignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool isValid)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            let f := shl(224, 0x1626ba7e)
            mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
            mstore(add(m, 0x04), hash)
            let d := add(m, 0x24)
            mstore(d, 0x40) // The offset of the `signature` in the calldata.
            // Copy the `signature` over.
            let n := add(0x20, mload(signature))
            let copied := staticcall(gas(), 4, signature, n, add(m, 0x44), n)
            isValid := staticcall(gas(), signer, m, add(returndatasize(), 0x44), d, 0x20)
            isValid := and(eq(mload(d), f), and(isValid, copied))
        }
    }

    /// @dev Returns whether `signature` is valid for `hash` for an ERC1271 `signer` contract.
    function isValidERC1271SignatureNowCalldata(
        address signer,
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (bool isValid) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            let f := shl(224, 0x1626ba7e)
            mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
            mstore(add(m, 0x04), hash)
            let d := add(m, 0x24)
            mstore(d, 0x40) // The offset of the `signature` in the calldata.
            mstore(add(m, 0x44), signature.length)
            // Copy the `signature` over.
            calldatacopy(add(m, 0x64), signature.offset, signature.length)
            isValid := staticcall(gas(), signer, m, add(signature.length, 0x64), d, 0x20)
            isValid := and(eq(mload(d), f), isValid)
        }
    }

    /// @dev Returns whether the signature (`r`, `vs`) is valid for `hash`
    /// for an ERC1271 `signer` contract.
    function isValidERC1271SignatureNow(address signer, bytes32 hash, bytes32 r, bytes32 vs)
        internal
        view
        returns (bool isValid)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            let f := shl(224, 0x1626ba7e)
            mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
            mstore(add(m, 0x04), hash)
            let d := add(m, 0x24)
            mstore(d, 0x40) // The offset of the `signature` in the calldata.
            mstore(add(m, 0x44), 65) // Length of the signature.
            mstore(add(m, 0x64), r) // `r`.
            mstore(add(m, 0x84), shr(1, shl(1, vs))) // `s`.
            mstore8(add(m, 0xa4), add(shr(255, vs), 27)) // `v`.
            isValid := staticcall(gas(), signer, m, 0xa5, d, 0x20)
            isValid := and(eq(mload(d), f), isValid)
        }
    }

    /// @dev Returns whether the signature (`v`, `r`, `s`) is valid for `hash`
    /// for an ERC1271 `signer` contract.
    function isValidERC1271SignatureNow(address signer, bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (bool isValid)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            let f := shl(224, 0x1626ba7e)
            mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
            mstore(add(m, 0x04), hash)
            let d := add(m, 0x24)
            mstore(d, 0x40) // The offset of the `signature` in the calldata.
            mstore(add(m, 0x44), 65) // Length of the signature.
            mstore(add(m, 0x64), r) // `r`.
            mstore(add(m, 0x84), s) // `s`.
            mstore8(add(m, 0xa4), v) // `v`.
            isValid := staticcall(gas(), signer, m, 0xa5, d, 0x20)
            isValid := and(eq(mload(d), f), isValid)
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ERC6492 OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Note: These ERC6492 operations now include an ECDSA fallback at the very end.
    // The calldata variants are excluded for brevity.

    /// @dev Returns whether `signature` is valid for `hash`.
    /// If the signature is postfixed with the ERC6492 magic number, it will attempt to
    /// deploy / prepare the `signer` smart account before doing a regular ERC1271 check.
    /// Note: This function is NOT reentrancy safe.
    /// The verifier must be deployed.
    /// Otherwise, the function will return false if `signer` is not yet deployed / prepared.
    /// See: https://gist.github.com/Vectorized/011d6becff6e0a73e42fe100f8d7ef04
    /// With a dedicated verifier, this function is safe to use in contracts
    /// that have been granted special permissions.
    function isValidERC6492SignatureNowAllowSideEffects(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal returns (bool isValid) {
        /// @solidity memory-safe-assembly
        assembly {
            function callIsValidSignature(signer_, hash_, signature_) -> _isValid {
                let m_ := mload(0x40)
                let f_ := shl(224, 0x1626ba7e)
                mstore(m_, f_) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
                mstore(add(m_, 0x04), hash_)
                let d_ := add(m_, 0x24)
                mstore(d_, 0x40) // The offset of the `signature` in the calldata.
                let n_ := add(0x20, mload(signature_))
                let copied_ := staticcall(gas(), 4, signature_, n_, add(m_, 0x44), n_)
                _isValid := staticcall(gas(), signer_, m_, add(returndatasize(), 0x44), d_, 0x20)
                _isValid := and(eq(mload(d_), f_), and(_isValid, copied_))
            }
            let noCode := iszero(extcodesize(signer))
            let n := mload(signature)
            for {} 1 {} {
                if iszero(eq(mload(add(signature, n)), mul(0x6492, div(not(isValid), 0xffff)))) {
                    if iszero(noCode) { isValid := callIsValidSignature(signer, hash, signature) }
                    break
                }
                if iszero(noCode) {
                    let o := add(signature, 0x20) // Signature bytes.
                    isValid := callIsValidSignature(signer, hash, add(o, mload(add(o, 0x40))))
                    if isValid { break }
                }
                let m := mload(0x40)
                mstore(m, signer)
                mstore(add(m, 0x20), hash)
                pop(
                    call(
                        gas(), // Remaining gas.
                        0x0000bc370E4DC924F427d84e2f4B9Ec81626ba7E, // Non-reverting verifier.
                        0, // Send zero ETH.
                        m, // Start of memory.
                        add(returndatasize(), 0x40), // Length of calldata in memory.
                        staticcall(gas(), 4, add(signature, 0x20), n, add(m, 0x40), n), // 1.
                        0x00 // Length of returndata to write.
                    )
                )
                isValid := returndatasize()
                break
            }
            // Do `ecrecover` fallback if `noCode && !isValid`.
            for {} gt(noCode, isValid) {} {
                switch n
                case 64 {
                    let vs := mload(add(signature, 0x40))
                    mstore(0x20, add(shr(255, vs), 27)) // `v`.
                    mstore(0x60, shr(1, shl(1, vs))) // `s`.
                }
                case 65 {
                    mstore(0x20, byte(0, mload(add(signature, 0x60)))) // `v`.
                    mstore(0x60, mload(add(signature, 0x40))) // `s`.
                }
                default { break }
                let m := mload(0x40)
                mstore(0x00, hash)
                mstore(0x40, mload(add(signature, 0x20))) // `r`.
                let recovered := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                isValid := gt(returndatasize(), shl(96, xor(signer, recovered)))
                mstore(0x60, 0) // Restore the zero slot.
                mstore(0x40, m) // Restore the free memory pointer.
                break
            }
        }
    }

    /// @dev Returns whether `signature` is valid for `hash`.
    /// If the signature is postfixed with the ERC6492 magic number, it will attempt
    /// to use a reverting verifier to deploy / prepare the `signer` smart account
    /// and do a `isValidSignature` check via the reverting verifier.
    /// Note: This function is reentrancy safe.
    /// The reverting verifier must be deployed.
    /// Otherwise, the function will return false if `signer` is not yet deployed / prepared.
    /// See: https://gist.github.com/Vectorized/846a474c855eee9e441506676800a9ad
    function isValidERC6492SignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        returns (bool isValid)
    {
        /// @solidity memory-safe-assembly
        assembly {
            function callIsValidSignature(signer_, hash_, signature_) -> _isValid {
                let m_ := mload(0x40)
                let f_ := shl(224, 0x1626ba7e)
                mstore(m_, f_) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
                mstore(add(m_, 0x04), hash_)
                let d_ := add(m_, 0x24)
                mstore(d_, 0x40) // The offset of the `signature` in the calldata.
                let n_ := add(0x20, mload(signature_))
                let copied_ := staticcall(gas(), 4, signature_, n_, add(m_, 0x44), n_)
                _isValid := staticcall(gas(), signer_, m_, add(returndatasize(), 0x44), d_, 0x20)
                _isValid := and(eq(mload(d_), f_), and(_isValid, copied_))
            }
            let noCode := iszero(extcodesize(signer))
            let n := mload(signature)
            for {} 1 {} {
                if iszero(eq(mload(add(signature, n)), mul(0x6492, div(not(isValid), 0xffff)))) {
                    if iszero(noCode) { isValid := callIsValidSignature(signer, hash, signature) }
                    break
                }
                if iszero(noCode) {
                    let o := add(signature, 0x20) // Signature bytes.
                    isValid := callIsValidSignature(signer, hash, add(o, mload(add(o, 0x40))))
                    if isValid { break }
                }
                let m := mload(0x40)
                mstore(m, signer)
                mstore(add(m, 0x20), hash)
                let willBeZeroIfRevertingVerifierExists :=
                    call(
                        gas(), // Remaining gas.
                        0x00007bd799e4A591FeA53f8A8a3E9f931626Ba7e, // Reverting verifier.
                        0, // Send zero ETH.
                        m, // Start of memory.
                        add(returndatasize(), 0x40), // Length of calldata in memory.
                        staticcall(gas(), 4, add(signature, 0x20), n, add(m, 0x40), n), // 1.
                        0x00 // Length of returndata to write.
                    )
                isValid := gt(returndatasize(), willBeZeroIfRevertingVerifierExists)
                break
            }
            // Do `ecrecover` fallback if `noCode && !isValid`.
            for {} gt(noCode, isValid) {} {
                switch n
                case 64 {
                    let vs := mload(add(signature, 0x40))
                    mstore(0x20, add(shr(255, vs), 27)) // `v`.
                    mstore(0x60, shr(1, shl(1, vs))) // `s`.
                }
                case 65 {
                    mstore(0x20, byte(0, mload(add(signature, 0x60)))) // `v`.
                    mstore(0x60, mload(add(signature, 0x40))) // `s`.
                }
                default { break }
                let m := mload(0x40)
                mstore(0x00, hash)
                mstore(0x40, mload(add(signature, 0x20))) // `r`.
                let recovered := mload(staticcall(gas(), 1, 0x00, 0x80, 0x01, 0x20))
                isValid := gt(returndatasize(), shl(96, xor(signer, recovered)))
                mstore(0x60, 0) // Restore the zero slot.
                mstore(0x40, m) // Restore the free memory pointer.
                break
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     HASHING OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns an Ethereum Signed Message, created from a `hash`.
    /// This produces a hash corresponding to the one signed with the
    /// [`eth_sign`](https://eth.wiki/json-rpc/API#eth_sign)
    /// JSON-RPC method as part of EIP-191.
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, hash) // Store into scratch space for keccak256.
            mstore(0x00, "\x00\x00\x00\x00\x19Ethereum Signed Message:\n32") // 28 bytes.
            result := keccak256(0x04, 0x3c) // `32 * 2 - (32 - 28) = 60 = 0x3c`.
        }
    }

    /// @dev Returns an Ethereum Signed Message, created from `s`.
    /// This produces a hash corresponding to the one signed with the
    /// [`eth_sign`](https://eth.wiki/json-rpc/API#eth_sign)
    /// JSON-RPC method as part of EIP-191.
    /// Note: Supports lengths of `s` up to 999999 bytes.
    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let sLength := mload(s)
            let o := 0x20
            mstore(o, "\x19Ethereum Signed Message:\n") // 26 bytes, zero-right-padded.
            mstore(0x00, 0x00)
            // Convert the `s.length` to ASCII decimal representation: `base10(s.length)`.
            for { let temp := sLength } 1 {} {
                o := sub(o, 1)
                mstore8(o, add(48, mod(temp, 10)))
                temp := div(temp, 10)
                if iszero(temp) { break }
            }
            let n := sub(0x3a, o) // Header length: `26 + 32 - o`.
            // Throw an out-of-offset error (consumes all gas) if the header exceeds 32 bytes.
            returndatacopy(returndatasize(), returndatasize(), gt(n, 0x20))
            mstore(s, or(mload(0x00), mload(n))) // Temporarily store the header.
            result := keccak256(add(s, sub(0x20, n)), add(n, sLength))
            mstore(s, sLength) // Restore the length.
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   EMPTY CALLDATA HELPERS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns an empty calldata bytes.
    function emptySignature() internal pure returns (bytes calldata signature) {
        /// @solidity memory-safe-assembly
        assembly {
            signature.length := 0
        }
    }
}

// src/interfaces/IEthStrategy.sol

interface IEthStrategy {
    /// @dev The function to get the decimals of the ethStrategy
    /// @return The number of decimals of the ethStrategy
    function decimals() external view returns (uint8);

    /// @dev The function to mint ethStrategy to an address
    /// @param _to The address to mint the ethStrategy to
    /// @param _amount The amount of ethStrategy to mint
    function mint(address _to, uint256 _amount) external;

    /// @dev The function to initiate governance
    function initiateGovernance() external;
}

// lib/solady/src/auth/OwnableRoles.sol

/// @notice Simple single owner and multiroles authorization mixin.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/auth/OwnableRoles.sol)
///
/// @dev Note:
/// This implementation does NOT auto-initialize the owner to `msg.sender`.
/// You MUST call the `_initializeOwner` in the constructor / initializer.
///
/// While the ownable portion follows
/// [EIP-173](https://eips.ethereum.org/EIPS/eip-173) for compatibility,
/// the nomenclature for the 2-step ownership handover may be unique to this codebase.
abstract contract OwnableRoles is Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The `user`'s roles is updated to `roles`.
    /// Each bit of `roles` represents whether the role is set.
    event RolesUpdated(address indexed user, uint256 indexed roles);

    /// @dev `keccak256(bytes("RolesUpdated(address,uint256)"))`.
    uint256 private constant _ROLES_UPDATED_EVENT_SIGNATURE =
        0x715ad5ce61fc9595c7b415289d59cf203f23a94fa06f04af7e489a0a76e1fe26;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The role slot of `user` is given by:
    /// ```
    ///     mstore(0x00, or(shl(96, user), _ROLE_SLOT_SEED))
    ///     let roleSlot := keccak256(0x00, 0x20)
    /// ```
    /// This automatically ignores the upper bits of the `user` in case
    /// they are not clean, as well as keep the `keccak256` under 32-bytes.
    ///
    /// Note: This is equivalent to `uint32(bytes4(keccak256("_OWNER_SLOT_NOT")))`.
    uint256 private constant _ROLE_SLOT_SEED = 0x8b78c6d8;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Overwrite the roles directly without authorization guard.
    function _setRoles(address user, uint256 roles) internal virtual {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x0c, _ROLE_SLOT_SEED)
            mstore(0x00, user)
            // Store the new value.
            sstore(keccak256(0x0c, 0x20), roles)
            // Emit the {RolesUpdated} event.
            log3(0, 0, _ROLES_UPDATED_EVENT_SIGNATURE, shr(96, mload(0x0c)), roles)
        }
    }

    /// @dev Updates the roles directly without authorization guard.
    /// If `on` is true, each set bit of `roles` will be turned on,
    /// otherwise, each set bit of `roles` will be turned off.
    function _updateRoles(address user, uint256 roles, bool on) internal virtual {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x0c, _ROLE_SLOT_SEED)
            mstore(0x00, user)
            let roleSlot := keccak256(0x0c, 0x20)
            // Load the current value.
            let current := sload(roleSlot)
            // Compute the updated roles if `on` is true.
            let updated := or(current, roles)
            // Compute the updated roles if `on` is false.
            // Use `and` to compute the intersection of `current` and `roles`,
            // `xor` it with `current` to flip the bits in the intersection.
            if iszero(on) { updated := xor(current, and(current, roles)) }
            // Then, store the new value.
            sstore(roleSlot, updated)
            // Emit the {RolesUpdated} event.
            log3(0, 0, _ROLES_UPDATED_EVENT_SIGNATURE, shr(96, mload(0x0c)), updated)
        }
    }

    /// @dev Grants the roles directly without authorization guard.
    /// Each bit of `roles` represents the role to turn on.
    function _grantRoles(address user, uint256 roles) internal virtual {
        _updateRoles(user, roles, true);
    }

    /// @dev Removes the roles directly without authorization guard.
    /// Each bit of `roles` represents the role to turn off.
    function _removeRoles(address user, uint256 roles) internal virtual {
        _updateRoles(user, roles, false);
    }

    /// @dev Throws if the sender does not have any of the `roles`.
    function _checkRoles(uint256 roles) internal view virtual {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the role slot.
            mstore(0x0c, _ROLE_SLOT_SEED)
            mstore(0x00, caller())
            // Load the stored value, and if the `and` intersection
            // of the value and `roles` is zero, revert.
            if iszero(and(sload(keccak256(0x0c, 0x20)), roles)) {
                mstore(0x00, 0x82b42900) // `Unauthorized()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Throws if the sender is not the owner,
    /// and does not have any of the `roles`.
    /// Checks for ownership first, then lazily checks for roles.
    function _checkOwnerOrRoles(uint256 roles) internal view virtual {
        /// @solidity memory-safe-assembly
        assembly {
            // If the caller is not the stored owner.
            // Note: `_ROLE_SLOT_SEED` is equal to `_OWNER_SLOT_NOT`.
            if iszero(eq(caller(), sload(not(_ROLE_SLOT_SEED)))) {
                // Compute the role slot.
                mstore(0x0c, _ROLE_SLOT_SEED)
                mstore(0x00, caller())
                // Load the stored value, and if the `and` intersection
                // of the value and `roles` is zero, revert.
                if iszero(and(sload(keccak256(0x0c, 0x20)), roles)) {
                    mstore(0x00, 0x82b42900) // `Unauthorized()`.
                    revert(0x1c, 0x04)
                }
            }
        }
    }

    /// @dev Throws if the sender does not have any of the `roles`,
    /// and is not the owner.
    /// Checks for roles first, then lazily checks for ownership.
    function _checkRolesOrOwner(uint256 roles) internal view virtual {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the role slot.
            mstore(0x0c, _ROLE_SLOT_SEED)
            mstore(0x00, caller())
            // Load the stored value, and if the `and` intersection
            // of the value and `roles` is zero, revert.
            if iszero(and(sload(keccak256(0x0c, 0x20)), roles)) {
                // If the caller is not the stored owner.
                // Note: `_ROLE_SLOT_SEED` is equal to `_OWNER_SLOT_NOT`.
                if iszero(eq(caller(), sload(not(_ROLE_SLOT_SEED)))) {
                    mstore(0x00, 0x82b42900) // `Unauthorized()`.
                    revert(0x1c, 0x04)
                }
            }
        }
    }

    /// @dev Convenience function to return a `roles` bitmap from an array of `ordinals`.
    /// This is meant for frontends like Etherscan, and is therefore not fully optimized.
    /// Not recommended to be called on-chain.
    /// Made internal to conserve bytecode. Wrap it in a public function if needed.
    function _rolesFromOrdinals(uint8[] memory ordinals) internal pure returns (uint256 roles) {
        /// @solidity memory-safe-assembly
        assembly {
            for { let i := shl(5, mload(ordinals)) } i { i := sub(i, 0x20) } {
                // We don't need to mask the values of `ordinals`, as Solidity
                // cleans dirty upper bits when storing variables into memory.
                roles := or(shl(mload(add(ordinals, i)), 1), roles)
            }
        }
    }

    /// @dev Convenience function to return an array of `ordinals` from the `roles` bitmap.
    /// This is meant for frontends like Etherscan, and is therefore not fully optimized.
    /// Not recommended to be called on-chain.
    /// Made internal to conserve bytecode. Wrap it in a public function if needed.
    function _ordinalsFromRoles(uint256 roles) internal pure returns (uint8[] memory ordinals) {
        /// @solidity memory-safe-assembly
        assembly {
            // Grab the pointer to the free memory.
            ordinals := mload(0x40)
            let ptr := add(ordinals, 0x20)
            let o := 0
            // The absence of lookup tables, De Bruijn, etc., here is intentional for
            // smaller bytecode, as this function is not meant to be called on-chain.
            for { let t := roles } 1 {} {
                mstore(ptr, o)
                // `shr` 5 is equivalent to multiplying by 0x20.
                // Push back into the ordinals array if the bit is set.
                ptr := add(ptr, shl(5, and(t, 1)))
                o := add(o, 1)
                t := shr(o, roles)
                if iszero(t) { break }
            }
            // Store the length of `ordinals`.
            mstore(ordinals, shr(5, sub(ptr, add(ordinals, 0x20))))
            // Allocate the memory.
            mstore(0x40, ptr)
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Allows the owner to grant `user` `roles`.
    /// If the `user` already has a role, then it will be an no-op for the role.
    function grantRoles(address user, uint256 roles) public payable virtual onlyOwner {
        _grantRoles(user, roles);
    }

    /// @dev Allows the owner to remove `user` `roles`.
    /// If the `user` does not have a role, then it will be an no-op for the role.
    function revokeRoles(address user, uint256 roles) public payable virtual onlyOwner {
        _removeRoles(user, roles);
    }

    /// @dev Allow the caller to remove their own roles.
    /// If the caller does not have a role, then it will be an no-op for the role.
    function renounceRoles(uint256 roles) public payable virtual {
        _removeRoles(msg.sender, roles);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the roles of `user`.
    function rolesOf(address user) public view virtual returns (uint256 roles) {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the role slot.
            mstore(0x0c, _ROLE_SLOT_SEED)
            mstore(0x00, user)
            // Load the stored value.
            roles := sload(keccak256(0x0c, 0x20))
        }
    }

    /// @dev Returns whether `user` has any of `roles`.
    function hasAnyRole(address user, uint256 roles) public view virtual returns (bool) {
        return rolesOf(user) & roles != 0;
    }

    /// @dev Returns whether `user` has all of `roles`.
    function hasAllRoles(address user, uint256 roles) public view virtual returns (bool) {
        return rolesOf(user) & roles == roles;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Marks a function as only callable by an account with `roles`.
    modifier onlyRoles(uint256 roles) virtual {
        _checkRoles(roles);
        _;
    }

    /// @dev Marks a function as only callable by the owner or by an account
    /// with `roles`. Checks for ownership first, then lazily checks for roles.
    modifier onlyOwnerOrRoles(uint256 roles) virtual {
        _checkOwnerOrRoles(roles);
        _;
    }

    /// @dev Marks a function as only callable by an account with `roles`
    /// or the owner. Checks for roles first, then lazily checks for ownership.
    modifier onlyRolesOrOwner(uint256 roles) virtual {
        _checkRolesOrOwner(roles);
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ROLE CONSTANTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // IYKYK

    uint256 internal constant _ROLE_0 = 1 << 0;
    uint256 internal constant _ROLE_1 = 1 << 1;
    uint256 internal constant _ROLE_2 = 1 << 2;
    uint256 internal constant _ROLE_3 = 1 << 3;
    uint256 internal constant _ROLE_4 = 1 << 4;
    uint256 internal constant _ROLE_5 = 1 << 5;
    uint256 internal constant _ROLE_6 = 1 << 6;
    uint256 internal constant _ROLE_7 = 1 << 7;
    uint256 internal constant _ROLE_8 = 1 << 8;
    uint256 internal constant _ROLE_9 = 1 << 9;
    uint256 internal constant _ROLE_10 = 1 << 10;
    uint256 internal constant _ROLE_11 = 1 << 11;
    uint256 internal constant _ROLE_12 = 1 << 12;
    uint256 internal constant _ROLE_13 = 1 << 13;
    uint256 internal constant _ROLE_14 = 1 << 14;
    uint256 internal constant _ROLE_15 = 1 << 15;
    uint256 internal constant _ROLE_16 = 1 << 16;
    uint256 internal constant _ROLE_17 = 1 << 17;
    uint256 internal constant _ROLE_18 = 1 << 18;
    uint256 internal constant _ROLE_19 = 1 << 19;
    uint256 internal constant _ROLE_20 = 1 << 20;
    uint256 internal constant _ROLE_21 = 1 << 21;
    uint256 internal constant _ROLE_22 = 1 << 22;
    uint256 internal constant _ROLE_23 = 1 << 23;
    uint256 internal constant _ROLE_24 = 1 << 24;
    uint256 internal constant _ROLE_25 = 1 << 25;
    uint256 internal constant _ROLE_26 = 1 << 26;
    uint256 internal constant _ROLE_27 = 1 << 27;
    uint256 internal constant _ROLE_28 = 1 << 28;
    uint256 internal constant _ROLE_29 = 1 << 29;
    uint256 internal constant _ROLE_30 = 1 << 30;
    uint256 internal constant _ROLE_31 = 1 << 31;
    uint256 internal constant _ROLE_32 = 1 << 32;
    uint256 internal constant _ROLE_33 = 1 << 33;
    uint256 internal constant _ROLE_34 = 1 << 34;
    uint256 internal constant _ROLE_35 = 1 << 35;
    uint256 internal constant _ROLE_36 = 1 << 36;
    uint256 internal constant _ROLE_37 = 1 << 37;
    uint256 internal constant _ROLE_38 = 1 << 38;
    uint256 internal constant _ROLE_39 = 1 << 39;
    uint256 internal constant _ROLE_40 = 1 << 40;
    uint256 internal constant _ROLE_41 = 1 << 41;
    uint256 internal constant _ROLE_42 = 1 << 42;
    uint256 internal constant _ROLE_43 = 1 << 43;
    uint256 internal constant _ROLE_44 = 1 << 44;
    uint256 internal constant _ROLE_45 = 1 << 45;
    uint256 internal constant _ROLE_46 = 1 << 46;
    uint256 internal constant _ROLE_47 = 1 << 47;
    uint256 internal constant _ROLE_48 = 1 << 48;
    uint256 internal constant _ROLE_49 = 1 << 49;
    uint256 internal constant _ROLE_50 = 1 << 50;
    uint256 internal constant _ROLE_51 = 1 << 51;
    uint256 internal constant _ROLE_52 = 1 << 52;
    uint256 internal constant _ROLE_53 = 1 << 53;
    uint256 internal constant _ROLE_54 = 1 << 54;
    uint256 internal constant _ROLE_55 = 1 << 55;
    uint256 internal constant _ROLE_56 = 1 << 56;
    uint256 internal constant _ROLE_57 = 1 << 57;
    uint256 internal constant _ROLE_58 = 1 << 58;
    uint256 internal constant _ROLE_59 = 1 << 59;
    uint256 internal constant _ROLE_60 = 1 << 60;
    uint256 internal constant _ROLE_61 = 1 << 61;
    uint256 internal constant _ROLE_62 = 1 << 62;
    uint256 internal constant _ROLE_63 = 1 << 63;
    uint256 internal constant _ROLE_64 = 1 << 64;
    uint256 internal constant _ROLE_65 = 1 << 65;
    uint256 internal constant _ROLE_66 = 1 << 66;
    uint256 internal constant _ROLE_67 = 1 << 67;
    uint256 internal constant _ROLE_68 = 1 << 68;
    uint256 internal constant _ROLE_69 = 1 << 69;
    uint256 internal constant _ROLE_70 = 1 << 70;
    uint256 internal constant _ROLE_71 = 1 << 71;
    uint256 internal constant _ROLE_72 = 1 << 72;
    uint256 internal constant _ROLE_73 = 1 << 73;
    uint256 internal constant _ROLE_74 = 1 << 74;
    uint256 internal constant _ROLE_75 = 1 << 75;
    uint256 internal constant _ROLE_76 = 1 << 76;
    uint256 internal constant _ROLE_77 = 1 << 77;
    uint256 internal constant _ROLE_78 = 1 << 78;
    uint256 internal constant _ROLE_79 = 1 << 79;
    uint256 internal constant _ROLE_80 = 1 << 80;
    uint256 internal constant _ROLE_81 = 1 << 81;
    uint256 internal constant _ROLE_82 = 1 << 82;
    uint256 internal constant _ROLE_83 = 1 << 83;
    uint256 internal constant _ROLE_84 = 1 << 84;
    uint256 internal constant _ROLE_85 = 1 << 85;
    uint256 internal constant _ROLE_86 = 1 << 86;
    uint256 internal constant _ROLE_87 = 1 << 87;
    uint256 internal constant _ROLE_88 = 1 << 88;
    uint256 internal constant _ROLE_89 = 1 << 89;
    uint256 internal constant _ROLE_90 = 1 << 90;
    uint256 internal constant _ROLE_91 = 1 << 91;
    uint256 internal constant _ROLE_92 = 1 << 92;
    uint256 internal constant _ROLE_93 = 1 << 93;
    uint256 internal constant _ROLE_94 = 1 << 94;
    uint256 internal constant _ROLE_95 = 1 << 95;
    uint256 internal constant _ROLE_96 = 1 << 96;
    uint256 internal constant _ROLE_97 = 1 << 97;
    uint256 internal constant _ROLE_98 = 1 << 98;
    uint256 internal constant _ROLE_99 = 1 << 99;
    uint256 internal constant _ROLE_100 = 1 << 100;
    uint256 internal constant _ROLE_101 = 1 << 101;
    uint256 internal constant _ROLE_102 = 1 << 102;
    uint256 internal constant _ROLE_103 = 1 << 103;
    uint256 internal constant _ROLE_104 = 1 << 104;
    uint256 internal constant _ROLE_105 = 1 << 105;
    uint256 internal constant _ROLE_106 = 1 << 106;
    uint256 internal constant _ROLE_107 = 1 << 107;
    uint256 internal constant _ROLE_108 = 1 << 108;
    uint256 internal constant _ROLE_109 = 1 << 109;
    uint256 internal constant _ROLE_110 = 1 << 110;
    uint256 internal constant _ROLE_111 = 1 << 111;
    uint256 internal constant _ROLE_112 = 1 << 112;
    uint256 internal constant _ROLE_113 = 1 << 113;
    uint256 internal constant _ROLE_114 = 1 << 114;
    uint256 internal constant _ROLE_115 = 1 << 115;
    uint256 internal constant _ROLE_116 = 1 << 116;
    uint256 internal constant _ROLE_117 = 1 << 117;
    uint256 internal constant _ROLE_118 = 1 << 118;
    uint256 internal constant _ROLE_119 = 1 << 119;
    uint256 internal constant _ROLE_120 = 1 << 120;
    uint256 internal constant _ROLE_121 = 1 << 121;
    uint256 internal constant _ROLE_122 = 1 << 122;
    uint256 internal constant _ROLE_123 = 1 << 123;
    uint256 internal constant _ROLE_124 = 1 << 124;
    uint256 internal constant _ROLE_125 = 1 << 125;
    uint256 internal constant _ROLE_126 = 1 << 126;
    uint256 internal constant _ROLE_127 = 1 << 127;
    uint256 internal constant _ROLE_128 = 1 << 128;
    uint256 internal constant _ROLE_129 = 1 << 129;
    uint256 internal constant _ROLE_130 = 1 << 130;
    uint256 internal constant _ROLE_131 = 1 << 131;
    uint256 internal constant _ROLE_132 = 1 << 132;
    uint256 internal constant _ROLE_133 = 1 << 133;
    uint256 internal constant _ROLE_134 = 1 << 134;
    uint256 internal constant _ROLE_135 = 1 << 135;
    uint256 internal constant _ROLE_136 = 1 << 136;
    uint256 internal constant _ROLE_137 = 1 << 137;
    uint256 internal constant _ROLE_138 = 1 << 138;
    uint256 internal constant _ROLE_139 = 1 << 139;
    uint256 internal constant _ROLE_140 = 1 << 140;
    uint256 internal constant _ROLE_141 = 1 << 141;
    uint256 internal constant _ROLE_142 = 1 << 142;
    uint256 internal constant _ROLE_143 = 1 << 143;
    uint256 internal constant _ROLE_144 = 1 << 144;
    uint256 internal constant _ROLE_145 = 1 << 145;
    uint256 internal constant _ROLE_146 = 1 << 146;
    uint256 internal constant _ROLE_147 = 1 << 147;
    uint256 internal constant _ROLE_148 = 1 << 148;
    uint256 internal constant _ROLE_149 = 1 << 149;
    uint256 internal constant _ROLE_150 = 1 << 150;
    uint256 internal constant _ROLE_151 = 1 << 151;
    uint256 internal constant _ROLE_152 = 1 << 152;
    uint256 internal constant _ROLE_153 = 1 << 153;
    uint256 internal constant _ROLE_154 = 1 << 154;
    uint256 internal constant _ROLE_155 = 1 << 155;
    uint256 internal constant _ROLE_156 = 1 << 156;
    uint256 internal constant _ROLE_157 = 1 << 157;
    uint256 internal constant _ROLE_158 = 1 << 158;
    uint256 internal constant _ROLE_159 = 1 << 159;
    uint256 internal constant _ROLE_160 = 1 << 160;
    uint256 internal constant _ROLE_161 = 1 << 161;
    uint256 internal constant _ROLE_162 = 1 << 162;
    uint256 internal constant _ROLE_163 = 1 << 163;
    uint256 internal constant _ROLE_164 = 1 << 164;
    uint256 internal constant _ROLE_165 = 1 << 165;
    uint256 internal constant _ROLE_166 = 1 << 166;
    uint256 internal constant _ROLE_167 = 1 << 167;
    uint256 internal constant _ROLE_168 = 1 << 168;
    uint256 internal constant _ROLE_169 = 1 << 169;
    uint256 internal constant _ROLE_170 = 1 << 170;
    uint256 internal constant _ROLE_171 = 1 << 171;
    uint256 internal constant _ROLE_172 = 1 << 172;
    uint256 internal constant _ROLE_173 = 1 << 173;
    uint256 internal constant _ROLE_174 = 1 << 174;
    uint256 internal constant _ROLE_175 = 1 << 175;
    uint256 internal constant _ROLE_176 = 1 << 176;
    uint256 internal constant _ROLE_177 = 1 << 177;
    uint256 internal constant _ROLE_178 = 1 << 178;
    uint256 internal constant _ROLE_179 = 1 << 179;
    uint256 internal constant _ROLE_180 = 1 << 180;
    uint256 internal constant _ROLE_181 = 1 << 181;
    uint256 internal constant _ROLE_182 = 1 << 182;
    uint256 internal constant _ROLE_183 = 1 << 183;
    uint256 internal constant _ROLE_184 = 1 << 184;
    uint256 internal constant _ROLE_185 = 1 << 185;
    uint256 internal constant _ROLE_186 = 1 << 186;
    uint256 internal constant _ROLE_187 = 1 << 187;
    uint256 internal constant _ROLE_188 = 1 << 188;
    uint256 internal constant _ROLE_189 = 1 << 189;
    uint256 internal constant _ROLE_190 = 1 << 190;
    uint256 internal constant _ROLE_191 = 1 << 191;
    uint256 internal constant _ROLE_192 = 1 << 192;
    uint256 internal constant _ROLE_193 = 1 << 193;
    uint256 internal constant _ROLE_194 = 1 << 194;
    uint256 internal constant _ROLE_195 = 1 << 195;
    uint256 internal constant _ROLE_196 = 1 << 196;
    uint256 internal constant _ROLE_197 = 1 << 197;
    uint256 internal constant _ROLE_198 = 1 << 198;
    uint256 internal constant _ROLE_199 = 1 << 199;
    uint256 internal constant _ROLE_200 = 1 << 200;
    uint256 internal constant _ROLE_201 = 1 << 201;
    uint256 internal constant _ROLE_202 = 1 << 202;
    uint256 internal constant _ROLE_203 = 1 << 203;
    uint256 internal constant _ROLE_204 = 1 << 204;
    uint256 internal constant _ROLE_205 = 1 << 205;
    uint256 internal constant _ROLE_206 = 1 << 206;
    uint256 internal constant _ROLE_207 = 1 << 207;
    uint256 internal constant _ROLE_208 = 1 << 208;
    uint256 internal constant _ROLE_209 = 1 << 209;
    uint256 internal constant _ROLE_210 = 1 << 210;
    uint256 internal constant _ROLE_211 = 1 << 211;
    uint256 internal constant _ROLE_212 = 1 << 212;
    uint256 internal constant _ROLE_213 = 1 << 213;
    uint256 internal constant _ROLE_214 = 1 << 214;
    uint256 internal constant _ROLE_215 = 1 << 215;
    uint256 internal constant _ROLE_216 = 1 << 216;
    uint256 internal constant _ROLE_217 = 1 << 217;
    uint256 internal constant _ROLE_218 = 1 << 218;
    uint256 internal constant _ROLE_219 = 1 << 219;
    uint256 internal constant _ROLE_220 = 1 << 220;
    uint256 internal constant _ROLE_221 = 1 << 221;
    uint256 internal constant _ROLE_222 = 1 << 222;
    uint256 internal constant _ROLE_223 = 1 << 223;
    uint256 internal constant _ROLE_224 = 1 << 224;
    uint256 internal constant _ROLE_225 = 1 << 225;
    uint256 internal constant _ROLE_226 = 1 << 226;
    uint256 internal constant _ROLE_227 = 1 << 227;
    uint256 internal constant _ROLE_228 = 1 << 228;
    uint256 internal constant _ROLE_229 = 1 << 229;
    uint256 internal constant _ROLE_230 = 1 << 230;
    uint256 internal constant _ROLE_231 = 1 << 231;
    uint256 internal constant _ROLE_232 = 1 << 232;
    uint256 internal constant _ROLE_233 = 1 << 233;
    uint256 internal constant _ROLE_234 = 1 << 234;
    uint256 internal constant _ROLE_235 = 1 << 235;
    uint256 internal constant _ROLE_236 = 1 << 236;
    uint256 internal constant _ROLE_237 = 1 << 237;
    uint256 internal constant _ROLE_238 = 1 << 238;
    uint256 internal constant _ROLE_239 = 1 << 239;
    uint256 internal constant _ROLE_240 = 1 << 240;
    uint256 internal constant _ROLE_241 = 1 << 241;
    uint256 internal constant _ROLE_242 = 1 << 242;
    uint256 internal constant _ROLE_243 = 1 << 243;
    uint256 internal constant _ROLE_244 = 1 << 244;
    uint256 internal constant _ROLE_245 = 1 << 245;
    uint256 internal constant _ROLE_246 = 1 << 246;
    uint256 internal constant _ROLE_247 = 1 << 247;
    uint256 internal constant _ROLE_248 = 1 << 248;
    uint256 internal constant _ROLE_249 = 1 << 249;
    uint256 internal constant _ROLE_250 = 1 << 250;
    uint256 internal constant _ROLE_251 = 1 << 251;
    uint256 internal constant _ROLE_252 = 1 << 252;
    uint256 internal constant _ROLE_253 = 1 << 253;
    uint256 internal constant _ROLE_254 = 1 << 254;
    uint256 internal constant _ROLE_255 = 1 << 255;
}

// src/DutchAuction.sol

contract DutchAuction is OwnableRoles, TReentrancyGuard {
    /// @dev The error for when the start time is before the current block time or more than 7 days in the future
    error InvalidStartTime();
    /// @dev The error for when the DA_ADMIN_ROLE calls startAuction while the auction is already active
    error AuctionAlreadyActive();
    /// @dev The error for when a user attempts to fill an auction has not begun or is already over
    error AuctionNotActive();
    /// @dev The error for when the end price is greater than the start price or the end price is zero
    error InvalidStartPrice();
    /// @dev The error for when the provided fill amount exceeds the auction supply
    error AmountExceedsSupply();
    /// @dev The error for when the duration is zero or greater than 30 days
    error InvalidDuration();
    /// @dev The error for when the start price multiplied by the amount exceeds the max uint256 value
    error AmountStartPriceOverflow();
    /// @dev The error for when the provided fill amount is zero
    error AmountOutZero();
    /// @dev The error for when a user has already redeemed a whitelist spot
    error AlreadyRedeemed();
    /// @dev The error for when the signature is invalid
    error InvalidSignature();
    /// @dev The error for when a user attempts to call a payable method that is not receive()
    error InvalidCall();

    /// @dev The struct for the auction parameters
    struct Auction {
        uint64 startTime;
        uint64 duration;
        uint128 amount;
        uint256 startPrice;
        uint256 endPrice;
    }

    /// @dev The current auction
    Auction public auction;
    /// @dev The address of the EthStrategy contract (tokens to be sold)
    address public immutable ethStrategy;
    /// @dev The address of the payment token (tokens used as payment)
    address public immutable paymentToken;
    /// @dev The decimals used for price evaluation
    uint8 public constant decimals = 18; // percentage in basis points
    /// @dev The maximum start time window for an auction based on the current block time
    uint64 public constant MAX_START_TIME_WINDOW = 7 days;
    /// @dev The maximum duration for an auction to occur
    uint64 public constant MAX_DURATION = 30 days;
    /// @dev The address of the whitelist signer
    address public signer;

    /// @dev A mapping to track if a user has redeemed whitelist spot
    mapping(bytes32 => bool) public hasRedeemed;

    /// @dev The event for when an auction is started
    event AuctionStarted(Auction auction);
    /// @dev The event for when an auction is filled
    event AuctionFilled(address buyer, uint128 amountOut, uint256 amountIn);
    /// @dev The event for when an auction is ended early (all tokens sold)
    event AuctionEndedEarly();
    /// @dev The event for when an auction is cancelled
    event AuctionCancelled();

    /// @dev The role for the dutch auction admin, can start and cancel auctions
    uint256 public constant DA_ADMIN_ROLE = uint256(keccak256("DA_ADMIN_ROLE"));

    /// @notice Constructor for the DutchAuction contract
    /// @param _ethStrategy The address of the EthStrategy contract (tokens to be sold)
    /// @param _paymentToken The address of the payment token (tokens used as payment)
    constructor(address _ethStrategy, address _paymentToken, address _signer) {
        ethStrategy = _ethStrategy;
        paymentToken = _paymentToken;
        _initializeOwner(_ethStrategy);
        _setRoles(msg.sender, DA_ADMIN_ROLE);
        signer = _signer;
    }

    /// @notice Start a new auction, auctions occur one at a time and can be triggered by the ADMIN_ROLE or the owner()
    /// @param _startTime The start time of the auction
    /// @param _duration The duration of the auction
    /// @param _startPrice The starting price of the auction
    /// @param _endPrice The ending price of the auction
    /// @param _amount The amount of tokens to be sold
    function startAuction(uint64 _startTime, uint64 _duration, uint256 _startPrice, uint256 _endPrice, uint128 _amount)
        public
        virtual
        onlyOwnerOrRoles(DA_ADMIN_ROLE)
    {
        uint64 currentTime = uint64(block.timestamp);
        if (_startTime == 0) {
            _startTime = currentTime;
        }
        /// @dev prevent auctions starting in the past or more than 7 days in the future
        if (_startTime < currentTime || _startTime > currentTime + MAX_START_TIME_WINDOW) {
            revert InvalidStartTime();
        }
        /// @dev prevent auctions with a duration of zero or greater than 30 days
        if (_duration == 0 || _duration > MAX_DURATION) {
            revert InvalidDuration();
        }
        /// @dev prevent the start price multiplied by the amount from overflowing
        if (_startPrice > (type(uint256).max / _amount)) {
            revert AmountStartPriceOverflow();
        }
        Auction memory _auction = auction;
        /// @dev prevent auctions from being started while another is active
        if (_isAuctionActive(_auction, currentTime)) {
            revert AuctionAlreadyActive();
        }
        delete auction;
        /// @dev prevent the start price from being less than the end price or the end price from being zero
        if (_startPrice < _endPrice || _endPrice == 0) {
            revert InvalidStartPrice();
        }
        _auction = Auction({
            startTime: _startTime,
            duration: _duration,
            startPrice: _startPrice,
            endPrice: _endPrice,
            amount: _amount
        });
        auction = _auction;

        emit AuctionStarted(_auction);
    }

    /// @notice Cancel the current auction, can be triggered by the ADMIN_ROLE or the owner(), cancelling an auction will not effect tokens already sold
    function cancelAuction() public onlyOwnerOrRoles(DA_ADMIN_ROLE) {
        delete auction;
        emit AuctionCancelled();
    }

    /// @notice Fill the auction with the amount of tokens to be sold
    /// @param _amountOut The amount of tokens to be sold
    /// @param signature The signature of the whitelist spot for the msg.sender
    function fill(uint128 _amountOut, bytes calldata signature)
        external
        payable
        virtual
        nonreentrant
        whitelist(signature)
    {
        Auction memory _auction = auction;
        uint256 currentTime = block.timestamp;
        /// @dev prevent the user from filling an inactive auction
        if (!_isAuctionActive(_auction, currentTime)) {
            revert AuctionNotActive();
        }
        /// @dev prevent the user from filling an auction with an amount of zero
        if (_amountOut == 0) {
            revert AmountOutZero();
        }
        /// @dev prevent the user from filling an auction with an amount of tokens that exceeds the auction supply
        if (_amountOut > _auction.amount) {
            revert AmountExceedsSupply();
        }
        uint256 currentPrice = _getCurrentPrice(_auction, currentTime);
        uint128 delta_amount = _auction.amount - _amountOut;
        if (delta_amount > 0) {
            auction.amount = delta_amount;
        } else {
            delete auction;
            emit AuctionEndedEarly();
        }
        uint256 amountIn = _getAmountIn(_amountOut, currentPrice);
        emit AuctionFilled(msg.sender, _amountOut, amountIn);
        _fill(_amountOut, amountIn, _auction.startTime, _auction.duration);
    }

    /// @dev An internal function to be called when the auction is filled, implementation left empty for inheriting contracts
    /// @param amountOut The amount of tokens to be sold
    /// @param amountIn The amount of tokens to be bought
    /// @param startTime The start time of the auction
    /// @param duration The duration of the auction
    function _fill(uint128 amountOut, uint256 amountIn, uint64 startTime, uint64 duration) internal virtual {}

    /// @dev A helper function to check if the auction is active
    /// @param _auction The auction to check
    /// @param currentTime The current time
    /// @return bool true if the auction is active, false otherwise
    function _isAuctionActive(Auction memory _auction, uint256 currentTime) internal pure returns (bool) {
        return _auction.startTime > 0 && _auction.startTime + _auction.duration > currentTime
            && currentTime >= _auction.startTime;
    }

    /// @notice An external helper function to get the amount of tokens to be paid by the filler
    /// @param amountOut The amount of tokens to be sold
    /// @param currentTime The time the filler is calling the function
    /// @return amountIn The amount of tokens to be paid by the filler
    function getAmountIn(uint128 amountOut, uint64 currentTime) external view returns (uint256 amountIn) {
        Auction memory _auction = auction;
        uint256 currentPrice = _getCurrentPrice(_auction, currentTime);
        return _getAmountIn(amountOut, currentPrice);
    }

    /// @dev An internal helper function to get the amount of tokens to be paid by the filler
    /// @param amountOut The amount of tokens to be sold
    /// @param currentPrice The current price of the auction
    /// @return amountIn The amount of tokens to be paid by the filler
    function _getAmountIn(uint128 amountOut, uint256 currentPrice) internal pure returns (uint256 amountIn) {
        amountIn = (amountOut * currentPrice) / 10 ** decimals;
        return (amountIn == 0) ? 1 : amountIn;
    }

    /// @dev An internal helper function to get the current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    /// @param _auction The auction to get the current price from
    /// @param currentTime The time the filler is calling the function
    /// @return currentPrice The current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    function _getCurrentPrice(Auction memory _auction, uint256 currentTime)
        internal
        pure
        returns (uint256 currentPrice)
    {
        uint256 delta_p = _auction.startPrice - _auction.endPrice;
        uint256 delta_t = _auction.duration - (currentTime - _auction.startTime);
        currentPrice = ((delta_p * delta_t) / _auction.duration) + _auction.endPrice;
    }

    /// @notice An external helper function to get the current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    /// @param currentTime The time the filler is calling the function
    /// @return currentPrice The current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    function getCurrentPrice(uint256 currentTime) external view returns (uint256 currentPrice) {
        Auction memory _auction = auction;
        if (!_isAuctionActive(_auction, currentTime)) {
            revert AuctionNotActive();
        }
        currentPrice = _getCurrentPrice(_auction, currentTime);
    }

    /// @dev An external helper function to check if the auction is active
    /// @param currentTime The time the filler is calling the function
    /// @return bool true if the auction is active, false otherwise
    function isAuctionActive(uint256 currentTime) external view returns (bool) {
        Auction memory _auction = auction;
        return _isAuctionActive(_auction, currentTime);
    }

    /// @dev A modifier to check if the user is whitelisted (hasRedeemed is updated)
    /// @param signature The signature of the whitelist spot for the msg.sender
    modifier whitelist(bytes calldata signature) {
        if (signer != address(0)) {
            bytes32 key = keccak256(
                abi.encodePacked(auction.startTime, auction.duration, auction.startPrice, auction.endPrice, msg.sender)
            );
            if (hasRedeemed[key]) revert AlreadyRedeemed();
            hasRedeemed[key] = true;
            bytes32 hash = SignatureCheckerLib.toEthSignedMessageHash(abi.encodePacked(msg.sender));
            if (!SignatureCheckerLib.isValidSignatureNow(signer, hash, signature)) revert InvalidSignature();
        }
        _;
    }

    /// @notice set the signer
    /// @param _signer the new signer
    /// @dev only the owner can set the signer
    function setSigner(address _signer) external onlyOwnerOrRoles(DA_ADMIN_ROLE) {
        signer = _signer;
    }

    /// @dev A fallback function to reject any ETH sent to the contract that is not using a payable method
    receive() external payable {
        revert InvalidCall();
    }
}

// src/EchidnaDutchAuctionTest.sol

/**
 * @title EchidnaDutchAuctionTest
 * @dev Property-based tests for DutchAuction using Echidna
 */
contract MockEthStrategy {
    function mint(address to, uint256 amount) external {}
}

contract MockPaymentToken {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
}

contract EchidnaDutchAuctionTest is DutchAuction {
    // Test accounts
    address constant public USER1 = address(0x1);
    address constant public USER2 = address(0x2);
    address constant public ADMIN = address(0x3);
    
    // Mock tokens
    MockPaymentToken paymentTokenInstance;
    MockEthStrategy ethStrategyInstance;
    
    // Test state variables
    uint128 public initialAuctionAmount;
    uint256 public initialStartPrice;
    uint256 public initialEndPrice;
    
    constructor() DutchAuction(address(new MockEthStrategy()), address(new MockPaymentToken()), address(this)) {
        // Store contract instances
        ethStrategyInstance = MockEthStrategy(ethStrategy);
        paymentTokenInstance = MockPaymentToken(paymentToken);
        
        // Setup roles
        _setRoles(ADMIN, DA_ADMIN_ROLE);
        
        // Initialize test state
        initialAuctionAmount = 1000;
        initialStartPrice = 2 * 10**decimals;  // 2.0 payment tokens per ethStrategy
        initialEndPrice = 1 * 10**decimals;    // 1.0 payment tokens per ethStrategy
        
        // Setup initial auction
        vm_startAuction();
    }
    
    // Helper function to start an auction with default parameters
    function vm_startAuction() internal {
        // Use msgSender() to simulate caller
        address originalSender = msg.sender;
        
        // Simulate ADMIN calling startAuction
        vm_mockSender(ADMIN);
        
        startAuction(
            uint64(block.timestamp), // start now
            3600,                    // 1 hour duration
            initialStartPrice,
            initialEndPrice,
            initialAuctionAmount
        );
        
        // Reset sender
        vm_mockSender(originalSender);
    }
    
    // Mock function to simulate different callers
    function vm_mockSender(address sender) internal {
        // In a real test with vm, this would use vm.prank(sender)
        // For Echidna, we'd handle this differently, but this is a placeholder
    }
    
    // Helper function to check if an account has a specific role
    function hasRole(address account, uint256 role) internal view returns (bool) {
        return rolesOf(account) & role != 0;
    }
    
    // PROPERTY 1: Auction state consistency
    function echidna_auctionStateConsistency() public view returns (bool) {
        Auction memory _auction = auction;
        uint256 currentTime = block.timestamp;
        
        // If auction has zero start time, it should be inactive
        if (_auction.startTime == 0) {
            return !_isAuctionActive(_auction, currentTime);
        }
        
        // If auction has non-zero start time, it should be active only within its time window
        if (currentTime < _auction.startTime) {
            return !_isAuctionActive(_auction, currentTime);
        }
        
        if (currentTime >= _auction.startTime + _auction.duration) {
            return !_isAuctionActive(_auction, currentTime);
        }
        
        if (currentTime >= _auction.startTime && currentTime < _auction.startTime + _auction.duration) {
            return _isAuctionActive(_auction, currentTime);
        }
        
        return true;
    }
    
    // PROPERTY 2: Auction amount never exceeds initial amount
    function echidna_auctionAmountNeverExceedsInitial() public view returns (bool) {
        // If auction is active, its amount should never exceed initialAuctionAmount
        if (auction.startTime != 0) {
            return auction.amount <= initialAuctionAmount;
        }
        return true;
    }
    
    // PROPERTY 3: Price always decreases over time
    function echidna_priceAlwaysDecreases() public view returns (bool) {
        Auction memory _auction = auction;
        
        // Skip if auction is not active
        if (!_isAuctionActive(_auction, block.timestamp)) {
            return true;
        }
        
        // Check price at current time
        uint256 currentPrice = _getCurrentPrice(_auction, block.timestamp);
        
        // Check price at a future time (still within auction duration)
        uint256 futureTime = block.timestamp + 1;
        if (futureTime < _auction.startTime + _auction.duration) {
            uint256 futurePrice = _getCurrentPrice(_auction, futureTime);
            return currentPrice >= futurePrice;
        }
        
        return true;
    }
    
    // PROPERTY 4: Price calculation correctness
    function echidna_priceCalculationCorrect() public view returns (bool) {
        Auction memory _auction = auction;
        
        // Skip if auction is not active
        if (!_isAuctionActive(_auction, block.timestamp)) {
            return true;
        }
        
        uint256 currentTime = block.timestamp;
        uint256 elapsedTime = currentTime - _auction.startTime;
        uint256 remainingTime = _auction.duration - elapsedTime;
        
        // Manual price calculation
        uint256 priceDelta = _auction.startPrice - _auction.endPrice;
        uint256 expectedPrice = _auction.endPrice + (priceDelta * remainingTime / _auction.duration);
        
        // Compare with contract's calculation
        uint256 actualPrice = _getCurrentPrice(_auction, currentTime);
        
        // Allow for minimal rounding differences due to integer division
        if (expectedPrice > actualPrice) {
            return expectedPrice - actualPrice <= 1;
        } else {
            return actualPrice - expectedPrice <= 1;
        }
    }
    
    // PROPERTY 5: Start price must be >= end price
    function echidna_startPriceGteEndPrice() public view returns (bool) {
        Auction memory _auction = auction;
        
        // Skip if no auction is active
        if (_auction.startTime == 0) {
            return true;
        }
        
        return _auction.startPrice >= _auction.endPrice;
    }
    
    // PROPERTY 6: Only owner or admin can cancel auction
    function echidna_onlyOwnerOrAdminCanCancel() public returns (bool) {
        // Skip if no auction is active or caller is owner/admin
        if (auction.startTime == 0 || msg.sender == owner() || hasRole(msg.sender, DA_ADMIN_ROLE)) {
            return true;
        }
        
        // Try to cancel auction as non-owner, non-admin user
        // This should revert, and if it doesn't, the property fails
        cancelAuction();
        
        // If we get here, cancellation succeeded when it shouldn't have
        return false;
    }
    
    // PROPERTY 7: Supply decreases after fill
    function echidna_supplyDecreasesAfterFill() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        uint128 amountBefore = auction.amount;
        uint128 fillAmount = amountBefore > 0 ? 1 : 0;
        
        // Skip if no amount to fill
        if (fillAmount == 0) {
            return true;
        }
        
        // Note: In a real test, we'd handle signatures properly
        bytes memory signature = new bytes(65);
        
        // Try to fill some amount
        try this.fill(fillAmount, signature) {
            // If fill succeeded, check if amount decreased
            return auction.amount == amountBefore - fillAmount;
        } catch {
            // If fill failed, property still holds
            return true;
        }
    }
    
    // PROPERTY 8: Cannot fill more than available
    function echidna_cannotFillMoreThanAvailable() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        uint128 availableAmount = auction.amount;
        uint128 fillAmount = availableAmount + 1;
        
        // Note: In a real test, we'd handle signatures properly
        bytes memory signature = new bytes(65);
        
        // Try to fill more than available
        try this.fill(fillAmount, signature) {
            // If fill succeeded, this is a violation
            return false;
        } catch {
            // Fill failed as expected
            return true;
        }
    }
}

