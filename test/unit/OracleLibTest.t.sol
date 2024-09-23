// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { OracleLib, AggregatorV3Interface } from "../../src/libraries/OracleLib.sol";

contract OracleLibTest is StdCheats, Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator public priceFeed;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000 ether;
    function setUp() public {
        priceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }
    function testRevertOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours + 1 seconds);
        vm.roll(block.number + 1);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(priceFeed)).staleCheckLatestRoundData();
    }

    function testGetTimeout() public view {
        uint256 expectedTime = 3 hours;
        assertEq(expectedTime, OracleLib.getTimeout(AggregatorV3Interface(address(priceFeed))));
    }

    function testRevertsOnBadAnswerInRound() public {
        uint80 _roundId = 0; 
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0; 
       priceFeed.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

       vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
       AggregatorV3Interface(address(priceFeed)).staleCheckLatestRoundData();

    }

}