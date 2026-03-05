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
}
