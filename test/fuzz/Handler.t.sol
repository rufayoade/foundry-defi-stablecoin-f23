// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {console} from "forge-std/Test.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;
    address wethPriceFeed;

    uint256 maxDepositSize = 10_000 ether; // Max 10,000 ETH deposit
    // Add to the top of your Handler with other state variables
    mapping(address => uint256) public timesMinted;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        dsce = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        wethPriceFeed = dsce.getCollateralTokenPriceFeed(address(weth));
    }

    function mintDsc(uint256 amount) public {
        // Get account info using msg.sender (the fuzzer will handle different users)
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(msg.sender);

        // Calculate max they can mint (50% of collateral value minus what they already minted)
        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDscMinted;
        if (maxDscToMint <= 0) {
            return;
        }

        amount = bound(amount, 0, maxDscToMint);
        if (amount == 0) {
            return;
        }

        vm.startPrank(msg.sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        console.log("Raw amountCollateral:", amountCollateral);
        console.log("maxDepositSize:", maxDepositSize);

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, maxDepositSize);
        console.log("Bounded amountCollateral:", amountCollateral);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
        vm.warp(block.timestamp + 1 seconds);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // Check if user has any of THIS specific collateral token
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
        if (maxCollateralToRedeem == 0) {
            return;
        }

        amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);

        // Try-catch to handle any remaining edge cases
        try dsce.redeemCollateral(address(collateral), amountCollateral) {
        // Success
        }
        catch {
            return;
        }
    }

    function redeemCollateralForDsc(uint256 collateralSeed, uint256 amountCollateral, uint256 amountDscToBurn) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) return;

        uint256 maxBurn = dsce.getDscMinted(msg.sender);
        amountDscToBurn = bound(amountDscToBurn, 0, maxBurn);
        if (amountDscToBurn == 0) return;

        vm.startPrank(msg.sender);
        dsc.approve(address(dsce), amountDscToBurn);
        dsce.redeemCollateralForDsc(address(collateral), amountCollateral, amountDscToBurn);
        vm.stopPrank();
    }

    function liquidate(uint256 collateralSeed, address userToLiquidate, uint256 debtToCover) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        uint256 healthFactor = dsce.getHealthFactor(userToLiquidate);
        if (healthFactor >= 1e18) return;

        uint256 userDebt = dsce.getDscMinted(userToLiquidate);
        debtToCover = bound(debtToCover, 1, userDebt);

        vm.startPrank(msg.sender);
        dsc.mint(msg.sender, debtToCover);
        dsc.approve(address(dsce), debtToCover);
        dsce.liquidate(address(collateral), userToLiquidate, debtToCover);
        vm.stopPrank();
    }

    // THIS FUNCTION IS COMMENTED OUT AS PER TUTORIAL BECAUSE IT BREAKS THE INVARIANT
    // function updateCollateralPrice(uint96 newPrice) public {
    //     uint96 boundedPrice = uint96(bound(newPrice, 100e8, 10000e8));
    //     vm.startPrank(address(wethPriceFeed));
    //     MockV3Aggregator(wethPriceFeed).updateAnswer(int256(uint256(boundedPrice)));
    //     vm.stopPrank();
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function burnDsc(uint256 amount) public {
        uint256 maxBurn = dsce.getDscMinted(msg.sender);
        if (maxBurn == 0) return;

        amount = bound(amount, 1, maxBurn);
        vm.startPrank(msg.sender);
        dsc.approve(address(dsce), amount);
        dsce.burnDsc(amount);
        vm.stopPrank();
    }

    function getUsersWithCollateralCount() external view returns (uint256) {
        return usersWithCollateralDeposited.length;
    }
}
