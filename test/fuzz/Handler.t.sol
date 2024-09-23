// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
// Will narrow down the way we call functions 

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
// import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// import {console} from "forge-std/console.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintDscIsCalled;
    address[] public usersWithDepositedCollateral;
    MockV3Aggregator public wethUsdPriceFeed;
    MockV3Aggregator public wbtcUsdPriceFeed;
    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        wethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        wbtcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
            collateral.mint(msg.sender, amountCollateral);
            collateral.approve(address(dscEngine), amountCollateral);
            dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // will double push is same address used twice
        usersWithDepositedCollateral.push(msg.sender);
    }
     // call redeem collateral <- when there is collateral
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxRedeemAmount = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxRedeemAmount);
        if(amountCollateral == 0){
            return;
        }
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }
    function mintDsc(uint256 addressSeed, uint256 amountToMint) public {
        if(usersWithDepositedCollateral.length == 0){
            return;
        }
        address msgSender = _getAddressFromSeed(addressSeed);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(msgSender);   
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2 ) - int256(totalDscMinted);
        if(maxDscToMint < 0){
            return;
        }
        amountToMint = bound(amountToMint,0,uint256(maxDscToMint));
        if(amountToMint == 0){
            return;
        }
        vm.startPrank(msgSender);
            dsc.approve(address(dscEngine),amountToMint);
            dscEngine.mintDsc(amountToMint);
            timesMintDscIsCalled++; 
        vm.stopPrank();
    }

    // This breaks our invariant if the newPrice is way below $2000e8
    /* function updateCollateralPrice(uint96 newPrice) public {
        int256 newPriceInt = int256(uint256(newPrice));
        wethUsdPriceFeed.updateAnswer(newPriceInt); 
    } */
    //////////////////////
    // Helper Functions //
    //////////////////////
    function _getCollateralFromSeed(uint256 _collateralSeed) private view returns(ERC20Mock){
        if(_collateralSeed % 2 == 0) {
            return ERC20Mock(weth);
        } else {
            return ERC20Mock(wbtc);
        }
    }
    function _getAddressFromSeed(uint256 _addressSeed) private view returns(address){
        return (usersWithDepositedCollateral[_addressSeed % usersWithDepositedCollateral.length]);
    }
}