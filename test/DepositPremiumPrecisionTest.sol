// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {BaseTest} from "./utils/BaseTest.t.sol";
import {Deposit} from "../src/Deposit.sol";
import {IEthStrategy} from "../src/EthStrategy.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {console} from "forge-std/console.sol";

contract DepositPremiumPrecisionTest is BaseTest {
    Deposit deposit;
    Account signer;
    
    uint256 defaultConversionRate = 30_000;
    uint256 defaultDepositCap = 10_000e18;
    uint256 DENOMINATOR_BP = 100_00; // 100% in basis points
    
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
     * @notice Test precision issues with different premium values
     * @dev This test checks if the premium calculation maintains precision
     *      across different premium percentages
     */
    function testFuzz_PremiumPrecision(
        uint256 conversionPremium,
        uint256 depositAmount
    ) public {
        // Bound inputs to reasonable ranges
        // Premium is in basis points (0-10000, representing 0-100%)
        conversionPremium = bound(conversionPremium, 0, DENOMINATOR_BP - 1);
        
        // Test with deposit amounts from minimum to larger values
        depositAmount = bound(depositAmount, 1e18, 100e18);
        
        // Deploy contract with the fuzzed premium
        deposit = new Deposit(
            address(ethStrategy),
            signer.addr,
            defaultConversionRate,
            conversionPremium,
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
        
        // Calculate expected token amount with premium applied
        uint256 rawAmount = depositAmount * defaultConversionRate;
        uint256 expectedTokens = rawAmount * (DENOMINATOR_BP - conversionPremium) / DENOMINATOR_BP;
        
        // Check actual tokens received
        uint256 actualTokens = ethStrategy.balanceOf(alice);
        
        // Verify precision is maintained
        assertEq(
            actualTokens,
            expectedTokens,
            "Token amount with premium should exactly match expected calculation"
        );
        
        // Log results for analysis
        console.log("Conversion Premium (BP):", conversionPremium);
        console.log("Deposit Amount:", depositAmount);
        console.log("Raw Token Amount (before premium):", rawAmount);
        console.log("Expected Tokens (after premium):", expectedTokens);
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
     * @notice Test edge cases with premium values close to boundaries
     * @dev This test specifically targets scenarios where rounding errors might occur
     */
    function test_PremiumEdgeCases() public {
        uint256 depositAmount = 1e18;
        
        // Test case 1: Premium just below 100%
        uint256 highPremium = DENOMINATOR_BP - 1; // 99.99%
        
        // Deploy contract with high premium
        deposit = new Deposit(
            address(ethStrategy),
            signer.addr,
            defaultConversionRate,
            highPremium,
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
        
        // Calculate expected token amount with high premium
        uint256 rawAmount = depositAmount * defaultConversionRate;
        uint256 expectedTokens = rawAmount * (DENOMINATOR_BP - highPremium) / DENOMINATOR_BP;
        
        // With 99.99% premium, tokens should be almost zero but not quite
        assertEq(expectedTokens, rawAmount / DENOMINATOR_BP, "Expected tokens should be minimal with high premium");
        
        // Check actual tokens received
        uint256 actualTokens = ethStrategy.balanceOf(alice);
        
        // Verify precision is maintained even with extreme premium
        assertEq(
            actualTokens,
            expectedTokens,
            "Token amount should match expected calculation even with extreme premium"
        );
        
        console.log("High Premium Edge Case");
        console.log("Premium:", highPremium);
        console.log("Premium in percent:", highPremium / 100);
        console.log("Raw Token Amount:", rawAmount);
        console.log("Expected Tokens:", expectedTokens);
        console.log("Actual Tokens:", actualTokens);
        
        // Test case 2: Very small premium
        uint256 tinyPremium = 1; // 0.01%
        
        // Reset state for new test
        vm.startPrank(alice);
        vm.deal(alice, 0);
        vm.stopPrank();
        
        // Deploy contract with tiny premium
        deposit = new Deposit(
            address(ethStrategy),
            signer.addr,
            defaultConversionRate,
            tinyPremium,
            defaultDepositCap,
            uint64(block.timestamp)
        );
        
        // Grant minting role
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRole(ethStrategy.MINTER_ROLE(), address(deposit));
        vm.stopPrank();
        
        // Set up for deposit
        signature = getSignature(bob);
        vm.deal(bob, depositAmount);
        
        // Make the deposit
        vm.startPrank(bob);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();
        
        // Calculate expected token amount with tiny premium
        rawAmount = depositAmount * defaultConversionRate;
        expectedTokens = rawAmount * (DENOMINATOR_BP - tinyPremium) / DENOMINATOR_BP;
        
        // Check actual tokens received
        actualTokens = ethStrategy.balanceOf(bob);
        
        // Verify precision is maintained with tiny premium
        assertEq(
            actualTokens,
            expectedTokens,
            "Token amount should match expected calculation with tiny premium"
        );
        
        console.log("Tiny Premium Edge Case");
        console.log("Premium:", tinyPremium);
        console.log("Premium in percent:", tinyPremium / 100);
        console.log("Raw Token Amount:", rawAmount);
        console.log("Expected Tokens:", expectedTokens);
        console.log("Actual Tokens:", actualTokens);
        
        // Calculate the difference between no premium and tiny premium
        uint256 noPremiumTokens = rawAmount;
        uint256 premiumDifference = noPremiumTokens - expectedTokens;
        
        console.log("Premium Difference (tokens):", premiumDifference);
        console.log("Premium Difference (percentage):", premiumDifference * 100 / noPremiumTokens);
    }
    
    /**
     * @notice Test for potential rounding errors with odd deposit amounts
     * @dev This test checks if the premium calculation handles non-round numbers correctly
     */
    function testFuzz_RoundingErrors(
        uint256 conversionPremium,
        uint256 depositAmount
    ) public {
        // Bound inputs to reasonable ranges
        conversionPremium = bound(conversionPremium, 1, DENOMINATOR_BP - 1);
        
        // Use odd deposit amounts that might cause rounding
        depositAmount = bound(depositAmount, 1e18, 100e18);
        // Make it an odd number to increase chance of rounding issues
        if (depositAmount % 2 == 0) depositAmount += 1;
        
        // Deploy contract
        deposit = new Deposit(
            address(ethStrategy),
            signer.addr,
            defaultConversionRate,
            conversionPremium,
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
        
        // Calculate expected token amount with premium applied
        uint256 rawAmount = depositAmount * defaultConversionRate;
        uint256 expectedTokens = rawAmount * (DENOMINATOR_BP - conversionPremium) / DENOMINATOR_BP;
        
        // Check actual tokens received
        uint256 actualTokens = ethStrategy.balanceOf(alice);
        
        // Verify precision is maintained
        assertEq(
            actualTokens,
            expectedTokens,
            "Token amount should match expected calculation even with odd values"
        );
        
        // Calculate alternative order of operations (division first, then multiplication)
        // This would be the incorrect way to calculate but helps identify precision loss
        uint256 premiumFactor = (DENOMINATOR_BP - conversionPremium) / DENOMINATOR_BP;
        uint256 alternativeTokens = rawAmount * premiumFactor;
        
        // Log results for analysis
        console.log("Deposit Amount:", depositAmount);
        console.log("Premium (BP):", conversionPremium);
        console.log("Correct Calculation:", expectedTokens);
        console.log("Alternative Calculation (division first):", alternativeTokens);
        console.log("Actual Tokens:", actualTokens);
        
        // Check for difference between correct and alternative calculation
        if (expectedTokens != alternativeTokens) {
            int256 precisionDifference = int256(expectedTokens) - int256(alternativeTokens);
            console.log("Precision Difference:", precisionDifference);
            console.log("Precision Difference Percentage:", 
                        (precisionDifference * 100) / int256(expectedTokens));
        }
    }
}
