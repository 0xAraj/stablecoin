//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract DSCEngina is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__LengthShouldBeEqual();
    error DSCEngine__TransferFails();

    DecentralizedStableCoin private i_dsc;
    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

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

    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeed,
        address dsc
    ) {
        if (tokenAddress.length != priceFeed.length) {
            revert DSCEngine__LengthShouldBeEqual();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeed[tokenAddress[i]] = priceFeed[i];
        }
        i_dsc = DecentralizedStableCoin(dsc);
    }

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeed[token] != address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*
@param tokenCollateralAddress, The address of token to deposite as collateral
@param amountCollateral, The amount of collateral to deposite
*/
    function depositeCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );

        if (!success) {
            revert DSCEngine__TransferFails();
        }
    }
}
