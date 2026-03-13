// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract MultiUserTest is Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    uint256 constant NUM_USERS = 10;
    uint256 constant DEPOSIT_AMOUNT = 10 ether;

    address[] users;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();

        // Create 10 users and mint them tokens
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            users.push(user);
            ERC20Mock(weth).mint(user, DEPOSIT_AMOUNT * 10);
            ERC20Mock(wbtc).mint(user, DEPOSIT_AMOUNT * 10);
        }
    }

    function testMultipleUsersDepositAndMint() public {
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];

            vm.startPrank(user);
            ERC20Mock(weth).approve(address(dsce), DEPOSIT_AMOUNT);
            dsce.depositCollateral(weth, DEPOSIT_AMOUNT);

            // Each user mints different amounts
            uint256 mintAmount = DEPOSIT_AMOUNT * (i + 1) * 100; // 1000, 2000, 3000... ether
            dsce.mintDsc(mintAmount);
            vm.stopPrank();

            // Verify
            assertGt(dsce.getDscMinted(user), 0);
            assertGt(dsce.getAccountCollateralValue(user), 0);
        }

        // Verify total supply matches
        uint256 totalSupply = dsc.totalSupply();
        assertGt(totalSupply, 0);
        console.log("Total supply with 10 users:", totalSupply);
    }

    function testMultipleUsersInteract() public {
        // First, all users deposit and mint
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];

            vm.startPrank(user);
            ERC20Mock(weth).approve(address(dsce), DEPOSIT_AMOUNT);
            dsce.depositCollateral(weth, DEPOSIT_AMOUNT);
            dsce.mintDsc(1000 ether); // Give each user 1000 DSC
            vm.stopPrank();
        }

        // Now they can transfer
        for (uint256 round = 0; round < 5; round++) {
            for (uint256 i = 0; i < NUM_USERS; i++) {
                uint256 j = (i + 1) % NUM_USERS;

                vm.startPrank(users[i]);
                require(dsc.transfer(users[j], 100 ether), "Transfer failed");
                vm.stopPrank();
            }
        }

        // All invariants should still hold
        uint256 totalCollateral = dsce.getAccountCollateralValue(users[0]) + dsce.getAccountCollateralValue(users[1]);
        assertGe(totalCollateral, dsc.totalSupply() / 2);
    }
}
