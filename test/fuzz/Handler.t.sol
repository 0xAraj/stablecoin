//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    address weth;
    address wbtc;
    address[] private userAddress;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;
        weth = dscEngine.returnTokenCollateralAddress(0);
        wbtc = dscEngine.returnTokenCollateralAddress(1);
    }

    function depositeCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address tokenCollateralAddress = getTokenCollateralAddress(collateralSeed);
        vm.startPrank(msg.sender);
        amountCollateral = bound(amountCollateral, 1, type(uint96).max);

        ERC20Mock(tokenCollateralAddress).mint(msg.sender, amountCollateral);
        ERC20Mock(tokenCollateralAddress).approve(address(dscEngine), amountCollateral);
        dscEngine.depositeCollateral(tokenCollateralAddress, amountCollateral);
        userAddress.push(msg.sender);
    }

    function mintDsc(uint256 amountToMint) public {
        if (userAddress.length == 0) {
            return;
        }
        uint256 index = amountToMint % userAddress.length;
        address user = userAddress[index];
        vm.startPrank(user);
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine.returnGetAccountInformation(user);
        int256 mintableAmount = (int256(totalCollateralValueInUsd) / 2) - int256(totalDscMinted);
        if (mintableAmount <= 0) {
            return;
        }
        amountToMint = bound(amountToMint, 1, uint256(mintableAmount));

        dscEngine.mintDsc(amountToMint);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address tokenCollateralAddress = getTokenCollateralAddress(collateralSeed);
        vm.startPrank(msg.sender);
        uint256 amountDeposited = dscEngine.returnDepositedCollateral(tokenCollateralAddress);
        if (amountDeposited == 0) {
            return;
        }
        amountCollateral = bound(amountCollateral, 1, amountDeposited);

        dscEngine.redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    // Helper function

    function getTokenCollateralAddress(uint256 collateralSeed) public view returns (address) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
