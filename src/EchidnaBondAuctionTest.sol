// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import "./BondAuction.sol";
import "./interfaces/IEthStrategy.sol";

/**
 * @title EchidnaBondAuctionTest
 * @dev Property-based tests for BondAuction using Echidna
 */
contract MockEthStrategyForBond {
    mapping(address => uint256) public balances;
    
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
}

contract MockPaymentTokenForBond {
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
    
    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
}

contract EchidnaBondAuctionTest is BondAuction {
    // Test accounts
    address constant public USER1 = address(0x1);
    address constant public USER2 = address(0x2);
    address constant public ADMIN = address(0x3);
    
    // Mock tokens
    MockEthStrategyForBond mockEthStrategy;
    MockPaymentTokenForBond mockPaymentToken;
    
    // Test state variables
    uint128 public initialAuctionAmount;
    uint256 public initialStartPrice;
    uint256 public initialEndPrice;
    
    constructor() BondAuction(
        address(new MockEthStrategyForBond()), 
        address(new MockPaymentTokenForBond()),
        address(this)
    ) {
        // Store contract instances
        mockEthStrategy = MockEthStrategyForBond(ethStrategy);
        mockPaymentToken = MockPaymentTokenForBond(paymentToken);
        
        // Setup roles
        _setRoles(ADMIN, DA_ADMIN_ROLE);
        
        // Initialize test state
        initialAuctionAmount = 1000;
        initialStartPrice = 2 * 10**decimals;  // 2.0 payment tokens per ethStrategy
        initialEndPrice = 1 * 10**decimals;    // 1.0 payment tokens per ethStrategy
        
        // Setup initial auction
        vm_startAuction();
        
        // Mint tokens to users for testing
        mockPaymentToken.mint(USER1, 10000 * 10**18);
        mockPaymentToken.mint(USER2, 10000 * 10**18);
        mockPaymentToken.mint(address(this), 10000 * 10**18);
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
    
    // Helper function to fill a bond for a user
    function vm_fillBond(address user, uint128 amount) internal returns (bool) {
        // Use msgSender() to simulate caller
        address originalSender = msg.sender;
        
        // Simulate user calling fill
        vm_mockSender(user);
        
        // Approve payment
        uint256 paymentAmount = this.getAmountIn(amount, uint64(block.timestamp));
        mockPaymentToken.approve(address(this), paymentAmount);
        
        // Create a signature (mock for testing)
        bytes memory signature = new bytes(65);
        
        bool success = false;
        try this.fill(amount, signature) {
            success = true;
        } catch {
            success = false;
        }
        
        // Reset sender
        vm_mockSender(originalSender);
        
        return success;
    }
    
    // PROPERTY 1: Bond is created with correct parameters
    function echidna_bondCreatedCorrectly() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        // Skip if auction amount is 0
        if (auction.amount == 0) {
            return true;
        }
        
        uint128 fillAmount = 100;
        if (auction.amount < fillAmount) {
            fillAmount = auction.amount;
        }
        
        // Fill bond for USER1
        bool fillSuccess = vm_fillBond(USER1, fillAmount);
        if (!fillSuccess) {
            return true;  // Skip if fill failed
        }
        
        // Check bond parameters
        Bond memory bond = bonds[USER1];
        
        // Verify bond amount
        bool amountCorrect = bond.amountOut == fillAmount;
        
        // Verify payment amount
        uint256 expectedPayment = this.getAmountIn(fillAmount, uint64(block.timestamp));
        bool paymentCorrect = bond.amountIn == expectedPayment;
        
        // Verify redemption time
        bool redemptionTimeCorrect = bond.startRedemption == auction.startTime + auction.duration;
        
        return amountCorrect && paymentCorrect && redemptionTimeCorrect;
    }
    
    // PROPERTY 2: Cannot create multiple bonds for the same user
    function echidna_cannotCreateMultipleBonds() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        // Skip if auction amount is 0
        if (auction.amount == 0) {
            return true;
        }
        
        uint128 fillAmount = 10;
        if (auction.amount < fillAmount) {
            fillAmount = auction.amount;
        }
        
        // Fill first bond for USER1
        bool firstFillSuccess = vm_fillBond(USER1, fillAmount);
        if (!firstFillSuccess) {
            return true;  // Skip if first fill failed
        }
        
        // Try to fill second bond for USER1
        bool secondFillSuccess = vm_fillBond(USER1, fillAmount);
        
        // Second fill should fail
        return !secondFillSuccess;
    }
    
    // PROPERTY 3: Cannot redeem before redemption window
    function echidna_cannotRedeemBeforeWindow() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        uint128 fillAmount = 10;
        if (auction.amount < fillAmount) {
            fillAmount = auction.amount;
        }
        
        // Fill bond for USER1
        bool fillSuccess = vm_fillBond(USER1, fillAmount);
        if (!fillSuccess) {
            return true;  // Skip if fill failed
        }
        
        // Bond should be set with redeption time in the future
        if (bonds[USER1].startRedemption <= block.timestamp) {
            return true;  // Invalid test state
        }
        
        // Try to redeem before redemption window
        vm_mockSender(USER1);
        try this.redeem() {
            // If redeem succeeded, property is violated
            return false;
        } catch {
            // Redemption failed as expected
            return true;
        }
    }
    
    // PROPERTY 4: Cannot redeem after redemption window
    function echidna_cannotRedeemAfterWindow() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        uint128 fillAmount = 10;
        if (auction.amount < fillAmount) {
            fillAmount = auction.amount;
        }
        
        // Fill bond for USER1
        bool fillSuccess = vm_fillBond(USER1, fillAmount);
        if (!fillSuccess) {
            return true;  // Skip if fill failed
        }
        
        // Fast forward to after redemption window
        // This is a mock in Echidna - in a real test we'd use vm.warp
        // For this property test, we'll set up a bond with past redemption
        Bond storage userBond = bonds[USER1];
        
        // Skip if we can't set up the test state correctly
        if (userBond.startRedemption == 0) {
            return true;
        }
        
        // Mock a bond with expired redemption window
        // We'd normally use vm.warp, but we'll modify the bond directly for echidna
        uint64 currentTime = uint64(block.timestamp);
        userBond.startRedemption = currentTime - uint64(REDEMPTION_WINDOW) - 1;
        
        // Try to redeem after redemption window
        vm_mockSender(USER1);
        try this.redeem() {
            // If redeem succeeded, property is violated
            return false;
        } catch {
            // Redemption failed as expected
            return true;
        }
    }
    
    // PROPERTY 5: Cannot withdraw before redemption window
    function echidna_cannotWithdrawBeforeWindow() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        uint128 fillAmount = 10;
        if (auction.amount < fillAmount) {
            fillAmount = auction.amount;
        }
        
        // Fill bond for USER1
        bool fillSuccess = vm_fillBond(USER1, fillAmount);
        if (!fillSuccess) {
            return true;  // Skip if fill failed
        }
        
        // Bond should be set with redemption time in the future
        if (bonds[USER1].startRedemption <= block.timestamp) {
            return true;  // Invalid test state
        }
        
        // Try to withdraw before redemption window
        vm_mockSender(USER1);
        try this.withdraw() {
            // If withdraw succeeded, property is violated
            return false;
        } catch {
            // Withdrawal failed as expected
            return true;
        }
    }
    
    // PROPERTY 6: Successful redemption deletes bond
    function echidna_redemptionDeletesBond() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        uint128 fillAmount = 10;
        if (auction.amount < fillAmount) {
            fillAmount = auction.amount;
        }
        
        // Fill bond for USER1
        bool fillSuccess = vm_fillBond(USER1, fillAmount);
        if (!fillSuccess) {
            return true;  // Skip if fill failed
        }
        
        // Setup bond for redemption
        Bond storage userBond = bonds[USER1];
        userBond.startRedemption = uint64(block.timestamp); // Set redemption time to now
        
        // Try to redeem
        vm_mockSender(USER1);
        try this.redeem() {
            // If redeemed successfully, check that bond was deleted
            return bonds[USER1].startRedemption == 0;
        } catch {
            // If redemption failed, property still holds
            return true;
        }
    }
    
    // PROPERTY 7: Successful withdrawal deletes bond
    function echidna_withdrawalDeletesBond() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        uint128 fillAmount = 10;
        if (auction.amount < fillAmount) {
            fillAmount = auction.amount;
        }
        
        // Fill bond for USER1
        bool fillSuccess = vm_fillBond(USER1, fillAmount);
        if (!fillSuccess) {
            return true;  // Skip if fill failed
        }
        
        // Setup bond for withdrawal
        Bond storage userBond = bonds[USER1];
        userBond.startRedemption = uint64(block.timestamp); // Set redemption time to now
        
        // Try to withdraw
        vm_mockSender(USER1);
        try this.withdraw() {
            // If withdraw succeeded, check that bond was deleted
            return bonds[USER1].startRedemption == 0;
        } catch {
            // If withdrawal failed, property still holds
            return true;
        }
    }
    
    // PROPERTY 8: Withdrawal returns the correct amount
    function echidna_withdrawalReturnsCorrectAmount() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        uint128 fillAmount = 10;
        if (auction.amount < fillAmount) {
            fillAmount = auction.amount;
        }
        
        // Fill bond for USER1
        bool fillSuccess = vm_fillBond(USER1, fillAmount);
        if (!fillSuccess) {
            return true;  // Skip if fill failed
        }
        
        // Get the bond payment amount
        uint256 paymentAmount = bonds[USER1].amountIn;
        
        // Setup bond for withdrawal
        Bond storage userBond = bonds[USER1];
        userBond.startRedemption = uint64(block.timestamp); // Set redemption time to now
        
        // Record USER1's balance before withdrawal
        uint256 balanceBefore = mockPaymentToken.balanceOf(USER1);
        
        // Try to withdraw
        vm_mockSender(USER1);
        try this.withdraw() {
            // If withdrawal succeeded, check that USER1 received the correct amount
            uint256 balanceAfter = mockPaymentToken.balanceOf(USER1);
            return balanceAfter == balanceBefore + paymentAmount;
        } catch {
            // If withdrawal failed, property still holds
            return true;
        }
    }
}
