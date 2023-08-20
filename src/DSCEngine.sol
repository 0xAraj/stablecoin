//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__LengthShouldBeEqual();
    error DSCEngine__TransferFails();
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__MintingFails();
    error DSCEngine__HealthFactorIsGood();

    DecentralizedStableCoin private i_dsc;
    uint256 private constant PRICE_FEED_ADJUSTMENT = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant THRESHOLD_PERCENTAGE = 50;
    uint256 private constant THRESHOLD_PRECISION = 100;
    uint256 private constant MAX_THRESHOLD_VALUE = 1;
    uint256 private constant BONUS_PERCENTAGE = 10;
    address[] private s_collateralTokens;

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);
    event BurnDSC(address indexed user, uint256 indexed amount);

    /*
      @title DSCEngine
      @author Aditya Raj

      This system is designed to maintain the 1 token == 1$

      This stablecoin has the properties
      -Exogenoue collateral
      -Pegged to usd
      -Algorithmically stable

      @notice This contract handles all the logic of minting and burning of dsc token, also depositing and withdarawing of collaterals.

      @notice Contract should always be 'overcollateralize'.    
    */

    constructor(address[] memory tokenAddress, address[] memory priceFeed, address dsc) {
        if (tokenAddress.length != priceFeed.length) {
            revert DSCEngine__LengthShouldBeEqual();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeed[tokenAddress[i]] = priceFeed[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dsc);
    }

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*
    @param tokenCollateralAddress, The address of token to deposite as collateral
    @param amountCollateral, The amount of collateral to deposite
    */
    function depositeCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFails();
        }
    }

    /*
     @param amount, Amount that user to mint
     @notice They must have more collateral than they have minted token
    */

    function mintDsc(uint256 amount) public moreThanZero(amount) {
        s_dscMinted[msg.sender] += amount;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, amount);
        if (!success) {
            revert DSCEngine__MintingFails();
        }
    }

    function depositeCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositeCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDSCToMint);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(tokenCollateralAddress, msg.sender, msg.sender, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 amountDSCToBurn) public moreThanZero(amountDSCToBurn) {
        _burnDsc(msg.sender, msg.sender, amountDSCToBurn);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateralAndBurnDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function liquidator(address user, address tokenCollateralAddress, uint256 amountDscToLiquidate)
        external
        moreThanZero(amountDscToLiquidate)
        isAllowedToken(tokenCollateralAddress)
    {
        uint256 userStartingHealthFactor = _healthFactor(user);
        if (userStartingHealthFactor >= MAX_THRESHOLD_VALUE) {
            revert DSCEngine__HealthFactorIsGood();
        }

        uint256 collateralAmount = _getCollateralAmountFromUsd(tokenCollateralAddress, amountDscToLiquidate);
        uint256 bonusCollateral = (collateralAmount * BONUS_PERCENTAGE) / 100;
        uint256 totalCollateral = collateralAmount + bonusCollateral;

        _redeemCollateral(tokenCollateralAddress, user, msg.sender, totalCollateral);
        _burnDsc(user, msg.sender, amountDscToLiquidate);
        uint256 userFinalHealthFactor = _healthFactor(user);
        if (userFinalHealthFactor <= MAX_THRESHOLD_VALUE) {
            revert DSCEngine__HealthFactorIsBroken();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Internal Functions

    function _getCollateralAmountFromUsd(address token, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);

        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((amount * PRECISION) / (uint256(price) * PRICE_FEED_ADJUSTMENT));
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MAX_THRESHOLD_VALUE) {
            revert DSCEngine__HealthFactorIsBroken();
        }
    }

    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);

        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * THRESHOLD_PERCENTAGE) / THRESHOLD_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValue(user);
    }

    function getUsdValue(address token, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);

        (, int256 price,,,) = priceFeed.latestRoundData();

        return (((uint256(price)) * PRICE_FEED_ADJUSTMENT) * amount) / PRECISION;
    }

    function _redeemCollateral(address tokenCollateralAddress, address from, address to, uint256 amountCollateral)
        internal
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFails();
        }
    }

    function _burnDsc(address from, address to, uint256 amountDSCToBurn) internal {
        s_dscMinted[from] -= amountDSCToBurn;
        emit BurnDSC(from, amountDSCToBurn);

        bool success = i_dsc.transferFrom(to, address(this), amountDSCToBurn);
        if (!success) {
            revert DSCEngine__TransferFails();
        }
        i_dsc.burn(amountDSCToBurn);
    }

    // Public Functions

    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    // Getter functions

    function returnPriceFeedAddress(address tokenCollateralAddress) external view returns (address) {
        return s_priceFeed[tokenCollateralAddress];
    }

    function returnTokenCollateralAddress(uint256 index) external view returns (address) {
        return s_collateralTokens[index];
    }

    function returnDepositedCollateral(address tokenCollateralAddress) external view returns (uint256) {
        return s_collateralDeposited[msg.sender][tokenCollateralAddress];
    }

    function returnGetUsdValue(address token, uint256 amount) external view returns (uint256) {
        return getUsdValue(token, amount);
    }

    function returnGetAccountInformation(address user) external view returns (uint256, uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        return (totalDscMinted, totalCollateralValueInUsd);
    }

    function returnHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
