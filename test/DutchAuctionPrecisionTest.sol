// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {BaseTest} from "./utils/BaseTest.t.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {IEthStrategy} from "../src/EthStrategy.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DutchAuctionPrecisionTest
 * @notice Tests for arithmetic precision issues in the DutchAuction contract
 */
contract DutchAuctionPrecisionTest is BaseTest {
    DutchAuction dutchAuction;
    
    // Test parameters
    uint64 defaultDuration = 1 days;
    uint128 defaultStartPrice = 10_000e6;
    uint128 defaultEndPrice = 3_000e6;
    uint128 defaultAmount = 100e18;
    
    function setUp() public override {
        super.setUp();
        
        // Deploy the DutchAuction contract
        dutchAuction = new DutchAuction(address(ethStrategy), address(usdcToken));
        
        // Grant minting role to the auction contract
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRole(ethStrategy.MINTER_ROLE(), address(dutchAuction));
        vm.stopPrank();
        
        // Grant admin role to test accounts
        vm.startPrank(address(ethStrategy));
        dutchAuction.grantRoles(admin1.addr, dutchAuction.ADMIN_ROLE());
        dutchAuction.grantRoles(admin2.addr, dutchAuction.ADMIN_ROLE());
        vm.stopPrank();
    }
    
    /**
     * @notice Test for precision loss in price calculation
     * @dev This test checks if the price calculation formula loses precision
     *      due to division before multiplication: ((delta_p * delta_t) / duration) + endPrice
     */
    function testFuzz_PriceCalculationPrecision(
        uint64 duration,
        uint128 startPrice,
        uint128 endPrice,
        uint64 elapsedTime
    ) public {
        // Bound inputs to reasonable ranges
        duration = uint64(bound(duration, 1 hours, 30 days));
        
        // Ensure startPrice > endPrice
        startPrice = uint128(bound(startPrice, 1000e6, 100_000e6));
        endPrice = uint128(bound(endPrice, 100e6, startPrice - 1));
        
        // Ensure elapsedTime < duration
        elapsedTime = uint64(bound(elapsedTime, 0, duration - 1));
        
        // Start a new auction
        uint64 startTime = uint64(block.timestamp);
        vm.prank(admin1.addr);
        dutchAuction.startAuction(startTime, duration, startPrice, endPrice, defaultAmount);
        
        // Move time forward
        vm.warp(startTime + elapsedTime);
        
        // Get the current price using the contract's method
        uint128 contractPrice = dutchAuction.getCurrentPrice(block.timestamp);
        
        // Calculate the price manually using a more precise approach
        uint128 delta_p = startPrice - endPrice;
        uint64 delta_t = duration - elapsedTime;
        
        // Calculate using different order of operations
        // Original: ((delta_p * delta_t) / duration) + endPrice
        uint128 originalCalculation = uint128(((uint256(delta_p) * delta_t) / duration) + endPrice);
        
        // Alternative: (delta_p * delta_t / duration) + endPrice
        // This is mathematically equivalent but might have different precision characteristics
        uint256 alternativeCalculation = (uint256(delta_p) * delta_t / duration) + endPrice;
        
        // More precise: endPrice + delta_p - (delta_p * elapsedTime / duration)
        uint256 preciseCalculation = uint256(endPrice) + delta_p - (uint256(delta_p) * elapsedTime / duration);
        
        // Verify the contract's price matches our manual calculation
        assertEq(contractPrice, originalCalculation, "Contract price should match manual calculation");
        
        // Log the results for analysis
        console.log("Start Price:", startPrice);
        console.log("End Price:", endPrice);
        console.log("Duration:", duration);
        console.log("Elapsed Time:", elapsedTime);
        console.log("Contract Price:", contractPrice);
        console.log("Original Calculation:", originalCalculation);
        console.log("Alternative Calculation:", alternativeCalculation);
        console.log("Precise Calculation:", preciseCalculation);
        
        // Check for precision differences
        if (originalCalculation != uint128(preciseCalculation)) {
            int256 precisionDiff = int256(uint256(originalCalculation)) - int256(preciseCalculation);
            console.log("Precision Difference:", precisionDiff);
            console.log("Precision Difference Percentage:", 
                        (precisionDiff * 10000) / int256(preciseCalculation));
            console.log("basis points");
        }
    }
    
    /**
     * @notice Test for edge cases in price calculation
     * @dev This test specifically targets scenarios where precision loss might be significant
     */
    function test_PriceCalculationEdgeCases() public {
        // Test case 1: Very short duration with large price difference
        uint64 shortDuration = 10 minutes;
        uint128 highStartPrice = 100_000e6;
        uint128 lowEndPrice = 1000e6;
        uint64 smallElapsedTime = 1 minutes;
        
        // Start a new auction
        uint64 startTime = uint64(block.timestamp);
        vm.prank(admin1.addr);
        dutchAuction.startAuction(startTime, shortDuration, highStartPrice, lowEndPrice, defaultAmount);
        
        // Move time forward
        vm.warp(startTime + smallElapsedTime);
        
        // Get the current price
        uint128 contractPrice = dutchAuction.getCurrentPrice(block.timestamp);
        
        // Calculate manually
        uint128 delta_p = highStartPrice - lowEndPrice;
        uint64 delta_t = shortDuration - smallElapsedTime;
        uint128 expectedPrice = uint128(((uint256(delta_p) * delta_t) / shortDuration) + lowEndPrice);
        
        // More precise calculation
        uint256 precisePrice = uint256(lowEndPrice) + delta_p - (uint256(delta_p) * smallElapsedTime / shortDuration);
        
        console.log("Short Duration Edge Case");
        console.log("Contract Price:", contractPrice);
        console.log("Expected Price:", expectedPrice);
        console.log("Precise Price:", precisePrice);
        console.log("Difference:", int256(uint256(expectedPrice)) - int256(precisePrice));
        
        // Test case 2: Very long duration with small price difference
        uint64 longDuration = 30 days;
        uint128 closeStartPrice = 10_000e6;
        uint128 closeEndPrice = 9_900e6;
        uint64 largeElapsedTime = 29 days;
        
        // Reset and start a new auction
        vm.warp(block.timestamp + 1);
        startTime = uint64(block.timestamp);
        vm.prank(admin1.addr);
        dutchAuction.startAuction(startTime, longDuration, closeStartPrice, closeEndPrice, defaultAmount);
        
        // Move time forward
        vm.warp(startTime + largeElapsedTime);
        
        // Get the current price
        contractPrice = dutchAuction.getCurrentPrice(block.timestamp);
        
        // Calculate manually
        delta_p = closeStartPrice - closeEndPrice;
        delta_t = longDuration - largeElapsedTime;
        expectedPrice = uint128(((uint256(delta_p) * delta_t) / longDuration) + closeEndPrice);
        
        // More precise calculation
        precisePrice = uint256(closeEndPrice) + delta_p - (uint256(delta_p) * largeElapsedTime / longDuration);
        
        console.log("Long Duration Edge Case");
        console.log("Contract Price:", contractPrice);
        console.log("Expected Price:", expectedPrice);
        console.log("Precise Price:", precisePrice);
        console.log("Difference:", int256(uint256(expectedPrice)) - int256(precisePrice));
    }
    
    /**
     * @notice Test for the minimum return value of 1 in _getAmountIn
     * @dev This test checks if the minimum return value of 1 in _getAmountIn
     *      can lead to users paying more than the calculated amount
     */
    function testFuzz_MinimumAmountInValue(
        uint128 amountOut,
        uint128 currentPrice
    ) public {
        // Bound inputs to reasonable ranges
        // Use very small values to trigger the minimum return value of 1
        amountOut = uint128(bound(amountOut, 1, 1e18));
        currentPrice = uint128(bound(currentPrice, 1, 1e6));
        
        // Calculate amountIn using the contract's method
        uint128 amountIn = dutchAuction.getAmountIn(amountOut, uint64(block.timestamp + 1));
        
        // Calculate amountIn manually
        uint8 decimals = dutchAuction.decimals();
        uint128 manualAmountIn = uint128((uint256(amountOut) * currentPrice) / 10**decimals);
        
        // If manualAmountIn is 0, it should be set to 1
        if (manualAmountIn == 0) {
            manualAmountIn = 1;
        }
        
        // Log the results
        console.log("Amount Out:", amountOut);
        console.log("Current Price:", currentPrice);
        console.log("Manual Amount In:", manualAmountIn);
        console.log("Contract Amount In:", amountIn);
        
        // Check if the minimum value of 1 is causing a significant overpayment
        if (manualAmountIn == 1 && uint256(amountOut) * currentPrice > 0) {
            uint256 actualPrice = uint256(10**decimals);
            uint256 calculatedPrice = uint256(currentPrice);
            uint256 priceDifference = actualPrice > calculatedPrice ? 
                                      actualPrice - calculatedPrice : 
                                      calculatedPrice - actualPrice;
            
            console.log("Minimum value of 1 is being used");
            console.log("Actual effective price:", actualPrice);
            console.log("Calculated price:", calculatedPrice);
            console.log("Price difference:", priceDifference);
            console.log("Overpayment percentage:", (priceDifference * 100) / calculatedPrice);
            console.log("%");
        }
    }
}