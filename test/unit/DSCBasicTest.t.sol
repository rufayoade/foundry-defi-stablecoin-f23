// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DSCBasicTest is Test {
    DecentralizedStableCoin dsc;
    address owner = address(this);
    address user = makeAddr("user");

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    function testMint() public {
        dsc.mint(user, 1000 ether);
        assertEq(dsc.balanceOf(user), 1000 ether);
    }

    function testBurn() public {
        dsc.mint(user, 1000 ether);

        vm.prank(user);
        dsc.approve(address(this), 500 ether);

        dsc.burnFrom(user, 500 ether);
        assertEq(dsc.balanceOf(user), 500 ether);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(user);
        vm.expectRevert();
        dsc.mint(user, 1000 ether);
    }

    function testMintZeroReverts() public {
    vm.expectRevert();
    dsc.mint(address(this), 0);
    }

    function testBurnZeroReverts() public {
        vm.expectRevert();
        dsc.burn(0);
    }

    function testBurnFromZeroReverts() public {
        // First mint some tokens to user
        dsc.mint(user, 1000 ether);
        
        // User approves this contract
        vm.prank(user);
        dsc.approve(address(this), 1000 ether);
        
        // Now try to burn 0 from user - this should NOT revert in ERC20
        // ERC20 allows burning 0 tokens
        dsc.burnFrom(user, 0);

        // Verify balance unchanged
        assertEq(dsc.balanceOf(user), 1000 ether);
    }

   function testTransferFromWithoutAllowance() public {
        dsc.mint(user, 1000 ether);
        
        vm.prank(user);
        vm.expectRevert(); // Should revert due to insufficient allowance
        dsc.transferFrom(user, address(this), 100 ether);
    }
}
