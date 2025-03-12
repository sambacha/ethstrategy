# Echidna Property-Based Tests for EthStrategy Contracts

This directory contains property-based fuzzing tests using Echidna for the EthStrategy contracts.

## Test Structure

The test suite consists of four main test contracts, each targeting a specific contract in the system:

1. `EchidnaDutchAuctionTest.sol` - Tests the base DutchAuction contract
2. `EchidnaAtmAuctionTest.sol` - Tests the AtmAuction contract
3. `EchidnaBondAuctionTest.sol` - Tests the BondAuction contract
4. `EchidnaDepositTest.sol` - Tests the Deposit contract

Each test file contains:
- Mock contracts for dependencies (EthStrategy, payment tokens)
- Helper functions to set up test state
- Property functions prefixed with `echidna_` that verify invariants
- Defensive code to ensure properties are only checked when applicable

## Properties Tested

### DutchAuction Properties

- `echidna_auctionStateConsistency` - Auction active status correctly reflects time conditions
- `echidna_auctionAmountNeverExceedsInitial` - Auction amount never exceeds initial amount
- `echidna_priceAlwaysDecreases` - Price always decreases over time during auction
- `echidna_priceCalculationCorrect` - Price calculation follows the expected formula
- `echidna_startPriceGteEndPrice` - Start price is always >= end price
- `echidna_onlyOwnerOrAdminCanCancel` - Only owner or admin can cancel auction
- `echidna_supplyDecreasesAfterFill` - Auction supply decreases after fill
- `echidna_cannotFillMoreThanAvailable` - Cannot fill more than available amount

### AtmAuction Properties

- `echidna_paymentAmountCorrect` - Payment amount calculation is correct
- `echidna_totalMintedNeverExceedsInitial` - Total minted tokens never exceed initial auction amount
- `echidna_ethRefundWorks` - ETH refund works correctly (for ETH payment)
- `echidna_fillMintsCorrectAmount` - Fill mints the correct amount of tokens
- `echidna_cannotFillWithInsufficientEth` - Cannot fill with insufficient payment
- `echidna_ownerReceivesPaymentAfterFill` - Owner receives payment after fill

### BondAuction Properties

- `echidna_bondCreatedCorrectly` - Bond is created with correct parameters
- `echidna_cannotCreateMultipleBonds` - Cannot create multiple bonds for the same user
- `echidna_cannotRedeemBeforeWindow` - Cannot redeem before redemption window
- `echidna_cannotRedeemAfterWindow` - Cannot redeem after redemption window
- `echidna_cannotWithdrawBeforeWindow` - Cannot withdraw before redemption window
- `echidna_redemptionDeletesBond` - Successful redemption deletes bond
- `echidna_withdrawalDeletesBond` - Successful withdrawal deletes bond
- `echidna_withdrawalReturnsCorrectAmount` - Withdrawal returns the correct amount

### Deposit Properties

- `echidna_depositLimitEnforced` - Deposit limit is enforced
- `echidna_startPriceEqualsEndPrice` - Start price must equal end price for deposits
- `echidna_cannotInitiateGovernanceDuringAuction` - Cannot initiate governance during active auction
- `echidna_canInitiateGovernanceWhenNoAuction` - Can initiate governance when no auction is active
- `echidna_fillAmountCannotExceedMaxDeposit` - Fill amount cannot exceed MAX_DEPOSIT
- `echidna_fillAmountCanEqualMaxDeposit` - Fill amount can equal MAX_DEPOSIT

## Running the Tests

To run these tests with Echidna, you'll need to:

1. Install Echidna (https://github.com/crytic/echidna)
2. Run each test separately with the configuration file

```bash
# Run DutchAuction tests
echidna-test src/EchidnaDutchAuctionTest.sol --contract EchidnaDutchAuctionTest --config src/echidna_config.yaml

# Run AtmAuction tests
echidna-test src/EchidnaAtmAuctionTest.sol --contract EchidnaAtmAuctionTest --config src/echidna_config.yaml

# Run BondAuction tests
echidna-test src/EchidnaBondAuctionTest.sol --contract EchidnaBondAuctionTest --config src/echidna_config.yaml

# Run Deposit tests
echidna-test src/EchidnaDepositTest.sol --contract EchidnaDepositTest --config src/echidna_config.yaml
```

## Configuration

The `echidna_config.yaml` file contains settings for the Echidna fuzzer:

```yaml
# Basic configuration
testMode: property
testLimit: 50000
seqLen: 100
shrinkLimit: 5000

# Multi-contract testing setup
filterFunctions: ["echidna_"]
filterBlacklist: false

# Addresses to use during testing
deployer: "0x10000"
sender: ["0x10000", "0x20000", "0x30000", "0x40000", "0x50000"]
```

## Implementation Notes

1. These tests use mock versions of EthStrategy and payment tokens
2. Time-based tests rely on manipulating the contract state directly rather than using `vm.warp`
3. Many properties are skipped when the test state doesn't allow for meaningful testing
4. The tests simulate different callers through internal helper functions

## Limitations and Future Improvements

1. **Signature Verification**: The tests use mock signatures that wouldn't pass real verification. In production, proper signature generation would be needed.
2. **Time Manipulation**: Echidna has limited time manipulation. A real test suite might use Foundry's `vm.warp`.
3. **State Transitions**: Most tests check single state transitions. More complex sequence testing would be valuable.
4. **Coverage**: Add more edge cases and boundary tests.
