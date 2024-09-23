// SPDX-License-Identifier: MIT
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

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Xander Nesta
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 US Dollar peg.
 * This stablecoin has the following properties:
 * - Collateral: Exogenous
 * - Minting: Algorithmic
 * - Relative Stability: Anchored to US Dollar, Algorithmically
 *
 * our DSC system should always be "overcollateralized". At no point, should the value of ALL collateral <= the value $ backed value of all DSC.
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed only by WETH and WBTC.
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    ////////////
    // Errors //
    ////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__MustBeAllowedToken();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__DuplicateCollateralAddressInConstructor();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__BurnFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImprovedByLiquidation();
    error DSCEngine__TokenAddressZeroNotAllowed();

    ///////////
    // Types //
    ///////////
    using OracleLib for AggregatorV3Interface;

    /////////////////////
    // State Variables //
    /////////////////////
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This makes it so that you have to be 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // This translates to a 10% bonus because it gets divided by LIQUIDATION_PRECISION
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    DecentralizedStableCoin private immutable i_dsc;
    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountOfDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    ////////////
    // Events //
    ////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed addressRedeemedFrom, address indexed addressRedeemedTo, address indexed token, uint256 amount);
    event CollateralLiquidated(address indexed addressLiquidatedFrom, address indexed addressLiquidator, address indexed token, uint256 amount, uint256 liquidationBonus);
    event DscMinted(address indexed user, uint256 amount);
    event DscBurned(address indexed user, uint256 amount);

    ///////////////
    // Modifiers //
    ///////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0) || tokenAddress == address(0)) {
            revert DSCEngine__MustBeAllowedToken();
        }
        _;
    }

    ///////////////////
    // All Functions //
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (s_priceFeeds[tokenAddresses[i]] != address(0)) {
                revert DSCEngine__DuplicateCollateralAddressInConstructor();
            }
            if (tokenAddresses[i] == address(0) || priceFeedAddresses[i] == address(0)) {
                revert DSCEngine__TokenAddressZeroNotAllowed();
            }
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////
    /**
     * @notice This function will deposit your collateral and mint DSC in one transaction
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountOfCollateral The amount of collateral to deposit
     * @param amountOfDscToMint The amount of decentralized stablecoin to mint
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountOfCollateral, uint256 amountOfDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountOfCollateral);
        mintDsc(amountOfDscToMint);
    }
    /**
     * @notice follows CEI - Checks, Effects, Interactions
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountOfCollateral The amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountOfCollateral)
        public
        moreThanZero(amountOfCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountOfCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountOfCollateral);
        bool succcess = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountOfCollateral);
        if (!succcess) {
            revert DSCEngine__TransferFailed();
        }
    }
    /**
     * This function burns DSC and redeems underlying collateral in one transaction.
     * @param tokenCollateralAddress The address of the collateral token to redeem.
     * @param amountOfCollateral The amount of collateral to redeem.
     * @param amountOfDscToBurn The amount of DSC to burn.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountOfCollateral, uint256 amountOfDscToBurn) external    
        moreThanZero(amountOfCollateral)
        isAllowedToken(tokenCollateralAddress){
        burnDsc(amountOfDscToBurn);
        redeemCollateral(tokenCollateralAddress,amountOfCollateral);
        // redeemCollateral check health factor so we don't need to include it here
    }
    function redeemCollateral(address tokenCollateralAddress, uint256 amountOfCollateral) public moreThanZero(amountOfCollateral) {
        // DRY: Don't Repeat Yourself
        // CEI: Checks, Effects, Interactions
            _redeemCollateral(tokenCollateralAddress, amountOfCollateral, msg.sender, msg.sender);
            _revertIfHealthFactorIsBroken(msg.sender);
    }
    /**
     * @notice follows CEI - Checks, Effects, Interactions
     * @param amountOfDscToMint The amount of decentralized stablecoin to mint
     * @notice callers must have more collateral value than the minimum threshold
     */

    function mintDsc(uint256 amountOfDscToMint) public moreThanZero(amountOfDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountOfDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountOfDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        } else {
            emit DscMinted(msg.sender, amountOfDscToMint);
        }
    }

    function burnDsc(uint256 amountOfDscToBurn) public moreThanZero(amountOfDscToBurn) {
        _burnDsc(amountOfDscToBurn, msg.sender, msg.sender);
        // _revertIfHealthFactorIsBroken(msg.sender); // Don't think this is ever hit since in theory burning debt should increase health
        // removed the line above because it prevents a user with debt from partially burning their DSC to partially lessen their debt during liquidation
    }
    // If a position starts nearing undercollateralization we need someone to liquidate that position in order to sustain the health of the system
    // This needs to occur before health ratio reaches 1 or else DSC will not still be worth $1
    // lets says:
    // $100 Eth backing $50 DSC -> healthy ratio of 2 or 200% which is our Collateral threshold but
    // $75 Eth back $50 DSC -> no longer healthy ratio of 1.5 or only 150% because if price of ETH keeps dropping to maybe $40 or worse we wont be at 1:1 anymore
    // Since Collateral Value is below 200% now we will incentivize others to liquidate by offering them the locked collateral at a discount
    /**
     * @param tokenCollateral The erc20 collateral token address to liquidate from the user
     * @param user The user who's position is being liquidated because of broken health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC msg.sender want's to burn to restore user's _healthFactor
     * @notice a user can be only partially liquidated.
     * @notice Caller will get a liquidation bonus for taking the user's funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for it to work.
     * @notice a known bug would be if the protocol were at 100% or less collateralized then we wouldn't be able to incentivize liquidations
     * follows CEI: CHecks, Effects, Interactions
     */
    function liquidate(address tokenCollateral, address user, uint256 debtToCover) external 
        moreThanZero(debtToCover)
        nonReentrant
    {
        // Checks
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();        
        }
        // We want to burn the "bad" DSC debt
        // And take the locked collateral
        // Bad Debt: $140 ETH, $100 DSC
        // debtToCover = 100 DSC
        // $100 DSC == ?? Eth?
        // should get back something like 0.05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateral, debtToCover);
        // To incentivize we then give liquidator 10% bonus
        // So the liquidator should get $110 worth of WETH for $100 DSC
        // We should also add a feature to liquidate in the event that the protocol is insolvent, positions are less than MIN_HEALTH_FACTOR
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(tokenCollateral, totalCollateralToRedeem, user, msg.sender);
        // need to burn the debt from the msg.sender, user will get to keep their DSC but will lose collateral
        _burnDsc(debtToCover,user,msg.sender);
        // need to check that health factor is restored
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor){
            revert DSCEngine__HealthFactorNotImprovedByLiquidation();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
        emit CollateralLiquidated(user, msg.sender, tokenCollateral, totalCollateralToRedeem, bonusCollateral);
    }
    function getHealthFactor(address user) external view returns (uint256){
        return _healthFactor(user);
    }

    ///////////////////////////////////////
    // Private & Internal VIEW Functions //
    ///////////////////////////////////////
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }
    /**
     * Returns how close to liquidation a user is.
     * If a user's health factor goes below 1, then they are at risk of liquidation.
     */

    function _healthFactor(address user) private view returns (uint256) {
        // Need the user's:
        // Total DSC minted
        // Total collateral VALUE
        // Ratio of the two and check to make sure ratio is above liquidation threshold
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // Tests were panicing because of possible divide by zero so need to do an additional check to make sure healthFactor wasn't dividing by zero
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }
    // 1. check health factor (do they have enough collateral?)
    // 2. Revert if they don't
     function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
