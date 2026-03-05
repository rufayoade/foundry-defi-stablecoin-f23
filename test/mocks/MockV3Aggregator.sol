// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockV3Aggregator {
    int256 private _price;
    uint8 private _decimals;

    constructor(uint8 _decimals_, int256 _initialPrice) {
        _decimals = _decimals_;
        _price = _initialPrice;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _price, 0, block.timestamp, 0);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function updateAnswer(int256 _newPrice) public {
        _price = _newPrice;
    }
}
