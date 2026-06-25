// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/ITwaporacle.sol";

contract MockOracle is ITwaporacle {
    int256 public mockPrice;

    function setPrice(int256 _price) external {
        mockPrice = _price;
    }

    // --- Required Implementations ---

    function decimals() external pure override returns (uint8) {
        return 8; // Chainlink standard
    }

    function description() external pure override returns (string memory) {
        return "Mock Oracle";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, mockPrice, 0, block.timestamp, 0);
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // Return mock data even if a specific round is requested
        return (0, mockPrice, 0, block.timestamp, 0);
    }
}