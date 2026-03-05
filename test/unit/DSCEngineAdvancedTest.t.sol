// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineAdvancedTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MINT_AMOUNT = 1000 ether;

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier mintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositColaterallAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }

    // ============ DepositCollateralAndMintDsc Tests ============
    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositColaterallAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        assertEq(totalDscMinted, 1000 ether);
        assertEq(collateralValueInUsd, AMOUNT_COLLATERAL * 2000); // 10 * 2000 = 20000
    }

    function testRevertsIfMintBreaksHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        // Try to mint too much DSC (more than 50% of collateral value)
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 666666666666666666));
        dsce.depositColaterallAndMintDsc(weth, AMOUNT_COLLATERAL, 15000 ether);
        vm.stopPrank();
    }

    // ============ BurnDsc Tests ============
    function testBurnDsc() public mintedDsc {
        uint256 initialDscMinted = dsce.getDscMinted(USER);

        vm.prank(USER);
        dsc.approve(address(dsce), 500 ether);

        vm.prank(USER);
        dsce.burnDsc(500 ether);

        uint256 finalDscMinted = dsce.getDscMinted(USER);
        assertEq(finalDscMinted, initialDscMinted - 500 ether);
    }

    function testRevertsIfBurnAmountZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
    }

    // ============ RedeemCollateral Tests ============
    function testRedeemCollateral() public depositedCollateral {
        uint256 initialCollateral = dsce.getCollateralBalanceOfUser(USER, weth);

        vm.prank(USER);
        dsce.redeemCollateral(weth, 5 ether);

        uint256 finalCollateral = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(finalCollateral, initialCollateral - 5 ether);
    }

    function testRevertsIfRedeemBreaksHealthFactor() public mintedDsc {
        vm.startPrank(USER);
        // Try to redeem all collateral - should break health factor
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.redeemCollateral(weth, 10 ether);
        vm.stopPrank();
    }

    // ============ RedeemCollateralForDsc Tests ============
    function testRedeemCollateralForDsc() public mintedDsc {
        uint256 initialCollateral = dsce.getCollateralBalanceOfUser(USER, weth);
        uint256 initialDscMinted = dsce.getDscMinted(USER);

        vm.startPrank(USER);
        dsc.approve(address(dsce), 500 ether);
        dsce.redeemCollateralForDsc(weth, 5 ether, 500 ether);
        vm.stopPrank();

        uint256 finalCollateral = dsce.getCollateralBalanceOfUser(USER, weth);
        uint256 finalDscMinted = dsce.getDscMinted(USER);

        assertEq(finalCollateral, initialCollateral - 5 ether);
        assertEq(finalDscMinted, initialDscMinted - 500 ether);
    }

    // ============ Liquidate Tests ============
    function testLiquidate() public {
        // Setup: User deposits collateral and mints DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositColaterallAndMintDsc(weth, AMOUNT_COLLATERAL, 8000 ether);
        vm.stopPrank();

        // Crash ETH price to make user undercollateralized
        vm.startPrank(ethUsdPriceFeed);
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8);
        vm.stopPrank();

        // Get user's remaining debt and liquidate ALL
        uint256 userDebt = dsce.getDscMinted(USER);

        // Liquidator steps in
        vm.startPrank(address(dsce));
        dsc.mint(LIQUIDATOR, userDebt);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsc.approve(address(dsce), userDebt);
        dsce.liquidate(weth, USER, userDebt);
        vm.stopPrank();

        // User should have 0 debt and positive collateral
        uint256 endingDebt = dsce.getDscMinted(USER);
        assertEq(endingDebt, 0, "User should have no debt after full liquidation");

        // Health factor should be extremely high (no debt)
        uint256 endingHealthFactor = dsce.getHealthFactor(USER);
        assertGe(endingHealthFactor, 1e18);
    }

    // ============ View Function Tests ============
    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collateralValue = dsce.getAccountCollateralValue(USER);
        assertEq(collateralValue, AMOUNT_COLLATERAL * 2000); // 10 * 2000 = 20000
    }

    function testGetDscMinted() public mintedDsc {
        uint256 dscMinted = dsce.getDscMinted(USER);
        assertEq(dscMinted, MINT_AMOUNT);
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 balance = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(balance, AMOUNT_COLLATERAL);
    }

    // ============ DecentralizedStableCoin Tests ============
    function testDscMintAndBurn() public {
        vm.prank(address(dsce));
        dsc.mint(USER, 1000 ether);
        assertEq(dsc.balanceOf(USER), 1000 ether);

        vm.prank(USER);
        dsc.approve(address(dsce), 1000 ether);

        vm.prank(address(dsce));
        dsc.burnFrom(USER, 500 ether);
        assertEq(dsc.balanceOf(USER), 500 ether);
    }

    function testRevertsIfNonOwnerMintsDsc() public {
        vm.prank(USER);
        vm.expectRevert();
        dsc.mint(USER, 1000 ether);
    }
}