/*         uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // 19999800000000000000000 * 50  / 100
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted; */
        // copied below line from audit
        return (collateralValueInUsd * LIQUIDATION_THRESHOLD * 1e18) / (LIQUIDATION_PRECISION * totalDscMinted);
        // 360000000000000000000 * 50 * 1e18  /  1e18 * 100 000000000000000000
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
    /**
     * @dev low-level internal function, do not call unless the function calling it is checking for health factor being broken
     * @param tokenCollateralAddress token address of collateral being redeemed
     * @param amountOfCollateral amount of the collateral token to redeem
     * @param from the user address of where the collateral being redeemed is coming from
     * @param to the user address of where the collateral being redeemed is going to
     */
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountOfCollateral, address from, address to) internal {
        // created so that users other than msg.sender can redeem collateral
        s_collateralDeposited[from][tokenCollateralAddress] -= amountOfCollateral;
        emit CollateralRedeemed(to, from, tokenCollateralAddress, amountOfCollateral);
        bool succcess = IERC20(tokenCollateralAddress).transfer(to, amountOfCollateral);
        if (!succcess) {
            revert DSCEngine__TransferFailed();
        }
    }
    /**
     * @dev low-level internal function, do not call unless the function calling it is checking for health factor being broken
     * @param amountOfDscToBurn amount of the DSC token to be burnt
     * @param onBehalfOf the user address of who's DSC will be deducted from our s_dscMinted mapping
     * @param dscFrom the user address of where the DSC will be transferred from 
    */
    function _burnDsc(uint256 amountOfDscToBurn, address onBehalfOf, address dscFrom) public moreThanZero(amountOfDscToBurn) {
        s_dscMinted[onBehalfOf] -= amountOfDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountOfDscToBurn);
        // Conditional hypothetically unreachable due to tranfserFrom's own revert?
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountOfDscToBurn);
        emit DscBurned(dscFrom, amountOfDscToBurn);
    }
    //////////////////////////////////////
    // Public & External VIEW Functions //
    //////////////////////////////////////
    function getTokenAmountFromUsd(address tokenCollateral, uint256 usdAmountInWei) public view 
    isAllowedToken(tokenCollateral) 
    returns (uint256) {
/*         if(tokenCollateral == address(0)){
            revert DSCEngine__MustBeAllowedToken();
        } */
        // Need to get price of Eth (token) from pricefeed
        //  $$/ETH we have $$, need to get the ETH 
        // so if it's $2000 / ETH and we have $1000 we can do 1000/2000 = .5 ETH
        // For this function we can take the usdAmountInWei / Eth Price to get amount of Eth from USD
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateral]);
        (,int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // Found this recommendation in the Audit, need to get the decimals to factor in correct USD price for an collateral used
        uint8 decimals = priceFeed.decimals();
        uint256 priceWithDecimals = (uint256(price) * 1e18) / (10 ** decimals); // if decimals is 8 then this is the same as saying 1e8
        // Using the priceWithDecimals eliminates the need to have the ADDITION_PRECISION variable of 1e8 (where we assumed before all pricefeeds with 8 decimals)
        // and lets us not assume by using the pricefeed's actual number of decimals
        uint256 amountFromUsd = (usdAmountInWei * PRECISION) / priceWithDecimals;
        return amountFromUsd;
    }
    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount the user has deposited, map it to the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view isAllowedToken(token) returns (uint256) {
        /* if(token == address(0)){
            revert DSCEngine__MustBeAllowedToken();
        } */
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // Don't want to assume all price feeds are 8 decimals even though Weth / USD is so we grab number of decimals and include in our calculation
        uint8 decimals = priceFeed.decimals();
        uint256 priceWithDecimals = (uint256(price) * 1e18) / (10 ** decimals);
        return (priceWithDecimals * amount) / PRECISION;
    }
    function getAccountInformation(address user) public view returns(uint256 totalDscMinted, uint256 collateralValueInUsd){
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) public pure returns(uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getMinHealthFactor() public pure returns(uint256){
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationBonusMultiple() external pure returns(uint256){
        return LIQUIDATION_BONUS;
    }

    function getLiquidationThreshold() external pure returns(uint256){
        return LIQUIDATION_THRESHOLD;
    }

    function getTotalDscMinted() external view returns(uint256) {
        return i_dsc.totalSupply();
    }

    function getCollateralTokens() external view returns(address[] memory){
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns(uint256){
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(address token) external view returns(address){
        return s_priceFeeds[token];
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }
}
