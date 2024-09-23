// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 10000e8;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            // Sepolia's ChainId is 11155111
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            // Since we only have 2 configs currently, we will use our catchall as local config.
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns(NetworkConfig memory sepoliaNetworkConfig){
        return sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY_SEP")
        });
    }
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        // create mock aggregator for each collateral
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS,ETH_USD_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS,BTC_USD_PRICE);
        // create mock ERC20 contracgts for the collateral
        ERC20Mock wethMock = new ERC20Mock("WETH","WETH",msg.sender, 1000e8);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC","WBTC",msg.sender, 1000e8);
        vm.stopBroadcast();

        return anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: vm.envUint("DEFAULT_ANVIL_KEY")
        });
    }
}