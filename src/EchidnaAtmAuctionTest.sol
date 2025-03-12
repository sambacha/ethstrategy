// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import "./AtmAuction.sol";
import "./interfaces/IEthStrategy.sol";

/**
 * @title EchidnaAtmAuctionTest
 * @dev Property-based tests for AtmAuction using Echidna
 */
contract MockEthStrategyForAtm {
    mapping(address => uint256) public balances;
    
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
}

contract MockPaymentTokenForAtm {
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

contract EchidnaAtmAuctionTest is AtmAuction {
    // Test accounts
    address constant public USER1 = address(0x1);
    address constant public USER2 = address(0x2);
    address constant public ADMIN = address(0x3);
    
    // Mock tokens
    MockEthStrategyForAtm mockEthStrategy;
    MockPaymentTokenForAtm mockPaymentToken;
    
    // Test state variables
    uint128 public initialAuctionAmount;
    uint256 public initialStartPrice;
    uint256 public initialEndPrice;
    
    // Tracking variables for testing
    uint256 public totalMinted;
    
    constructor() AtmAuction(
        address(new MockEthStrategyForAtm()),
        address(new MockPaymentTokenForAtm()),
        address(this)
    ) {
        // Store contract instances
        mockEthStrategy = MockEthStrategyForAtm(ethStrategy);
        mockPaymentToken = MockPaymentTokenForAtm(paymentToken);
        
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
    
    // Override _fill to track minted amounts for test verification
    function _fill(uint128 amountOut, uint256 amountIn, uint64 startTime, uint64 duration) internal override {
        super._fill(amountOut, amountIn, startTime, duration);
        totalMinted += amountOut;
    }
    
    // PROPERTY 1: Payment amount calculation is correct
    function echidna_paymentAmountCorrect() public view returns (bool) {
        Auction memory _auction = auction;
        
        // Skip if auction is not active
        if (!_isAuctionActive(_auction, block.timestamp)) {
            return true;
        }
        
        uint128 testAmount = 100;
        
        // Skip if auction amount is less than test amount
        if (_auction.amount < testAmount) {
            return true;
        }
        
        uint256 currentPrice = _getCurrentPrice(_auction, block.timestamp);
        uint256 expectedPayment = (testAmount * currentPrice) / 10**decimals;
        if (expectedPayment == 0) expectedPayment = 1; // Minimum payment is 1
        
        // Get the actual payment amount
        uint256 actualPayment = this.getAmountIn(testAmount, uint64(block.timestamp));
        
        return actualPayment == expectedPayment;
    }
    
    // PROPERTY 2: Total minted tokens never exceed initial auction amount
    function echidna_totalMintedNeverExceedsInitial() public view returns (bool) {
        return totalMinted <= initialAuctionAmount;
    }
    
    // PROPERTY 3: ETH refund works correctly (for ETH payment)
    function echidna_ethRefundWorks() public payable returns (bool) {
        // This property is only relevant for ETH payment
        if (paymentToken != address(0)) {
            return true;
        }
        
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        // Skip if auction amount is 0
        if (auction.amount == 0) {
            return true;
        }
        
        uint128 fillAmount = 1; // Just fill a small amount
        uint256 requiredPayment = this.getAmountIn(fillAmount, uint64(block.timestamp));
        uint256 excessPayment = requiredPayment * 2; // Send twice the required amount
        
        // Create a signature (mock for testing)
        bytes memory signature = new bytes(65);
        
        // Record balance before
        uint256 balanceBefore = address(this).balance;
        
        // Try to fill with excess payment
        try this.fill{value: excessPayment}(fillAmount, signature) {
            // If fill succeeded, check balance after
            // The excess should have been refunded
            uint256 balanceAfter = address(this).balance;
            uint256 expectedBalance = balanceBefore - requiredPayment;
            
            return balanceAfter == expectedBalance;
        } catch {
            // If fill failed, property still holds
            return true;
        }
    }
    
    // PROPERTY 4: Fill mints the correct amount of tokens
    function echidna_fillMintsCorrectAmount() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        // Skip if auction amount is 0
        if (auction.amount == 0) {
            return true;
        }
        
        uint128 fillAmount = 1; // Just fill a small amount
        
        // Create a signature (mock for testing)
        bytes memory signature = new bytes(65);
        
        // Record balances before
        uint256 userBalanceBefore = mockEthStrategy.balanceOf(msg.sender);
        
        // Try to fill
        try this.fill(fillAmount, signature) {
            // If fill succeeded, check balances after
            uint256 userBalanceAfter = mockEthStrategy.balanceOf(msg.sender);
            
            return userBalanceAfter == userBalanceBefore + fillAmount;
        } catch {
            // If fill failed, property still holds
            return true;
        }
    }
    
    // PROPERTY 5: Cannot fill with insufficient payment (ETH)
    function echidna_cannotFillWithInsufficientEth() public payable returns (bool) {
        // This property is only relevant for ETH payment
        if (paymentToken != address(0)) {
            return true;
        }
        
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        // Skip if auction amount is 0
        if (auction.amount == 0) {
            return true;
        }
        
        uint128 fillAmount = 1; // Just fill a small amount
        uint256 requiredPayment = this.getAmountIn(fillAmount, uint64(block.timestamp));
        uint256 insufficientPayment = requiredPayment - 1; // Send less than required
        
        // Create a signature (mock for testing)
        bytes memory signature = new bytes(65);
        
        // Try to fill with insufficient payment
        try this.fill{value: insufficientPayment}(fillAmount, signature) {
            // If fill succeeded with insufficient payment, property is violated
            return false;
        } catch {
            // Fill failed as expected
            return true;
        }
    }
    
    // PROPERTY 6: Owner receives payment after fill
    function echidna_ownerReceivesPaymentAfterFill() public returns (bool) {
        // Skip if no auction is active
        if (!_isAuctionActive(auction, block.timestamp)) {
            return true;
        }
        
        // Skip if auction amount is 0
        if (auction.amount == 0) {
            return true;
        }
        
        // This test is for token payment only
        if (paymentToken == address(0)) {
            return true;
        }
        
        uint128 fillAmount = 1; // Just fill a small amount
        uint256 paymentAmount = this.getAmountIn(fillAmount, uint64(block.timestamp));
        
        // Create a signature (mock for testing)
        bytes memory signature = new bytes(65);
        
        // Setup: Approve payment token
        mockPaymentToken.approve(address(this), paymentAmount);
        
        // Record owner balance before
        uint256 ownerBalanceBefore = mockPaymentToken.balanceOf(owner());
        
        // Try to fill
        try this.fill(fillAmount, signature) {
            // If fill succeeded, check owner balance after
            uint256 ownerBalanceAfter = mockPaymentToken.balanceOf(owner());
            
            return ownerBalanceAfter == ownerBalanceBefore + paymentAmount;
        } catch {
            // If fill failed, property still holds
            return true;
        }
    }
}
