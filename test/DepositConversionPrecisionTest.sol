// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {BaseTest} from "./utils/BaseTest.t.sol";
import {Deposit} from "../src/Deposit.sol";
import {IEthStrategy} from "../src/EthStrategy.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {console} from "forge-std/console.sol";

contract DepositConversionPrecisionTest is BaseTest {
    Deposit deposit;
    Account signer;
    
    uint256 defaultDepositCap = 10_000e18;
    
    function setUp() public override {
        super.setUp();
        
        // Create a signer account for whitelist signatures
        signer = makeAccount("signer");
        vm.label(signer.addr, "signer");
    }
    
    function getSignature(address _to) public view returns (bytes memory) {
        bytes32 hash = SignatureCheckerLib.toEthSignedMessageHash(abi.encodePacked(_to));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, hash);
        return abi.encodePacked(r, s, v);
    }
    
    /**
     * @notice Test precision issues with different conversion rates
     * @dev This test checks if the token amount calculation maintains precision
     *      across different conversion rates and deposit amounts
     */
    function testFuzz_ConversionRatePrecision(
        uint256 conversionRate,
        uint256 depositAmount
    ) public {
        // Bound inputs to reasonable ranges
        // Use a wide range of conversion rates to test precision
        conversionRate = bound(conversionRate, 1, 1_000_000);
        
        // Test with deposit amounts from minimum to larger values
        depositAmount = bound(depositAmount, 1e18, 100e18);
        
        // Deploy contract with the fuzzed conversion rate
        deposit = new Deposit(
            address(ethStrategy),
            signer.addr,
            conversionRate,
            0, // No premium for this test
            defaultDepositCap,
            uint64(block.timestamp)
        );
        
        // Grant minting role
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRole(ethStrategy.MINTER_ROLE(), address(deposit));
        vm.stopPrank();
        
        // Set up for deposit
        bytes memory signature = getSignature(alice);
        vm.deal(alice, depositAmount);
        
        // Make the deposit
        vm.startPrank(alice);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();
        
        // Calculate expected token amount
        uint256 expectedTokens = depositAmount * conversionRate;
        
        // Check actual tokens received
        uint256 actualTokens = ethStrategy.balanceOf(alice);
        
        // Verify precision is maintained
        assertEq(
            actualTokens,
            expectedTokens,
            "Token amount should exactly match expected calculation"
        );
        
        // Log results for analysis
        console.log("Conversion Rate:", conversionRate);
        console.log("Deposit Amount:", depositAmount);
        console.log("Expected Tokens:", expectedTokens);
        console.log("Actual Tokens:", actualTokens);
        
        // Check for any unexpected precision loss
        if (actualTokens != expectedTokens) {
            int256 precisionLoss = int256(expectedTokens) - int256(actualTokens);
            console.log("Precision Loss:", precisionLoss);
            console.log("Precision Loss Percentage:", 
                        (precisionLoss * 100) / int256(expectedTokens));
        }
    }
    
    /**
     * @notice Test edge cases with very small deposits and large conversion rates
     * @dev This test specifically targets scenarios where precision loss might occur
     */
    function test_ConversionRateEdgeCases() public {
        // Test case 1: Minimum deposit with maximum conversion rate
        uint256 minDeposit = 1e18; // Minimum deposit
        uint256 maxConversionRate = type(uint128).max; // Very large conversion rate
        
        // Check if this would overflow
        vm.assume(minDeposit * maxConversionRate < type(uint256).max);
        
        // Deploy contract with extreme conversion rate
        deposit = new Deposit(
            address(ethStrategy),
            signer.addr,
            maxConversionRate,
            0, // No premium
            defaultDepositCap,
            uint64(block.timestamp)
        );
        
        // Grant minting role
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRole(ethStrategy.MINTER_ROLE(), address(deposit));
        vm.stopPrank();
        
        // Set up for deposit
        bytes memory signature = getSignature(alice);
        vm.deal(alice, minDeposit);
        
        // Make the deposit
        vm.startPrank(alice);
        deposit.deposit{value: minDeposit}(signature);
        vm.stopPrank();
        
        // Calculate expected token amount
        uint256 expectedTokens = minDeposit * maxConversionRate;
        
        // Check actual tokens received
        uint256 actualTokens = ethStrategy.balanceOf(alice);
        
        // Verify precision is maintained even in extreme case
        assertEq(
            actualTokens,
            expectedTokens,
            "Token amount should match expected calculation even with extreme values"
        );
        
        console.log("Minimum Deposit with Maximum Conversion Rate Test");
        console.log("Deposit:", minDeposit);
        console.log("Conversion Rate:", maxConversionRate);
        console.log("Expected Tokens:", expectedTokens);
        console.log("Actual Tokens:", actualTokens);
    }
}
