//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
    address[] tokenAddress;
    address[] priceFeedAddress;
    address USER = makeAddr("user");

    uint256 public constant STARTING_USER_BALANCE = 20 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    function setUp() public {
        DeployDSC deployDSC = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployDSC.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    // Constructor testing

    function testRevertIfTokenLengthDoesNotMatchPriceFeed() public {
        tokenAddress.push(weth);
        tokenAddress.push(wbtc);
        priceFeedAddress.push(wethUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__LengthShouldBeEqual.selector);
        new DSCEngine(tokenAddress, priceFeedAddress,address(dsc));
    }

    function testConstructorIsSettingAddressesToMapping() public {
        tokenAddress.push(weth);
        tokenAddress.push(wbtc);
        priceFeedAddress.push(wethUsdPriceFeed);
        priceFeedAddress.push(wbtcUsdPriceFeed);

        DSCEngine newEngine = new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            address token = newEngine.returnTokenCollateralAddress(i);
            address priceFeed = newEngine.returnPriceFeedAddress(token);

            assert(token == tokenAddress[i]);
            assert(priceFeed == priceFeedAddress[i]);
        }
    }

    // Deposite collateral

    function testRevertIfCollateralAmountIsZero() public {
        uint256 depositeAmount = 0 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositeCollateral(weth, depositeAmount);
        vm.stopPrank();
    }

    function testRevertIfCollateralAddressIsNotValid() public {
        uint256 depositeAmount = 1 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(USER, STARTING_USER_BALANCE);
        randomToken.approve(address(dscEngine), approvedAmount);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositeCollateral(address(randomToken), depositeAmount);
        vm.stopPrank();
    }

    function testShouldDepositeCollateralAndUpdateData() public {
        uint256 depositeAmount = 2 ether;
        uint256 approvedAmount = 10 ether;
        uint256 startingWethBalanceOfDscEngine = ERC20Mock(weth).balanceOf(address(dscEngine));
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        dscEngine.depositeCollateral(weth, depositeAmount);

        uint256 actualDepositedAmount = dscEngine.returnDepositedCollateral(weth);
        uint256 finalWethBalanceOfDscEngine = ERC20Mock(weth).balanceOf(address(dscEngine));
        assert(depositeAmount == actualDepositedAmount);
        assert(finalWethBalanceOfDscEngine == startingWethBalanceOfDscEngine + depositeAmount);
    }

    function testDepositeCollaterealShouldEmitEvent() public {
        uint256 depositeAmount = 2 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        vm.expectEmit(address(dscEngine));
        emit CollateralDeposited(USER, weth, depositeAmount);
        dscEngine.depositeCollateral(weth, depositeAmount);
    }

    // PriceFeed testing

    function testGetUsdValue() public {
        uint256 amount = 2 ether;
        uint256 expectedUsdValue = amount * 2000;
        vm.startPrank(USER);
        uint256 actualUsdValue = dscEngine.returnGetUsdValue(weth, amount);

        assert(actualUsdValue == expectedUsdValue);
    }

    function testGetAccountCollateralValue() public {
        uint256 ethDepositeAmount = 2 ether;
        uint256 btcDepositedAmount = 4 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        ERC20Mock(wbtc).approve(address(dscEngine), approvedAmount);
        dscEngine.depositeCollateral(weth, ethDepositeAmount);
        dscEngine.depositeCollateral(wbtc, btcDepositedAmount);

        uint256 ethValue = ethDepositeAmount * 2000;
        uint256 btcValue = btcDepositedAmount * 1000;
        uint256 expectedTotalCollateralValue = ethValue + btcValue;
        uint256 actualTotalCollateralValue = dscEngine.getAccountCollateralValue(USER);
        assert(actualTotalCollateralValue == expectedTotalCollateralValue);
    }

    function testGetAccountInformation() public {
        uint256 ethDepositeAmount = 2 ether;
        uint256 btcDepositedAmount = 4 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        ERC20Mock(wbtc).approve(address(dscEngine), approvedAmount);
        dscEngine.depositeCollateral(weth, ethDepositeAmount);
        dscEngine.depositeCollateral(wbtc, btcDepositedAmount);

        uint256 ethValue = ethDepositeAmount * 2000;
        uint256 btcValue = btcDepositedAmount * 1000;
        uint256 expectedTotalCollateralValue = ethValue + btcValue;
        uint256 expectedDscMinted = 0;
        (uint256 actualDscMinted, uint256 actualTotalCollateralValue) = dscEngine.returnGetAccountInformation(USER);
        assert(actualTotalCollateralValue == expectedTotalCollateralValue);
        assert(actualDscMinted == expectedDscMinted);
    }

    // function testHealthFactor() public {
    //     uint256 ethDepositeAmount = 2 ether;
    //     uint256 btcDepositedAmount = 4 ether;
    //     uint256 approvedAmount = 10 ether;
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
    //     ERC20Mock(wbtc).approve(address(dscEngine), approvedAmount);
    //     dscEngine.depositeCollateral(weth, ethDepositeAmount);
    //     dscEngine.depositeCollateral(wbtc, btcDepositedAmount);

    //       uint256 healthFactor = dscEngine.returnHealthFactor(USER);
    //      console.log(healthFactor);
    // }
}
