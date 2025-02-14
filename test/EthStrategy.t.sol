// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {BaseTest} from "./utils/BaseTest.t.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DutchAuction} from "../../src/DutchAuction.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {EthStrategy} from "../../src/EthStrategy.sol";
import {Ownable} from "solady/src/auth/OwnableRoles.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract EthStrategyGovernorTest is BaseTest {
    DutchAuction dutchAuction;

    uint64 defaultDuration = 1 days;
    uint128 defaultStartPrice = 10_000e6;
    uint128 defaultEndPrice = 3_000e6;
    uint128 defaultAmount = 100e18;

    function setUp() public virtual override {
        super.setUp();
        dutchAuction = new DutchAuction(address(ethStrategy), address(usdcToken));
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRole(ethStrategy.MINTER_ROLE(), address(dutchAuction));
        dutchAuction.grantRoles(admin1.addr, dutchAuction.ADMIN_ROLE());
        dutchAuction.grantRoles(admin2.addr, dutchAuction.ADMIN_ROLE());
        vm.stopPrank();
    }

    function test_proposal_success() public {
        vm.startPrank(address(dutchAuction));
        ethStrategy.mint(alice, defaultAmount);
        ethStrategy.mint(bob, defaultAmount);
        ethStrategy.mint(charlie, defaultAmount);
        vm.stopPrank();
        vm.prank(alice);
        ethStrategy.delegate(alice);
        vm.prank(bob);
        ethStrategy.delegate(bob);
        vm.prank(charlie);
        ethStrategy.delegate(charlie);

        address[] memory targets = new address[](1);
        targets[0] = address(dutchAuction);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            DutchAuction.startAuction.selector, 0, defaultDuration, defaultStartPrice, defaultEndPrice, defaultAmount
        );
        string memory description = "test";

        uint256 proposalId = ethStrategy.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        vm.startPrank(charlie);
        vm.expectEmit(address(ethStrategy));
        emit IGovernor.ProposalCreated(
            proposalId,
            charlie,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            block.timestamp + ethStrategy.votingDelay(),
            block.timestamp + ethStrategy.votingPeriod() + ethStrategy.votingDelay(),
            description
        );
        ethStrategy.propose(targets, values, calldatas, description);
        vm.stopPrank();
        assertEq(
            uint256(ethStrategy.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "proposal not pending"
        );
        assertEq(ethStrategy.proposalNeedsQueuing(proposalId), true, "proposal needs queuing");
        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), false, "alice has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), false, "bob has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), false, "charlie has not voted");

        vm.warp(block.timestamp + ethStrategy.votingDelay() + 1);

        vm.prank(alice);
        ethStrategy.castVote(proposalId, 1);
        vm.prank(bob);
        ethStrategy.castVote(proposalId, 0);
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, 1);

        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), true, "alice has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), true, "bob has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), true, "charlie has voted");
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Active), "proposal not active");
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + 1);
        assertEq(
            uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded), "proposal not succeeded"
        );

        ethStrategy.queue(targets, values, calldatas, keccak256(bytes(description)));
        vm.warp(block.timestamp + ethStrategy.getMinDelay());
        DutchAuction.Auction memory auction = DutchAuction.Auction({
            startTime: uint64(block.timestamp),
            duration: defaultDuration,
            startPrice: defaultStartPrice,
            endPrice: defaultEndPrice,
            amount: defaultAmount
        });
        bytes32 descriptionHash = keccak256(bytes(description));
        bytes32 salt = bytes20(address(ethStrategy)) ^ descriptionHash;
        bytes32 id = ethStrategy.hashOperationBatch(targets, values, calldatas, 0, salt);
        vm.expectEmit();
        emit DutchAuction.AuctionStarted(auction);
        vm.expectEmit();
        emit TimelockController.CallExecuted(id, 0, targets[0], values[0], calldatas[0]);
        vm.expectEmit();
        emit IGovernor.ProposalExecuted(proposalId);
        ethStrategy.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_proposal_didNotReachQuorum() public {
        vm.startPrank(address(dutchAuction));
        ethStrategy.mint(alice, defaultAmount * 97);
        ethStrategy.mint(bob, defaultAmount * 3);
        vm.stopPrank();
        vm.prank(alice);
        ethStrategy.delegate(alice);
        vm.prank(bob);
        ethStrategy.delegate(bob);

        address[] memory targets = new address[](1);
        targets[0] = address(dutchAuction);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            DutchAuction.startAuction.selector, 0, defaultDuration, defaultStartPrice, defaultEndPrice, defaultAmount
        );
        string memory description = "test";

        uint256 proposalId = ethStrategy.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        vm.startPrank(charlie);
        vm.expectEmit(address(ethStrategy));
        emit IGovernor.ProposalCreated(
            proposalId,
            charlie,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            block.timestamp + ethStrategy.votingDelay(),
            block.timestamp + ethStrategy.votingPeriod() + ethStrategy.votingDelay(),
            description
        );
        ethStrategy.propose(targets, values, calldatas, description);
        vm.stopPrank();
        assertEq(
            uint256(ethStrategy.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "proposal not pending"
        );
        assertEq(ethStrategy.proposalNeedsQueuing(proposalId), true, "proposal needs queuing");
        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), false, "alice has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), false, "bob has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), false, "charlie has not voted");

        vm.warp(block.timestamp + ethStrategy.votingDelay() + 1);

        vm.prank(bob);
        ethStrategy.castVote(proposalId, 1);

        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), false, "alice has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), true, "bob has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), false, "charlie has voted");
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Active), "proposal not active");
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + 1);
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Defeated), "proposal not defeated");

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorUnexpectedProposalState.selector, proposalId, 3, 48));
        ethStrategy.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_proposal_defeated() public {
        vm.startPrank(address(dutchAuction));
        ethStrategy.mint(alice, defaultAmount * 97);
        ethStrategy.mint(bob, defaultAmount * 3);
        vm.stopPrank();
        vm.prank(alice);
        ethStrategy.delegate(alice);
        vm.prank(bob);
        ethStrategy.delegate(bob);

        address[] memory targets = new address[](1);
        targets[0] = address(dutchAuction);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            DutchAuction.startAuction.selector, 0, defaultDuration, defaultStartPrice, defaultEndPrice, defaultAmount
        );
        string memory description = "test";

        uint256 proposalId = ethStrategy.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        vm.startPrank(charlie);
        vm.expectEmit(address(ethStrategy));
        emit IGovernor.ProposalCreated(
            proposalId,
            charlie,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            block.timestamp + ethStrategy.votingDelay(),
            block.timestamp + ethStrategy.votingPeriod() + ethStrategy.votingDelay(),
            description
        );
        ethStrategy.propose(targets, values, calldatas, description);
        vm.stopPrank();
        assertEq(
            uint256(ethStrategy.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "proposal not pending"
        );
        assertEq(ethStrategy.proposalNeedsQueuing(proposalId), true, "proposal needs queuing");
        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), false, "alice has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), false, "bob has not voted");

        vm.warp(block.timestamp + ethStrategy.votingDelay() + 1);

        vm.prank(alice);
        ethStrategy.castVote(proposalId, 0);

        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), true, "alice has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), false, "bob has voted");
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Active), "proposal not active");
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + 1);
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Defeated), "proposal not defeated");

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorUnexpectedProposalState.selector, proposalId, 3, 48));
        ethStrategy.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    // function test_constructor_success() public {
    //     ethStrategy = new EthStrategy(address(governor));
    //     assertEq(ethStrategy.owner(), address(governor), "governor not assigned correctly");
    // }

    function test_mint_success() public {
        vm.startPrank(address(ethStrategy));
        ethStrategy.mint(address(alice), 100e18);
        assertEq(ethStrategy.balanceOf(address(alice)), 100e18, "balance not assigned correctly");
    }

    function test_mint_revert_unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), ethStrategy.MINTER_ROLE()
            )
        );
        ethStrategy.mint(address(alice), 100e18);
    }

    function test_mint_success_with_role() public {
        address admin = address(1);
        bytes32 role = ethStrategy.MINTER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRole(role, admin);
        vm.prank(admin);
        ethStrategy.mint(address(alice), 100e18);
        assertEq(ethStrategy.balanceOf(address(alice)), 100e18, "balance not assigned correctly");
    }

    function test_name_success() public {
        assertEq(ethStrategy.name(), "EthStrategy", "name not assigned correctly");
    }

    function test_symbol_success() public {
        assertEq(ethStrategy.symbol(), "ETHXR", "symbol not assigned correctly");
    }

    function test_setIsTransferPaused_success() public {
        vm.prank(address(ethStrategy));
        ethStrategy.setIsTransferPaused(true);
        assertEq(ethStrategy.isTransferPaused(), true, "isTransferPaused not assigned correctly");
    }

    function test_setIsTransferPaused_revert_unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), ethStrategy.PAUSER_ROLE()
            )
        );
        ethStrategy.setIsTransferPaused(true);
    }

    function test_transfer_revert_transferPaused() public {
        vm.prank(address(ethStrategy));
        ethStrategy.mint(address(alice), 1);
        vm.prank(address(alice));
        vm.expectRevert(EthStrategy.TransferPaused.selector);
        ethStrategy.transfer(bob, 1);
    }

    function test_transfer_success() public {
        vm.prank(address(ethStrategy));
        ethStrategy.mint(address(alice), 1);
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRole(ethStrategy.PAUSER_ROLE(), charlie);
        vm.stopPrank();
        vm.prank(charlie);
        ethStrategy.setIsTransferPaused(false);
        vm.prank(address(alice));
        vm.expectEmit();
        emit ERC20.Transfer(address(alice), address(bob), 1);
        ethStrategy.transfer(bob, 1);
    }
}
