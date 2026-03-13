// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract LiquidationProfitTest is Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;

    address user = makeAddr("user");
    address liquidator = makeAddr("liquidator");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();

        // Give users tokens
        ERC20Mock(weth).mint(user, 20 ether);
        ERC20Mock(weth).mint(liquidator, 20 ether);
        vm.deal(liquidator, 1000 ether);
    }

    function testLiquidationProfit() public {
        // User deposits and mints
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        dsce.depositCollateral(weth, 10 ether);
        dsce.mintDsc(5000 ether);
        vm.stopPrank();

        // Crash price
        vm.startPrank(ethUsdPriceFeed);
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(100e8);
        vm.stopPrank();

        // Get collateral value after crash
        uint256 collateralValueUsd = dsce.getAccountCollateralValue(user);
        console.log("Collateral value after crash: $", collateralValueUsd / 1e18);

        // Calculate maximum safe liquidation (90% of collateral value)
        uint256 maxSafeLiquidation = 900 ether; // 900 DSC

        console.log("Max safe liquidation amount:", maxSafeLiquidation / 1e18, "DSC");

        // Give liquidator enough DSC
        vm.prank(address(dsce));
        dsc.mint(liquidator, maxSafeLiquidation);

        // Record liquidator's balances before
        // uint256 liquidatorDscBefore = dsc.balanceOf(liquidator); // Unused variables
        // uint256 liquidatorWethBefore = ERC20Mock(weth).balanceOf(liquidator); // Unused variables

        vm.startPrank(liquidator);
        dsc.approve(address(dsce), maxSafeLiquidation);

        // This should revert because health factor won't improve enough
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dsce.liquidate(weth, user, maxSafeLiquidation);
        vm.stopPrank();

        console.log("Protocol correctly prevents non-improving liquidations!");
    }
}
