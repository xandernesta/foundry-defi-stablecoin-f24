// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title OracleLib
 * @author Xander Nesta
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * If the price is stale, the function will revert and render the DSCEngine unusable - this is by design.
 * For the safety of user funds we want the DSCEngine to freeze if there is an issue with prices
 *  
 * So if the Chainlink network explodes and you have a lot of money in this protocol... it'll stay there
 * 
 */
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__StalePrice();
    uint256 private constant TIMEOUT = 3 hours; // => In Solidity, 3 * 60 * 60 = 10800 seconds
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns(uint80, int256, uint256, uint256, uint80){
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;

        if (updatedAt == 0 || answeredInRound < roundId) revert OracleLib__StalePrice();

        if(secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }   
    function getTimeout(AggregatorV3Interface /* chainlinkFeed */ ) public pure returns (uint256) {
        return TIMEOUT;
    }
}