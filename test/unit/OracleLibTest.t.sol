// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {TimeAwareMockAggregator} from "../mocks/TimeAwareMockAggregator.sol";

contract OracleLibTest is Test {
    TimeAwareMockAggregator mockAggregator;

    function setUp() public {
        mockAggregator = new TimeAwareMockAggregator(8, 2000e8);
    }

    function testFreshPricePasses() public view {
        OracleLib.staleCheckLatestRoundData(mockAggregator);
    }

    function testStalePriceReverts() public {
        vm.warp(block.timestamp + 4 hours);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(mockAggregator);
    }

    function testStalePriceAfterTimeout() public {
        // Fast forward 4 hours (beyond the 3 hour timeout)
        vm.warp(block.timestamp + 4 hours);

        // This should revert because price is now stale
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(mockAggregator);
    }

    function testTimeAwareMockFunctions() public {
        // Test getRoundData
        (uint80 roundId, int256 answer,,,) = mockAggregator.getRoundData(0);
        assertEq(roundId, 1);
        assertEq(answer, 2000e8);

        // Test description
        assertEq(mockAggregator.description(), "Time Aware Mock Aggregator");

        // Test version
        assertEq(mockAggregator.version(), 1);

        // Test updatePrice
        mockAggregator.updatePrice(3000e8);
        (, answer,,,) = mockAggregator.latestRoundData();
        assertEq(answer, 3000e8);
    }
}
