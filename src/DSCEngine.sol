// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin
// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions​
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
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/*
 * @title DSCEngine
 * @author Rufus Adejumo
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard, Pausable {
    /////////////////
    //   Errors   //
    //////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__HealthFactorOk();

    ///////////////
    //   Types  //
    ////////////////
    using OracleLib for AggregatorV3Interface;

    /////////////////
    //State Variables//
    ///////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
     uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means a 10% bonus
    // Fee and Treasury variables
    uint256 public constant MINT_FEE = 5; // 0.5% fee (assuming 1000 = 100%), change to constant
    uint256 public constant FEE_DENOMINATOR = 1000;
    address public immutable treasury; // Change to immutable

    mapping(address token => address priceFeed) s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    // Mapping for token-specific collateral ratios (basis points, where 100 = 1%)
    mapping(address token => uint256 ratio) public s_collateralRatios;
    // Caching for gas optimization
    mapping(address user => uint256 value) public s_cachedCollateralValue;
    mapping(address user => uint256 timestamp) public s_lastUpdateTimestamp;

    // Default ratio for tokens without a custom ratio (200% = 200 basis points? Wait, let's be precise)
    // Let's use: 150 = 150% (1.5x), 170 = 170% (1.7x), 200 = 200% (2x)
    uint256 public constant RATIO_DENOMINATOR = 100;
    address[] private s_collateralTokens;
    uint256 public constant CACHE_DURATION = 1 hours; // Recalculate after 1 hour

    DecentralizedStableCoin private immutable I_DSC;

    /////////////////
    //   Events    //
    //////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /////////////////
    //   Modifiers   //
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /////////////////
    //   Functions   //
    ///////////////////
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        uint256[] memory collateralRatios, // NEW: Add this line
        address dscAddress,
        address _treasury
    ) {
        // Check treasury first - fail early
        require(_treasury != address(0), "Treasury cannot be zero address");

        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length || tokenAddresses.length != collateralRatios.length) {
            // UPDATED: Add ratio check
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        // For example ETH / USD, BTC / USD, MKR / USD, etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
            // NEW: Store the ratio for this token
            s_collateralRatios[tokenAddresses[i]] = collateralRatios[i];
        }
        treasury = _treasury;
        I_DSC = DecentralizedStableCoin(dscAddress);
    }

    /////////////////
    //  External Functions//
    ///////////////////
    /*
    * @param tokenCollateralAddress: the address of the token to deposit as collateral
    * @param amountCollateral: The amount of collateral to deposit
    * @param amountDscToMint: The amount of DecentralizedStableCoin to mint
    * @notice: This function will deposit your collateral and mint DSC in one transaction
    */
    function depositColaterallAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external whenNotPaused {
        // Add it here
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDSCToMint);
    }

    /*
     * @notice follows CEI
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
        whenNotPaused
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        // Invalidate cache
        s_lastUpdateTimestamp[msg.sender] = 0;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
    * @param tokenCollateralAddress: the collateral address to redeem
    * @param amountCollateral: amount of collateral to redeem
    * @param amountDscToBurn: amount of DSC to burn
    * This function burns DSC and redeems underlying collateral in one transaction
    */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checked health factor
    }

    // in order to redeem collateral:
    // 1. health factor must be over 1 AFTER collateral is pulled
    // DRY: Don't repeat yourself
    // CEI: Check, Effect, Interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
        whenNotPaused
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);

        // Invalidate cache
        s_lastUpdateTimestamp[msg.sender] = 0;

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    *@notice follows CEI
    * @param amountDscToMint: The amount of DSC you want to mint
    * You can only mint DSC if you have  enough collateral more than the minimum threshhold
    */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant whenNotPaused {
        // Calculate fee
        uint256 fee = (amountDscToMint * MINT_FEE) / FEE_DENOMINATOR;
        uint256 amountAfterFee = amountDscToMint - fee;

        s_DSCMinted[msg.sender] += amountAfterFee;

        _revertIfHealthFactorIsBroken(msg.sender);

        // Mint fee to treasury first
        if (fee > 0 && treasury != address(0)) {
            bool feeMinted = I_DSC.mint(treasury, fee);
            if (!feeMinted) revert DSCEngine__MintFailed();
        }

        // Mint remaining to user
        bool minted = I_DSC.mint(msg.sender, amountAfterFee);
        if (!minted) revert DSCEngine__MintFailed();
    }

    // Threshold to let's say 150%
    // $100 ETH Collateral -> $74
    // $50 DSC
    // UNDERCOLLATERALIZED!!!

    // I'll pay back the $50 DSC -> Get all your collateral

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think that this is necessary
    }

    /*
    * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
    * This is collateral that you're going to take from the user who is insolvent.
    * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
    * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
    * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
    *
    * @notice: You can partially liquidate a user.
    * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
    * For example, if the price of the collateral plummeted before anyone could be liquidated.
    */

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
        whenNotPaused // Add this line

    {
        // need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // We want to burn their DSC "debt"
        // And take their collateral
        // Bad User: $140 ETH, $100 DSC
        // debtToCover = $100
        // $100 of DSC == ??? ETH?
        // 0.05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amount into treasury
        // 0.05 * 0.1 = 0.005. Getting 0.005
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralRedeemed, user, msg.sender);
        // We need to burn DSC
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    /////////////////////////////////////
    // Private & Internal View Functions //
    //////////////////////////////////////
    /*
     *@ dev low-level internal function. Only call provided health faxtor is checked.
    */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = I_DSC.transferFrom(dscFrom, address(this), amountDscToBurn);
        // ondition hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        I_DSC.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        // Invalidate cache for both users
        s_lastUpdateTimestamp[from] = 0;
        s_lastUpdateTimestamp[to] = 0;

        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user) 
        private 
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user); // This is fine now
    }

    /*
    * Returns how close to liquidation a user is
    * If a user goes below 1, then they can be liquidated.
    */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDSCMinted == 0) return type(uint256).max; // No debt, infinite health factor

        // Calculate weighted average ratio based on user's deposited collateral
        uint256 weightedRatio = _calculateWeightedRatio(user);

       return (collateralValueInUsd * weightedRatio * PRECISION) / (RATIO_DENOMINATOR * totalDSCMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check health factor if they have enough collateral
        // 2. Revert if they dont.
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateWeightedRatio(address user) private view returns (uint256) {
        uint256 totalValue = getAccountCollateralValue(user);
        if (totalValue == 0) return 0;

        uint256 weightedRatio = 0;

        uint256 length = s_collateralTokens.length;
        for (uint256 i = 0; i < length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0) {
                uint256 tokenValue = getUsdValue(token, amount);
                uint256 tokenRatio = s_collateralRatios[token];
                weightedRatio += (tokenValue * tokenRatio) / totalValue;
            }
        }

        return weightedRatio;
    }

    /////////////////////////////////////
    // Public & External View Functions //
    //////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // casting to 'uint256' is safe because Chainlink prices are always positive
        // forge-lint: disable-next-line(unsafe-typecast)
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
       uint256 length = s_collateralTokens.length;
        for (uint256 i = 0; i < length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0) {
                totalCollateralValueInUsd += getUsdValue(token, amount);
            }        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e8
        // casting to 'uint256' is safe because Chainlink prices are always positive
        // forge-lint: disable-next-line(unsafe-typecast)
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getAccountInformation(address user) public view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        if (user == address(0)) {
            user = msg.sender;
        }
        return _getAccountInformation(user);
    }

    function getDscMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }
}
