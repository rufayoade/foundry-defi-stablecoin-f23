// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TimeAwareMockAggregator is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;
    uint256 private _updatedAt;
    uint80 private _roundId;
    
    constructor(uint8 _decimals_, int256 _initialPrice) {
        _decimals = _decimals_;
        _price = _initialPrice;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }
    
    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }
    
    function getRoundData(uint80) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }
    
    function decimals() external view override returns (uint8) {
        return _decimals;
    }
    
    function description() external pure override returns (string memory) {
        return "Time Aware Mock Aggregator";
    }
    
    function version() external pure override returns (uint256) {
        return 1;
    }
    
    function updatePrice(int256 _newPrice) external {
        _price = _newPrice;
        _updatedAt = block.timestamp;
        _roundId++;
    }
}