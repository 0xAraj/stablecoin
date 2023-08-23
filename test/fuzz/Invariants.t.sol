//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract HandlerInvariantTest is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
    Handler handler;

    function setUp() public {
        DeployDSC deployDSC = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployDSC.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
        handler = new Handler(dsc, dscEngine);
        targetContract(address(handler));
    }

    //Total supply of DSC should be less than total value of collateral
    // Getter view functions should never revert

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get total supply of dsc token
        // get total value of token collateral

        uint256 totalSupplyOfDsc = dsc.totalSupply();
        uint256 wethTotalDeposited = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 wbtcTotalDeposited = ERC20Mock(wbtc).balanceOf(address(dscEngine));

        uint256 wethValueInUsd = dscEngine.returnGetUsdValue(weth, wethTotalDeposited);
        uint256 wbtcValueInUsd = dscEngine.returnGetUsdValue(wbtc, wbtcTotalDeposited);

        uint256 totalCollateralValueInUsd = wethValueInUsd + wbtcValueInUsd;
        console.log("wethValue", wethValueInUsd);
        console.log("wbtcValue", wbtcValueInUsd);
        console.log("totalDscMinted", totalSupplyOfDsc);

        assert(totalCollateralValueInUsd >= totalSupplyOfDsc);
    }
}
