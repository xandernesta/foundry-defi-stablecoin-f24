// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
// import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol"; Updated mock location
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockFailedTransfer } from "../mocks/MockFailedTransfer.sol";
import { MockFailedTransferFrom } from "../mocks/MockFailedTransferFrom.sol";
import { MockFailedMintDSC } from "../mocks/MockFailedMintDSC.sol";
import { MockMoreDebtDSC } from "../mocks/MockMoreDebtDSC.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract DSCEngineTest is StdCheats, Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_DSC = 1000 ether;
    uint256 public amountDscToMint = 100 ether;
    uint256 public constant START_ERC20_BALANCE = 10 ether;
    uint256 public collateralToCover = 20 ether;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        vm.deal(USER, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(USER, START_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, START_ERC20_BALANCE);

    }
    /** Things to test 
     * Constructor:
    * Cannot duplicate token addresses in constructor
    * cannot have addresses and pricefeed arrays of not equal lengths
    * Deposit:
    * Deposit collateral has to be more than zero
    * Deposit fails if transfer from fails
    * Deposit of non-allowd token fails
    * Deposit fails if collateral
    * Deposit succeeds without minting
    * Can Deposit and then get Account info
    * PriceFeed:
    * test getTokenAmountFromUsd
    * test getUsdValue
    */

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    // Test the reverts work

    function testRevertsIfTokenAddressLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }
    function testRevertsIfDuplicateTokenAddresses() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        
        vm.expectRevert(DSCEngine.DSCEngine__DuplicateCollateralAddressInConstructor.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////
    // PriceFeed Tests //
    /////////////////////
    function testGetUsdValueRevertsIfTokenAddressZero() public{
        uint256 tokenAmount = 15e18;
        vm.expectRevert(DSCEngine.DSCEngine__MustBeAllowedToken.selector);
        dscEngine.getUsdValue(address(0), tokenAmount);
    }
    function testGetUsdValue() public view {
        uint256 wethAmount = 15e18;
        // math should be 15e18 * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, wethAmount);
        assertEq(expectedUsd,actualUsd);
    }
    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // $2000 / ETH, (100)
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    //////////////////////////////
    // DepositCollateral Tests //
    /////////////////////////////

    function testDepositMustBeMoreThanZero() public {
        vm.startPrank(USER);
        // Need to approve transfer first
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", USER, START_ERC20_BALANCE);
        vm.startPrank(USER);
            vm.expectRevert(DSCEngine.DSCEngine__MustBeAllowedToken.selector);
            dscEngine.depositCollateral(address(randomToken), START_ERC20_BALANCE);
        vm.stopPrank();
    }

    function testDepositRevertsIfTransferFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [wethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine testEngine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL);
        vm.prank(owner);
        mockDsc.transferOwnership(address(testEngine));
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(testEngine),AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        testEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    
    modifier depositedCollateral() {
        vm.startPrank(USER);
            ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
            dscEngine.depositCollateral(address(weth), AMOUNT_COLLATERAL);
        vm.stopPrank();
       _; 
    }
    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        uint256 totalDscMinted;
        uint256 userCollatValue;
        (totalDscMinted, userCollatValue) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDscMinited = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, userCollatValue);
