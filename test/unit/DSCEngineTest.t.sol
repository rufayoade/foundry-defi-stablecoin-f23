// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    uint256[] public collateralRatios;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(liquidator, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(liquidator, STARTING_ERC20_BALANCE);

        // Initialize arrays
        tokenAddresses = new address[](2);
        tokenAddresses[0] = weth;
        tokenAddresses[1] = wbtc;

        priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = ethUsdPriceFeed;
        priceFeedAddresses[1] = btcUsdPriceFeed;

        collateralRatios = new uint256[](2);
        collateralRatios[0] = 150;
        collateralRatios[1] = 170;
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        address[] memory badTokenAddresses = new address[](1);
        badTokenAddresses[0] = weth;

        address[] memory badPriceFeedAddresses = new address[](2);
        badPriceFeedAddresses[0] = ethUsdPriceFeed;
        badPriceFeedAddresses[1] = btcUsdPriceFeed;

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(badTokenAddresses, badPriceFeedAddresses, collateralRatios, address(dsc), address(this));
    }

    function testConstructorWithZeroTreasury() public {
        vm.expectRevert("Treasury cannot be zero address");
        new DSCEngine(tokenAddresses, priceFeedAddresses, collateralRatios, address(dsc), address(0));
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ///////////////////////////
    // depositCollateral Tests //
    ///////////////////////////

    function testRevertsCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositZeroReverts() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
    }

    function testDepositInvalidToken() public {
        address invalidToken = address(0x123);
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(invalidToken, 100 ether);
    }

    function testDepositWithUnapprovedTokenReverts() public {
        address fakeToken = makeAddr("fakeToken");
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(fakeToken, 100 ether);
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        uint256 deposited = dsce.getCollateralBalanceOfUser(user, weth);
        console.log("Deposited collateral:", deposited);

        uint256 collateralValue = dsce.getAccountCollateralValue(user);
        console.log("Collateral value:", collateralValue);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        console.log("totalDscMinted:", totalDscMinted);
        console.log("collateralValueInUsd:", collateralValueInUsd);

        uint256 expectedUsdValue = AMOUNT_COLLATERAL * 2000;
        console.log("expectedUsdValue:", expectedUsdValue);

        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, expectedUsdValue);
    }

    ///////////////////////////
    // redeemCollateral Tests //
    ///////////////////////////

    function testRedeemWithZeroAmountReverts() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }

    function testRedeemWithZeroHealthFactor() public depositedCollateral {
        vm.startPrank(user);
        dsce.mintDsc(10000 ether);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert();
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL * 8 / 10);
    }

    ///////////////////
    // mintDsc Tests //
    ///////////////////

    function testMintWithZeroAmountReverts() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
    }

    function testMintBreaksHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert();
        dsce.mintDsc(1000000 ether);
        vm.stopPrank();
    }

    ///////////////////
    // liquidate Tests //
    ///////////////////

    function testLiquidateWithZeroDebtReverts() public {
        vm.prank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, user, 0);
    }

    function testCannotLiquidateHealthyUser() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(1000 ether);
        vm.stopPrank();

        vm.prank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, user, 100 ether);
    }

    ///////////////////
    // Debug Helper  //
    ///////////////////

    function debugPriceFeed() public view {
        address[] memory tokens = dsce.getCollateralTokens();
        console.log("Number of collateral tokens:", tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log("Token", i, ":", tokens[i]);
            console.log("Price feed:", dsce.getCollateralTokenPriceFeed(tokens[i]));

            if (tokens[i] == weth) {
                console.log("Found WETH at index", i);
            }
        }
    }
}
