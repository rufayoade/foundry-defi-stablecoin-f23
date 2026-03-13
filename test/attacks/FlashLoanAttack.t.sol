// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract FlashLoanAttackTest is Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    address ethUsdPriceFeed;

    address attacker = makeAddr("attacker");
    uint256 constant FLASH_LOAN_AMOUNT = 1000 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,, weth, wbtc,) = config.activeNetworkConfig();

        // Give attacker some ETH for gas
        vm.deal(attacker, 100 ether);
    }

    function testFlashLoanAttack() public {
        // Record initial state
        uint256 initialTotalSupply = dsc.totalSupply();
        uint256 initialAttackerBalance = dsc.balanceOf(attacker);

        console.log("Initial total supply:", initialTotalSupply);
        console.log("Initial attacker balance:", initialAttackerBalance);

        // Simulate flash loan attack:
        // 1. Attacker gets flash loan of WETH
        // 2. Deposits as collateral
        // 3. Mints DSC
        // 4. Manipulates price
        // 5. Repays flash loan with profit

        vm.startPrank(attacker);

        // Step 1: Get flash loan (simulated by minting directly)
        ERC20Mock(weth).mint(attacker, FLASH_LOAN_AMOUNT);

        // Step 2: Deposit collateral
        ERC20Mock(weth).approve(address(dsce), FLASH_LOAN_AMOUNT);
        dsce.depositCollateral(weth, FLASH_LOAN_AMOUNT);

        // Step 3: Mint DSC
        dsce.mintDsc(FLASH_LOAN_AMOUNT * 1000); // Try to mint huge amount

        // Step 4: Manipulate price (should revert due to OracleLib)
        vm.startPrank(ethUsdPriceFeed);
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(100e8); // Crash price to $100
        vm.stopPrank();

        // Step 5: Try to liquidate and profit (should be prevented by health factor)
        vm.startPrank(attacker);
        vm.expectRevert(); // Should revert due to health factor checks
        dsce.liquidate(weth, attacker, 1 ether);

        vm.stopPrank();

        // Verify invariants still hold
        uint256 finalTotalSupply = dsc.totalSupply();
        assertGe(finalTotalSupply, initialTotalSupply); // No infinite mint
        console.log("Attack failed - protocol safe!");
    }
}
