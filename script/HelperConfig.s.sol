//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    uint8 constant DECIMAL = 8;
    int256 constant ETH_INITIAL_VALUE = 2000e8;
    int256 constant BTC_INITIAL_VALUE = 1000e8;
    uint256 constant ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkingConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkingConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkingConfig memory) {
        return NetworkingConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getAnvilConfig() public returns (NetworkingConfig memory) {
        if (activeNetworkConfig.wbtcUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(
            DECIMAL,
            ETH_INITIAL_VALUE
        );
        ERC20Mock wethMock = new ERC20Mock();

        MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(
            DECIMAL,
            BTC_INITIAL_VALUE
        );
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkingConfig({
            wethUsdPriceFeed: address(wethPriceFeed),
            wbtcUsdPriceFeed: address(wbtcPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: ANVIL_PRIVATE_KEY
        });
    }
}
