pragma solidity ^0.8.24;

import "./interfaces/ILiquidationEngine.sol";
import "./interfaces/IVaultmanager.sol";
import "./interfaces/ITwaporacle.sol";
import"./interfaces/IBharat.sol";
import "./interfaces/ISurplusPool.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SD59x18 ,sd,convert} from "@prb-math/SD59x18.sol";


contract LiquidationEngine is ILiquidationEngine, ReentrancyGuard, Pausable, Ownable {
   using {sd} for int256;
   using SafeERC20 for IBharat;
   
     /// -----------------------------
    /// ---- Pricing Parameters -----
    /// -----------------------------
   ///@notice parameter that controls initial price, stored as a 59x18 fixed precision number
    struct Auction{
        ///@notice unique identifier for the auction
        uint256 id;
        ///@notice the vault ID associated with the auction
        uint256 vaultId;
        ///@notice the address of the collateral asset
        address asset;
        ///@notice the collateral remaining in the auction, denominated in the smallest unit of the collateral asset
        uint256 collateralRemaining;
        ///@notice the debt remaining in the auction, denominated in the smallest unit of the stablecoin
        int256 debtToCover;
        ///@notice the time when the auction started, as a unix timestamp
        uint256 lastAuctionStartTime;
        ///@notice the initial price of the collateral in terms of the stablecoin, stored as a 59x18 fixed point number
        uint256 initialPrice;
        ///@notice if the auction has been settled
        bool settled;
        ///@notice the address of the beneficiary who will receive the proceeds from the auction( typically the owner of the vault being liquidated)
        address beneficiary;
    }
  
    ///set the decay constant and emission rate for the auction pricing model
    uint256 internal decayConstant; // scaled 1e18
    uint256 internal emissionRate; // tokens-per-second scaled 1e18
    uint256 internal constant SECONDS_IN_A_YEAR = 31_536_000; // 365 days
    uint256 internal AuctionCount;
    IVaultmanager public vaultManager;
    IBharat public bharatToken;
    ISurplusPool public surplusPool;
    uint256 AuctionIdCounter;

    mapping (uint256 => Auction) public auctions;
    event AuctionStarted(uint256 indexed auctionId, address indexed asset, uint256 assetAmount, address paymentToken);
    event Purchased(uint256 indexed auctionId, address indexed buyer, uint256 collateralBought, uint256 cost);
    event RefundCredited(address indexed user, address indexed paymentToken, uint256 amount);
    event AuctionEnded(uint256 indexed auctionId);
    event Withdrawn(address indexed to, address indexed token, uint256 amount);
    //@notice parameter that controls the rate of price decay, stored as a 59x18
    constructor(address _vaultManager,address _bharatToken, uint256 _decayConstant, uint256 _emissionRate,address surpluspool) 
    Ownable(msg.sender) {
        vaultManager = IVaultmanager(_vaultManager);
        decayConstant = _decayConstant;
        emissionRate = _emissionRate;
        bharatToken = IBharat(_bharatToken);
        surplusPool = ISurplusPool(surpluspool);
    }
    //modifiers
    modifier onlyVaultManager() {
        require(msg.sender == address(vaultManager), "Caller is not the VaultManager");
        _;
    }
      function startAuction(
        uint256 vaultId,
        uint256 collateralETH,
        uint256 debtToCoverForAuction,
        address vaultOwner
    ) external payable whenNotPaused() nonReentrant onlyVaultManager {
     require (vaultOwner != address(0), "Invalid vault owner");
    
      ///calculate fairinitialPrice using the TWAP oracle price at the time of liquidation
      uint256 price_of_eth = vaultManager.getEthPrice();

      AuctionIdCounter++;
      Auction storage auction = auctions[AuctionIdCounter];
        
        auction.id =AuctionIdCounter;
        auction.vaultId = vaultId;
        auction.asset = address(0); // Assuming ETH as collateral
        auction.collateralRemaining = collateralETH;
        auction.debtToCover = int256(debtToCoverForAuction);
        auction.lastAuctionStartTime = block.timestamp;    
        auction.settled = false;
        auction.beneficiary = vaultOwner;
        auction.initialPrice = price_of_eth*1e10; // Set the floor price based on the TWAP oracle price
        emit AuctionStarted(vaultId, address(0), collateralETH, address(bharatToken));

    }
    ///@notice allows a user to buy collateral from an active auction by paying the current price in Bharat stablecoins
    ///@param auctionId The ID of the auction from which to buy collateral
    ///@param collateralAmount The amount of collateral the user wants to buy (in wei)
    ///@param maxAcceptablePrice The maximum price the user is willing to pay for the collateral (in Bharat stablecoins)
    function buyCollateral(
        uint256 auctionId,
        uint256 collateralAmount,
        uint256 maxAcceptablePrice
    ) external payable whenNotPaused() nonReentrant{

       Auction storage auction =auctions[auctionId];
         //CHECKS
         require(!auction.settled, "Auction already settled");
        require(collateralAmount<= uint256(type(int256).max),"Value doesn't fit in int256");
         require(collateralAmount > 0, 
         "Stable amount must be greater than zero");
         require(auction.collateralRemaining>= collateralAmount, "Not enough collateral remaining");
         //use SD59x18 to calculate the current price of the collateral based on the auction parameters
         SD59x18 quantityFixed=int256(collateralAmount).sd();
         int256 timeElapsed = int256(block.timestamp - auction.lastAuctionStartTime);
         SD59x18 timeElapsedFixed = convert(timeElapsed);
         SD59x18 decayFixed = int256(decayConstant).sd();
         SD59x18 emissionRateFixed = int256(emissionRate).sd();
         SD59x18 initialPriceFixed = int256(auction.initialPrice).sd();
        uint256 currentPrice = purchasePrice(quantityFixed,timeElapsedFixed,decayFixed,initialPriceFixed,emissionRateFixed);
        require(currentPrice <= maxAcceptablePrice, "Current price exceeds max acceptable price");
        //require allowed payment is sent with the transaction
        IBharat(bharatToken).safeTransferFrom(msg.sender, address(this), currentPrice);

        // EFFECTS: update auction state BEFORE transferring collateral
        // compute seconds-of-emissions purchased = quantity / emissionRate (all in 59.18)
        SD59x18 secondsOfEmissionsPurchased = quantityFixed.div(emissionRateFixed);
        // compute new lastAuctionStartTime = lastAuctionStartTime + secondsOfEmissionsPurchased
        auction.lastAuctionStartTime += secondsOfEmissionsPurchased.intoUint256();
        auction.collateralRemaining -= collateralAmount;
        auction.debtToCover-=int256(currentPrice);
        //transfer the collateral to the buyer
        (bool success, ) = msg.sender.call{value: collateralAmount}("");
        require(success, "Transfer failed.");
        emit Purchased(auctionId, msg.sender, collateralAmount, currentPrice);
        //if the debtToCover is non positive, mark the auction as settled and transfer any remaining collateral to the beneficiary
        if(auction.debtToCover <= 0){
            settleAuction(auctionId);
        }
        emit AuctionEnded(auctionId);      
    }
    ///@notice calculates the current purchase price of the collateral based on the auction parameters 
    ///and the time elapsed since the auction started
    /// Compute GDA price per ContinuousGDA formula:
    /// totalCost = (initialPrice / decay) * (exp(decay * quantity / emissionRate) - 1) / exp(decay * timeSinceLast)
    /// All operations in 59.18 fixed point.
    function purchasePrice(SD59x18 _quantityFixed,SD59x18 _timeElapsedFixed,SD59x18 _decayFixed,SD59x18 initialPrice,SD59x18 emissionRateFixed) internal view returns (uint256){
       SD59x18 expDecayQuantity = ((_decayFixed.mul(_quantityFixed)).div(emissionRateFixed)).exp();
         SD59x18 expDecayTime = (_decayFixed.mul(_timeElapsedFixed)).exp();
          SD59x18 numerator = initialPrice.div(_decayFixed).mul(expDecayQuantity.sub(sd(1)));
          SD59x18 totalCost = numerator.div(expDecayTime);
          return totalCost.intoUint256();

    }


    function settleAuction(uint256 auctionId) internal {
        Auction storage auction = auctions[auctionId];
        require(!auction.settled, "Auction already settled");
        require(auction.debtToCover <= 0, "Auction not yet completed");
        auction.settled = true;
        address recipient = auction.beneficiary;
        //transfer any remaining collateral to the owner of the vault and also send the negative debt to the vaultowner
        if(auction.collateralRemaining > 0){
            uint256 remainingCollateral = auction.collateralRemaining;
             auction.collateralRemaining = 0;
            (bool success, ) = recipient.call{value: remainingCollateral}("");
            require(success, "Transfer failed.");
           
        }
        if(auction.debtToCover < 0){
            uint256 negativeDebt = uint256(-auction.debtToCover);
             auction.collateralRemaining = 0;
            bharatToken.safeTransfer(recipient, negativeDebt); 
        }
        auction.settled = true;
        emit AuctionEnded(auctionId);
    }
    //Helper Functions
    /// @notice Returns the core state of the auction
    function getAuction(uint256 auctionId)
        external
        view
        returns (
            uint256 collateralRemaining,
            int256 debtRemaining,
            uint256 startTime,
            bool isSettled
        )
    {
        Auction storage auction = auctions[auctionId];
        return (
            auction.collateralRemaining, 
            auction.debtToCover, 
            auction.lastAuctionStartTime,
            auction.settled
        );
    }

    /// @notice Calculates the exact cost to buy a specific amount of collateral right now
    /// @param auctionId The ID of the auction
    /// @param amountToBuy The amount of collateral the user wants to purchase (in wei)
    /// @return The cost in Bharat stablecoins
    function getExpectedCost(uint256 auctionId, uint256 amountToBuy) external view returns (uint256) {
        Auction storage auction = auctions[auctionId];
        require(!auction.settled, "Auction settled");
        require(auction.lastAuctionStartTime > 0, "Auction does not exist");
        require(amountToBuy > 0 && amountToBuy <= auction.collateralRemaining, "Invalid amount");

        // Use the exact same math setup as buyCollateral
        SD59x18 quantityFixed = int256(amountToBuy).sd();
        int256 timeElapsed = int256(block.timestamp - auction.lastAuctionStartTime);
        SD59x18 timeElapsedFixed = convert(timeElapsed); 
        SD59x18 decayFixed = int256(decayConstant).sd();
        SD59x18 emissionRateFixed = int256(emissionRate).sd();
        SD59x18 initialPriceFixed = int256(auction.initialPrice).sd();

        return purchasePrice(quantityFixed, timeElapsedFixed, decayFixed, initialPriceFixed, emissionRateFixed);
    }
    // ==========================================
    //            ADMIN FUNCTIONS
    // ==========================================

    /// @notice Pauses all auction actions in case of a vulnerability or emergency
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract to resume normal operations
    function unpause() external onlyOwner {
        _unpause();
    }
    

    receive() external payable {
        // Accept ETH payments for collateral purchases
    }
}