pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "./utils/BaseTest.t.sol";
import {EthStrategy} from "../../src/EthStrategy.sol";
import {Ownable} from "solady/src/auth/OwnableRoles.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

contract EthStrategyTest is BaseTest {
    function test_constructor_success() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        assertEq(ethStrategy.owner(), address(governor), "governor not assigned correctly");
    }

    function test_mint_success() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        vm.startPrank(address(governor));
        ethStrategy.mint(address(alice), 100e18);
        assertEq(ethStrategy.balanceOf(address(alice)), 100e18, "balance not assigned correctly");
    }

    function test_mint_revert_unauthorized() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        vm.expectRevert(Ownable.Unauthorized.selector);
        ethStrategy.mint(address(alice), 100e18);
    }

    function test_mint_success_with_role() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        address admin = address(1);
        uint8 role = ethStrategy.MINTER_ROLE();
        vm.prank(address(governor));
        ethStrategy.grantRoles(admin, role);
        vm.prank(admin);
        ethStrategy.mint(address(alice), 100e18);
        assertEq(ethStrategy.balanceOf(address(alice)), 100e18, "balance not assigned correctly");
    }

    function test_name_success() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        assertEq(ethStrategy.name(), "EthStrategy", "name not assigned correctly");
    }

    function test_symbol_success() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        assertEq(ethStrategy.symbol(), "ETHSR", "symbol not assigned correctly");
    }

    function test_setIsTransferPaused_success() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        vm.prank(address(governor));
        ethStrategy.setIsTransferPaused(true);
        assertEq(ethStrategy.isTransferPaused(), true, "isTransferPaused not assigned correctly");
    }

    function test_setIsTransferPaused_revert_unauthorized() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        vm.expectRevert(Ownable.Unauthorized.selector);
        ethStrategy.setIsTransferPaused(true);
    }

    function test_transfer_revert_transferPaused() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        vm.prank(address(governor));
        ethStrategy.mint(address(alice), 1);
        vm.prank(address(alice));
        vm.expectRevert(EthStrategy.TransferPaused.selector);
        ethStrategy.transfer(bob, 1);
    }

    function test_transfer_success() public {
        EthStrategy ethStrategy = new EthStrategy(address(governor));
        vm.prank(address(governor));
        ethStrategy.mint(address(alice), 1);
        vm.startPrank(address(governor));
        ethStrategy.grantRoles(charlie, ethStrategy.PAUSER_ROLE());
        vm.stopPrank();
        vm.prank(charlie);
        ethStrategy.setIsTransferPaused(false);
        vm.prank(address(alice));
        vm.expectEmit();
        emit ERC20.Transfer(address(alice), address(bob), 1);
        ethStrategy.transfer(bob, 1);
    }
}
