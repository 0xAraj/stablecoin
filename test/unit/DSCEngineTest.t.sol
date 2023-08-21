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
    address LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant STARTING_USER_BALANCE = 20 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    function setUp() public {
        DeployDSC deployDSC = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployDSC.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(LIQUIDATOR, STARTING_USER_BALANCE);
    }

    // Constructor testing

    function testRevertIfTokenLengthDoesNotMatchPriceFeed() public {
        tokenAddress.push(weth);
        tokenAddress.push(wbtc);
        priceFeedAddress.push(wethUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__LengthShouldBeEqual.selector);
        new DSCEngine(tokenAddress, priceFeedAddress,address(dsc));
    }

    function testConstructorIsSettingAddressesToMappingAndDSCAddress() public {
        tokenAddress.push(weth);
        tokenAddress.push(wbtc);
        priceFeedAddress.push(wethUsdPriceFeed);
        priceFeedAddress.push(wbtcUsdPriceFeed);
        address epectedDSCAddress = address(dsc);

        DSCEngine newEngine = new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));
        DecentralizedStableCoin newDSC = newEngine.returnDSCAddress();
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            address token = newEngine.returnTokenCollateralAddress(i);
            address priceFeed = newEngine.returnPriceFeedAddress(token);

            assert(token == tokenAddress[i]);
            assert(priceFeed == priceFeedAddress[i]);
        }
        assert(epectedDSCAddress == address(newDSC));
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
        uint256 depositeAmount = 5 ether;
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
        uint256 depositeAmount = 5 ether;
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
        uint256 depositeAmount = 5 ether;
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

    function testHealthFactorWhenMintedDscIsZero() public {
        uint256 ethDepositeAmount = 2 ether;
        uint256 btcDepositedAmount = 4 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        ERC20Mock(wbtc).approve(address(dscEngine), approvedAmount);
        dscEngine.depositeCollateral(weth, ethDepositeAmount);
        dscEngine.depositeCollateral(wbtc, btcDepositedAmount);

        uint256 expectedHealthFactor = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
        uint256 actualHealthFactor = dscEngine.returnHealthFactor(USER);

        assert(expectedHealthFactor == actualHealthFactor);
    }

    function testMintDscWhenDscMintedIsZeroInitially() public {
        uint256 ethDepositeAmount = 2 ether;
        uint256 btcDepositedAmount = 4 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        ERC20Mock(wbtc).approve(address(dscEngine), approvedAmount);
        dscEngine.depositeCollateral(weth, ethDepositeAmount);
        dscEngine.depositeCollateral(wbtc, btcDepositedAmount);

        uint256 amount = 5 ether;
        dscEngine.mintDsc(amount);
        uint256 actualMintDsc = dsc.balanceOf(USER);
        uint256 mintDscBalanceInMapping = dscEngine.returnMintedDsc(USER);
        assert(actualMintDsc == amount);
        assert(mintDscBalanceInMapping == amount);
    }

    function testRevertMintDscWhenUserMintMoreThanLimitWhenMintedDscIsZeroInitially() public {
        uint256 ethDepositeAmount = 2 ether;
        uint256 btcDepositedAmount = 4 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        ERC20Mock(wbtc).approve(address(dscEngine), approvedAmount);
        dscEngine.depositeCollateral(weth, ethDepositeAmount);
        dscEngine.depositeCollateral(wbtc, btcDepositedAmount);

        uint256 amount = 5000 ether;
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.mintDsc(amount);
    }

    // function testDepositeCollateralAndMintDsc() public {
    //     uint256 ethDepositeAmount = 2 ether;
    //     uint256 approvedAmount = 10 ether;
    //     uint256 startingWethBalanceOfDscEngine = ERC20Mock(weth).balanceOf(address(dscEngine));
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
    //     uint256 amountToMint = 2 ether;

    //     dscEngine.depositeCollateralAndMintDSC(weth, ethDepositeAmount, amountToMint);
    //     uint256 actualMintDsc = dsc.balanceOf(USER);
    //     console.log(actualMintDsc);
    //     uint256 mintDscBalanceInMapping = dscEngine.returnMintedDsc(USER);
    //     uint256 actualDepositedAmount = dscEngine.returnDepositedCollateral(weth);
    //     uint256 finalWethBalanceOfDscEngine = ERC20Mock(weth).balanceOf(address(dscEngine));
    //     assert(ethDepositeAmount == actualDepositedAmount);
    //     assert(finalWethBalanceOfDscEngine == startingWethBalanceOfDscEngine + ethDepositeAmount);
    //     assert(actualMintDsc == amountToMint);
    //     assert(mintDscBalanceInMapping == amountToMint);
    // }

    function testRevertRedeemCollateralIfMoreThanDepositeIsWithdrawed() public {
        uint256 depositeAmount = 2 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        dscEngine.depositeCollateral(weth, depositeAmount);

        uint256 redeemCollateral = 3 ether;
        vm.expectRevert(DSCEngine.DSCEngine__RedeemingMoreThanDeposite.selector);
        dscEngine.redeemCollateral(weth, redeemCollateral);
    }

    function testShouldRedeemCollateralAndEmitEvent() public {
        uint256 depositeAmount = 2 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        dscEngine.depositeCollateral(weth, depositeAmount);

        uint256 redeemCollateral = 2 ether;
        uint256 initialDepositedCollateral = dscEngine.returnDepositedCollateral(weth);
        uint256 initialWethBalanceOfUser = ERC20Mock(weth).balanceOf(USER);
        vm.expectEmit();
        emit CollateralRedeemed(USER, USER, weth, redeemCollateral);
        dscEngine.redeemCollateral(weth, redeemCollateral);
        uint256 finalDepositeCollateral = dscEngine.returnDepositedCollateral(weth);
        uint256 finalWethBalanceOfUser = ERC20Mock(weth).balanceOf(USER);
        assert(finalDepositeCollateral == initialDepositedCollateral - redeemCollateral);
        assert(finalWethBalanceOfUser == initialWethBalanceOfUser + redeemCollateral);
    }

    function testRevertRedeemCollateralIfHealthFactorIsBroken() public {
        uint256 ethDepositeAmount = 5 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        uint256 amountToMint = 5000 ether;

        dscEngine.depositeCollateralAndMintDSC(weth, ethDepositeAmount, amountToMint);

        uint256 amountToRedeem = 1 ether;
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.redeemCollateral(weth, amountToRedeem);
    }

    function testBurnDscShouldEmitEventAndTransferDscToDscEngine() public {
        uint256 ethDepositeAmount = 5 ether;
        uint256 approvedAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmount);
        uint256 amountToMint = 50 ether;

        dscEngine.depositeCollateralAndMintDSC(weth, ethDepositeAmount, amountToMint);

        uint256 amountDscToBurn = 10 ether;
        uint256 initialDscBalanceOfUser = dsc.balanceOf(USER);
        uint256 initialDscMintedToUser = dscEngine.returnMintedDsc(USER);
        ERC20Mock(address(dsc)).approve(address(dscEngine), amountDscToBurn);

        dscEngine.burnDSC(amountDscToBurn);
        uint256 finalDscBalanceOfUser = dsc.balanceOf(USER);
        uint256 finalDscBalanceOfDscEngine = dsc.balanceOf(address(dscEngine));
        uint256 finalDscMintedToUser = dscEngine.returnMintedDsc(USER);
        assert(finalDscBalanceOfDscEngine == 0);
        assert(finalDscBalanceOfUser == initialDscBalanceOfUser - amountDscToBurn);
        assert(finalDscMintedToUser == initialDscMintedToUser - amountDscToBurn);
    }

    function testRevertLiquidateIfHealthFactorIsGood() public {
        uint256 ethDepositeAmountOfUser = 5 ether;
        uint256 approvedAmountOfUser = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmountOfUser);
        uint256 amountToMintOfUser = 50 ether;
        dscEngine.depositeCollateralAndMintDSC(weth, ethDepositeAmountOfUser, amountToMintOfUser);
        vm.stopPrank();

        uint256 ethDepositeAmountOfLiquidator = 8 ether;
        uint256 approvedAmountOfLiquidator = 10 ether;
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), approvedAmountOfLiquidator);
        uint256 amountToMintOfLiquidator = 80 ether;
        dscEngine.depositeCollateralAndMintDSC(weth, ethDepositeAmountOfLiquidator, amountToMintOfLiquidator);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsGood.selector);
        dscEngine.liquidator(USER, weth, 20);
    }
}
