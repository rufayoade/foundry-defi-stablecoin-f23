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
}