/*          Not needed because of modifier   
            vm.startPrank(USER);
            ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
            dscEngine.depositCollateral(address(weth), AMOUNT_COLLATERAL);
            vm.stopPrank(); */
        assertEq(totalDscMinted, expectedTotalDscMinited);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
    
    ///////////////////////////////////////
    // DepositCollateralAndMintDsc Tests //
    ///////////////////////////////////////
        modifier depositedCollateralAndMintedDsc() {
            vm.startPrank(USER);
                ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
                dscEngine.depositCollateralAndMintDsc(address(weth), AMOUNT_COLLATERAL, AMOUNT_DSC);
                // AMOUNT_COLLATERAL = 10 weth
                // AMOUNT_DSC = 1000 DSC
                // HealthFactor = 10 000000000000000000
            vm.stopPrank();
        _; 
        }
        function testDepositCollateralAndMintDsc() public depositedCollateralAndMintedDsc {
            (uint256 userMintedDsc, uint256 userCollatValue) = dscEngine.getAccountInformation(USER);
            assertEq(userMintedDsc, AMOUNT_DSC);
            assertEq(userMintedDsc, dsc.balanceOf(USER));
            assertEq(userCollatValue, dscEngine.getUsdValue(address(weth), AMOUNT_COLLATERAL));
            uint256  userHealthFactor = (dscEngine.getHealthFactor(USER));
            console.log("USER healthFactor: ", userHealthFactor);
        }

        function testRevertsIfDepositAndMintBreaksHealthFactor() public {
            uint256 amountDscToBreakHealthFactor = 15000 ether;
            // AMOUNT_COLLATERAL = 10 ETHER, Price of ETHER $2000
            // 10 * 2000 = 20 000 which needs to be 200% of DSC value for healthy collateral
            // 20 000 / 15 000 = 133% so broken health factor
            uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(amountDscToBreakHealthFactor, dscEngine.getUsdValue(address(weth),AMOUNT_COLLATERAL));
            vm.startPrank(USER);
                ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
                vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
                dscEngine.depositCollateralAndMintDsc(address(weth), AMOUNT_COLLATERAL, amountDscToBreakHealthFactor);
            vm.stopPrank();
            console.log("expectedHF: ", expectedHealthFactor);
            // expected HF = .666666666666666666
        }

    //////////////////////////////
    // RedeemCollateral Tests //
    /////////////////////////////

    // testRevertIfRedeemAmountIsZero
    /* failing test
    function testRevertsIfRedeemCollateralBreaksHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 startingHealthFactor = dscEngine.getHealthFactor(USER);
        console.log("health factor", startingHealthFactor);
        uint256 amountCollatToRedeem = AMOUNT_COLLATERAL - 9e13;
        console.log("amountCollatToRedeem", amountCollatToRedeem);
        // 9.999910000000000000 so only .00009 weth left * $2000 = $0.18
        console.log("USD value of Collate to redeem", dscEngine.getUsdValue(address(weth), amountCollatToRedeem));
        // $19999 800000000000000000  
        uint256 expectedEndHealthFactor = dscEngine.calculateHealthFactor(AMOUNT_DSC, dscEngine.getUsdValue(address(weth), amountCollatToRedeem));
        console.log("expected end HF:", expectedEndHealthFactor);
        // 1  111100000000000000   9 999900000000000000 
        console.log("minted DSC", dsc.balanceOf(USER));
        // 1000000000000000000000
        vm.startPrank(USER);
            vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedEndHealthFactor/* dscEngine.getHealthFactor(USER) *//*));
            dscEngine.redeemCollateral(address(weth), amountCollatToRedeem);
        vm.stopPrank();
    } */
    /* function testRevertsIfRedeemCollateralTransferFails() public depositedCollateral {
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        vm.startPrank(USER);
            vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
            dscEngine.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();

    } */
   function testCanRedeemCollateral() public depositedCollateral{
    // Collateral deposited == AMOUNT_COLLATERAL , collateral type = weth
    uint256 startingUserBalance = ERC20Mock(weth).balanceOf(USER);
    // should be 0 weth
    vm.prank(USER);
     dscEngine.redeemCollateral(address(weth), AMOUNT_COLLATERAL);
     //redeem all collateral
     uint256 endingUserBalance = ERC20Mock(weth).balanceOf(USER);
     assertEq(startingUserBalance, 0);
     assertEq(endingUserBalance, AMOUNT_COLLATERAL);
   }

    //////////////////////////////////
    // RedeemCollateralForDsc Tests //
    //////////////////////////////////
    function testRedeemCollateralForDscMustBeMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
            dsc.approve(address(dscEngine), AMOUNT_DSC);
            vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
            dscEngine.redeemCollateralForDsc(weth, 0, AMOUNT_DSC);
        vm.stopPrank();
    }    
    function testCanRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        assertEq(ERC20Mock(weth).balanceOf(USER),0);
        vm.startPrank(USER);
            dsc.approve(address(dscEngine), AMOUNT_DSC);
            dscEngine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC);
        vm.stopPrank();
        assertEq(dsc.balanceOf(USER), 0);
        assertEq(ERC20Mock(weth).balanceOf(USER), AMOUNT_COLLATERAL);
    }

    ///////////////////
    // mintDsc Tests //
    ///////////////////

        function testRevertsIfMintFails() public {
            //Arrange
            // Need mockDSC and mockDSEngine
            MockFailedMintDSC mockDsc = new MockFailedMintDSC();
            //Will only use single collateral and single pricefeed for this test
            tokenAddresses = [weth];
            priceFeedAddresses = [wethUsdPriceFeed];
            address owner = msg.sender;
            vm.prank(owner);
            DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
            mockDsc.transferOwnership(address(mockDscEngine));
            //Act/Assert
            vm.startPrank(USER);
            ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
            vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
            mockDscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC);
            vm.stopPrank();
        }
    function testCanMintDsc() public depositedCollateral {
        uint256 amountToMint = 10 ether;
        vm.startPrank(USER);
            dsc.approve(address(dscEngine),amountToMint);
            dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
        assertEq(amountToMint, dsc.balanceOf(USER));


    }

    ///////////////////
    // burnDsc Tests //
    ///////////////////
    function testRevertsIfAttemptsToBurnZeroDSC() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
            vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
            dscEngine.burnDsc(0);
        vm.stopPrank();
    }

