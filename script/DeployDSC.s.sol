//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    HelperConfig helperConfig;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    address[] private tokenAddress;
    address[] private priceFeedAddress;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        helperConfig = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        tokenAddress = [weth, wbtc];
        priceFeedAddress = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.startBroadcast(deployerKey);
        dsc = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}
