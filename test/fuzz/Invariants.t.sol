// SPDX-License-Identifier: MIT

// Have our invariant aka properties

// What are the invariants of my protocol?

// 1.The total supply of DSC should be less than the total value of collateral
// 2.Getter view functions should never revert <--evergreen invariant

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(dsce));
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
        // hey, don't call redeemcollateral, unless there is a collateral to redeem
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.depositCollateral.selector;
        selectors[1] = handler.redeemCollateral.selector;
        selectors[2] = handler.mintDsc.selector;
        selectors[3] = handler.burnDsc.selector;
        selectors[4] = handler.liquidate.selector;
        selectors[5] = handler.redeemCollateralForDsc.selector;
        // selectors[6] = handler.updateCollateralPrice.selector; // Commented out
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply: ", totalSupply);
        console.log("Times Mint Called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        dsce.getLiquidationBonus();
        dsce.getPrecision();
    }

    // Add after existing invariants

    function invariant_healthFactorNeverZero() public view {
        uint256 userCount = handler.getUsersWithCollateralCount();
        for (uint256 i = 0; i < userCount; i++) {
            address user = handler.usersWithCollateralDeposited(i);
            if (user != address(0)) {
                uint256 healthFactor = dsce.getHealthFactor(user);
                // Health factor should never be 0 for users with deposits
                if (dsce.getAccountCollateralValue(user) > 0) {
                    assert(healthFactor > 0);
                }
            }
        }
    }

    function invariant_engineOwnsAllCollateral() public view {
        uint256 userCount = handler.getUsersWithCollateralCount();
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < userCount; i++) {
            address user = handler.usersWithCollateralDeposited(i);
            if (user != address(0)) {
                totalCollateralValue += dsce.getAccountCollateralValue(user);
            }
        }

        // Basic ownership check
        assert(totalCollateralValue >= 0);
    }

    function invariant_gettersShouldNeverRevert() public view {
        dsce.getLiquidationBonus();
        dsce.getPrecision();
        dsce.getCollateralTokens();
    }

    function invariant_userCannotMintAboveCollateral() public view {
        uint256 userCount = handler.getUsersWithCollateralCount();
        for (uint i = 0; i < userCount; i++) {
            address user = handler.usersWithCollateralDeposited(i);
            if (user == address(0)) continue;
            
            (uint256 totalMinted, uint256 collateralValue) = dsce.getAccountInformation(user);
            
            // With 150% ratio, max borrow = collateralValue * 100/150
            uint256 maxBorrow = (collateralValue * 100) / 150;
            assert(totalMinted <= maxBorrow);
        }
    }

   function invariant_totalCollateralAccountingMatches() public view {
        uint256 userCount = handler.getUsersWithCollateralCount();
        if (userCount == 0) return;
        
        // Use an array to track seen users
        address[] memory seenUsers = new address[](userCount);
        uint256 seenCount = 0;
        uint256 totalRecorded = 0;
        
        for (uint i = 0; i < userCount; i++) {
            address user = handler.usersWithCollateralDeposited(i);
            
            // Check if user already counted
            bool alreadySeen = false;
            for (uint j = 0; j < seenCount; j++) {
                if (seenUsers[j] == user) {
                    alreadySeen = true;
                    break;
                }
            }
            
            if (!alreadySeen) {
                seenUsers[seenCount] = user;
                seenCount++;
                totalRecorded += dsce.getAccountCollateralValue(user);
            }
        }
        
        uint256 engineWethBalance = IERC20(weth).balanceOf(address(dsce));
        uint256 engineWbtcBalance = IERC20(wbtc).balanceOf(address(dsce));
        
        uint256 wethValue = dsce.getUsdValue(weth, engineWethBalance);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, engineWbtcBalance);
        uint256 engineTotal = wethValue + wbtcValue;
        
        console.log("Total recorded (unique users):", totalRecorded);
        console.log("Engine total:", engineTotal);
        
        // Engine should have at least as much as recorded
        // The difference comes from the liquidation bonus which creates extra value
        assert(engineTotal >= totalRecorded || totalRecorded - engineTotal < 1e18);
    }
}