/* test is reverting with EVM Error - not sure why     
function testBurnRevertsIfTransferFails() public {
    address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [wethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_DSC);
        console.log("user amount DSC", mockDsc.balanceOf(USER));
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce),(AMOUNT_DSC * AMOUNT_DSC));
        mockDsce.depositCollateralAndMintDsc(address(mockDsc), AMOUNT_DSC, AMOUNT_DSC);
        console.log("user amount DSC After Collate/Mint:", mockDsc.balanceOf(USER));

        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.burnDsc(AMOUNT_DSC);
        vm.stopPrank();
    } */

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        uint256 amountToBurn = AMOUNT_DSC;
        vm.startPrank(USER);
        dsc.approve(address(dscEngine),amountToBurn);
        dscEngine.burnDsc(amountToBurn);
        vm.stopPrank();
        uint256 newUserDscBalance = dsc.balanceOf(USER);
        assertEq(newUserDscBalance,0);
    }

    function testInternalBurnDscWorks() public depositedCollateralAndMintedDsc {
        uint256 amountToBurn = AMOUNT_DSC;
        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL);
        vm.startPrank(LIQUIDATOR);
            ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
            dscEngine.depositCollateralAndMintDsc(address(weth),AMOUNT_COLLATERAL, amountToBurn);
        vm.stopPrank();
        //ACT
        vm.startPrank(LIQUIDATOR);
        console.log("starting Liquidator DSC: ", dsc.balanceOf(LIQUIDATOR));
        dsc.approve(address(dscEngine), amountToBurn);
        dscEngine._burnDsc(amountToBurn, USER, LIQUIDATOR);
        vm.stopPrank();
        uint256 endingLiquidatorDscBalance = dsc.balanceOf(LIQUIDATOR);
        // Assert
        assertEq(endingLiquidatorDscBalance, 0);
    }


    /////////////////////
    // liquidate Tests //
    /////////////////////
    function testMustImproveHealthFactorOnLiquidation() public {
        //setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(wethUsdPriceFeed);
        //Will only use single collateral and single pricefeed for this test
        tokenAddresses = [weth];
        priceFeedAddresses = [wethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDscEngine));

        vm.startPrank(USER);
            ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
            mockDscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC);
        vm.stopPrank();

        //Arrange
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);
        
        vm.startPrank(LIQUIDATOR);
            ERC20Mock(weth).approve(address(mockDscEngine), collateralToCover);
            uint256 debtToCover = 10 ether;
            mockDscEngine.depositCollateralAndMintDsc(weth, collateralToCover ,AMOUNT_DSC);
            mockDsc.approve(address(mockDscEngine), debtToCover);
            // Act
            int256 updatedWethPrice = 18e8; // 1 ETH = $18
            MockV3Aggregator(wethUsdPriceFeed).updateAnswer(updatedWethPrice);
            // Act/Assert
            vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImprovedByLiquidation.selector);
            mockDscEngine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }
    function testCantLiquidateGoodHealthFactor() public {
        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);
        vm.startPrank(LIQUIDATOR);       
            ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
            dscEngine.depositCollateralAndMintDsc(weth, collateralToCover, AMOUNT_DSC);
            // console.log("user health factor", dscEngine.getHealthFactor(USER));
            // 115792089237316195423570985008687907853269984665640564039457584007913129639935 => OK
            dsc.approve(address(dscEngine), AMOUNT_DSC);
            vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
            dscEngine.liquidate( weth, USER , AMOUNT_DSC);

        vm.stopPrank();
    }

    modifier liquidated(){
        vm.startPrank(USER);
            ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
            dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountDscToMint);
        vm.stopPrank();
        int256 updatedWethPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(updatedWethPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        collateralToCover = 20 ether; // HF Should be 1.8 with price change as shown below
        //console.log("expected HF liquidator",dscEngine.calculateHealthFactor(amountDscToMint, dscEngine.getUsdValue(weth, (collateralToCover))));
        // 1 800000000000000000 or 1.8 HF
        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);

        vm.startPrank(LIQUIDATOR);
            ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
            dscEngine.depositCollateralAndMintDsc(weth, collateralToCover, amountDscToMint);
            dsc.approve(address(dscEngine),amountDscToMint);
            dscEngine.liquidate(weth, USER, amountDscToMint);
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        // Bonus collateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION => ( 5555555555555555555 * 10) / 1e18 = 55.555555555555557 or 55.56e15
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        // console.log("Liquidator Weth bal", liquidatorWethBalance);
        // 6.111111111111111110
        uint256 expectedWeth = (dscEngine.getTokenAmountFromUsd(weth, amountDscToMint)) + (dscEngine.getTokenAmountFromUsd(weth, amountDscToMint) / dscEngine.getLiquidationBonusMultiple());
        // console.log("expectedWeth ",expectedWeth);
        // Liquidator should have the ETH quivalent of the amount liquidated plus the liquidation percentage of that ETH equivalent or weth value of DSC paid / 10 which is the bonus
        assertEq(liquidatorWethBalance, expectedWeth);
    }
    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        uint256 amountLiquidated = (dscEngine.getTokenAmountFromUsd(weth, amountDscToMint)) + (dscEngine.getTokenAmountFromUsd(weth, amountDscToMint) / dscEngine.getLiquidationBonusMultiple());
        uint256 usdAmountLiquidated = dscEngine.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL) - usdAmountLiquidated;
        (, uint256 actualUserCollateralValInUsd)  = dscEngine.getAccountInformation(USER);

        assertEq(expectedUserCollateralValueInUsd, actualUserCollateralValInUsd);
    }
    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(LIQUIDATOR);
        assertEq(totalDscMinted, amountDscToMint);
    }
    function testUserHasNoMoreDebt() public liquidated {
        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
    }

    /////////////////////////
    // HealthFactor Tests //
    ////////////////////////
    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        // set expected health factor based on 
        // AMOUNT_COLLATERAL = 10 weth
        // AMOUNT_DSC = 1000 DSC
        // HealthFactor = 10 000000000000000000
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(AMOUNT_DSC, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL));
        uint256 actualHealthFactor = dscEngine.getHealthFactor(USER);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }
    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        //set new ETH price
        // update price feed with new price
        //MockV3Aggregator(wethUsdPriceFeed).updateAnswer(/*NewEthPrice in e8 */);
        // calculate health factor with new weth price
        // assert healthFactor is equal to what it should be at new price
        int256 newEthPrice = 18e8; // 1 ETH = $18
        // Need $200 worth of ETH if we have $100 of DSC debt
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(newEthPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        // should match this USD Value: priceWithDecimals = (uint256(price) * 1e18) / (10 ** decimals);  
        // (priceWithDecimals * amount) / PRECISION;
        //    ((18e8 * 1e18) / 1e8 ) * 10 ) / 1e18 
        //  1.8e27 / 1e8 * 10 / 1e18
        // 1.8e20 / 1e18 = $180 = USD Value
        // HF: (collateralValueInUsd * LIQUIDATION_THRESHOLD * 1e18) / (LIQUIDATION_PRECISION * totalDscMinted)
        // 180 * 50 * 1e18  / 100 * 1000 000000000000000000
        // 9e21 / 1e23 = .09
        assertEq(userHealthFactor, .09 ether);
        console.log("user HF", userHealthFactor);
    }

    ////////////////////////
    // Helperconfig Tests //
    ////////////////////////

    function testHelperConfigGetSepoliaHasRightWethPrice() public {
        vm.chainId(11155111);
        HelperConfig sepHelper = new HelperConfig();
/*         (dsc, dscEngine, helperConfig) = dscDeployer.run(); */
        HelperConfig.NetworkConfig memory activeNetworkConfig = sepHelper.getSepoliaEthConfig();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,/*deployerKEy */) = sepHelper.activeNetworkConfig(); 
        address expectedWethPriceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        address expectedWbtcUsdPriceFeed= 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
        address expectedWeth= 0xdd13E55209Fd76AfE204dBda4007C227904f0a81;
        address expectedWbtc = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        assertEq(expectedWethPriceFeed, activeNetworkConfig.wethUsdPriceFeed);
        assertEq(expectedWbtcUsdPriceFeed, wbtcUsdPriceFeed);
        assertEq(expectedWeth, weth);
        assertEq(expectedWbtc, wbtc);
        assertEq(sepHelper.ETH_USD_PRICE(), 2000e8);
    }

    function testHelperConfigGetAnvilHasRightDeployKey() public {
        vm.chainId(2);
        HelperConfig anvilHelper = new HelperConfig();
        HelperConfig.NetworkConfig memory activeNetworkConfig = anvilHelper.getOrCreateAnvilEthConfig(); 
        uint256 expectedDeployerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        assertEq(expectedDeployerKey, activeNetworkConfig.deployerKey);
    }
    ////////////////////
    // Getters Tests //
    ///////////////////
    /* 
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This makes it so that you have to be 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // This translates to a 10% bonus because it gets divided by LIQUIDATION_PRECISION
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; */
    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        assertEq(minHealthFactor, 1e18);
    }

    function testGetLiquidationBonusMultiple() public view {
        uint256 liquidationBonus = dscEngine.getLiquidationBonusMultiple();
        assertEq(liquidationBonus, 10);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = dscEngine.getLiquidationThreshold();
        assertEq(liquidationThreshold, 50);
    }

    function testGetTotalDscMinted() public depositedCollateralAndMintedDsc {
        uint256 expectedTotalMintedDsc = dsc.totalSupply();
        uint256 totalMintedDsc = dscEngine.getTotalDscMinted();
        assertEq(expectedTotalMintedDsc, totalMintedDsc);
    }

    function testGetCollateralTokens() public view {
        address[2] memory expectedCollateralTokensArray = [address(weth),address(wbtc)];
        address[] memory collateralTokensArray = dscEngine.getCollateralTokens();
        assertEq(keccak256(abi.encodePacked(collateralTokensArray)),keccak256(abi.encodePacked(expectedCollateralTokensArray)));
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 userCollateralBalance = dscEngine.getCollateralBalanceOfUser(USER,weth) ;
        uint256 expectedBalance = ERC20Mock(weth).balanceOf(address(dscEngine));
        //Check the contract's total weth balance because with the modifier the only user with collateral should be USER
        assertEq(userCollateralBalance, expectedBalance);
    }

    function testGetCollateralTokenPriceFeed() public view {
        address collateralTokenPF = dscEngine.getCollateralTokenPriceFeed(weth);
        address expectedPF = address(wethUsdPriceFeed);
        assertEq(collateralTokenPF, expectedPF);
    }

    function testGetDsc() public view {
        address dscAddress = dscEngine.getDsc();
        assertEq(dscAddress, address(dsc));
    }
}