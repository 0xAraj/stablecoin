//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
@title DecentralizedStableCoin
@author Aditya Raj

Collateral: ETH and BTC
Minting: alogorithmic
Ralative stabilty: pegged to USD

This is governed by DSCEngine. This contract is just implenentation of ERC20 token.
*/

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountIsZero();
    error DecentralizedStableCoin__BalanceIsLow();
    error DecentralizedStableCoin__ZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) {
            revert DecentralizedStableCoin__BalanceIsLow();
        }
        if (amount <= 0) {
            revert DecentralizedStableCoin__AmountIsZero();
        }

        super.burn(amount);
    }

    function mint(
        address to,
        uint256 amount
    ) external onlyOwner returns (bool) {
        if (amount == 0) {
            revert DecentralizedStableCoin__AmountIsZero();
        }
        if (to == address(0)) {
            revert DecentralizedStableCoin__ZeroAddress();
        }

        _mint(to, amount);
        return true;
    }
}
