// SPDX-License-Identifier: MIT
// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Xander Nesta
 * Collateral: Exogenous
 * Minting: Algorithmic
 * Relative Stability: Anchored to US Dollar
 *
 * This is the contract to be governed by DSCEngine. This contract is the ERC20 implementation of our stablecoin system.
 *
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__MustNotExceedBalance();
    error DecentralizedStableCoin__NotZeroAddress();
    error DecentralizedStableCoin__BlockFunction();
    /* 
    * CHANGE OWNER ADDRESS BEFORE DEPLOYMENT!!!
    //  */
    //     address private constant DEFAULT_OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    // New openzeppelin contract requires an initial owner so it's set to the first anvil default address
    // Made it so you have to pass in an owner to deploy contract

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(address(msg.sender)) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert DecentralizedStableCoin__MustNotExceedBalance();
        }
        super.burn(_amount);
    }

    function burnFrom(address, uint256) public pure override {
        revert DecentralizedStableCoin__BlockFunction();
    }
    
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        } 
        _mint(_to, _amount);
        return true;
    }
}
