pragma solidity ^0.8.24;

import "./interfaces/ILiquidationEngine.sol";
import "./interfaces/IVaultmanager.sol";
import "./interfaces/ITwaporacle.sol";
import "./interfaces/IBharat.sol";
import "./interfaces/ISurplusPool.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LiquidationEngine is ILiquidationEngine, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IBharat;

    /// -----------------------------
    /// ---- Pricing Parameters -----
    /// -----------------------------
    ///@notice parameter that controls initial price
    struct Auction {
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
        ///@notice the initial price of the collateral in terms of the stablecoin, stored as an 18-decimal fixed point number
        uint256 initialPrice;
        ///@notice if the auction has been settled
        bool settled;
        ///@notice the address of the beneficiary who will receive the proceeds from the auction( typically the owner of the vault being liquidated)
        address beneficiary;
    }

    ///@notice parameter that controls the rate of price decay, stored as a percentage fraction per second scaled to 1e18
    ///@dev e.g., 0.00019e18 means the auction drops by 0.019% of its initial price per second (~100% drop in ~1.46 hours)
    uint256 internal decayConstant = 0.00019e18; // scaled 1e18
    uint256 internal AuctionIdCounter;

    IVaultmanager public vaultManager;
    IBharat public bharatToken;
    ISurplusPool public surplusPool;

    mapping(uint256 => Auction) public auctions;

    event AuctionStarted(
        uint256 indexed auctionId, uint256 indexed vaultID, uint256 collateralAmount, uint256 debtAmount
    );
    event Purchased(uint256 indexed auctionId, address indexed buyer, uint256 collateralBought, uint256 cost);
    event RefundCredited(address indexed user, address indexed paymentToken, uint256 amount);
    event AuctionEnded(uint256 indexed auctionId);
    event Withdrawn(address indexed to, address indexed token, uint256 amount);

    constructor(
        address _vaultManager,
        address _bharatToken,
        uint256 _decayConstant,
        address surpluspool
    ) Ownable(msg.sender) {
        vaultManager = IVaultmanager(_vaultManager);
        decayConstant = _decayConstant;
        bharatToken = IBharat(_bharatToken);
        surplusPool = ISurplusPool(surpluspool);
    }

    //modifiers

    modifier onlyVaultManager() {
        require(msg.sender == address(vaultManager), "Caller is not the VaultManager");
        _;
    }

    function startAuction(uint256 vaultId, uint256 collateralETH, uint256 debtToCoverForAuction, address vaultOwner)
        external
        payable
        whenNotPaused
        nonReentrant
        onlyVaultManager
        returns (uint256 auctionId)
    {
        require(vaultOwner != address(0), "Invalid vault owner");

        ///calculate fairinitialPrice using the TWAP oracle price at the time of liquidation
        uint256 price_of_eth = vaultManager.getEthPrice();

        auctionId = AuctionIdCounter;
        Auction storage auction = auctions[AuctionIdCounter];

        auction.id = auctionId;
        auction.vaultId = vaultId;
        auction.asset = address(0); // Assuming ETH as collateral
        auction.collateralRemaining = collateralETH;
        auction.debtToCover = int256(debtToCoverForAuction);
        auction.lastAuctionStartTime = block.timestamp;
        auction.settled = false;
        auction.beneficiary = vaultOwner;
        auction.initialPrice = price_of_eth * 1e10; // Converts 8-decimal oracle price to standard 18-decimal unit price
        emit AuctionStarted(AuctionIdCounter, vaultId, collateralETH, debtToCoverForAuction);
        AuctionIdCounter++;
        return auctionId;
    }

    ///@notice allows a user to buy collateral from an active auction by paying the current price in Bharat stablecoins
    ///@param auctionId The ID of the auction from which to buy collateral
    ///@param collateralAmount The amount of collateral the user wants to buy (in wei)
    ///@param maxAcceptablePrice The maximum price the user is willing to pay for the collateral (in Bharat stablecoins)
    function buyCollateral(uint256 auctionId, uint256 collateralAmount, uint256 maxAcceptablePrice)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        Auction storage auction = auctions[auctionId];
        //CHECKS
        require(!auction.settled, "Auction already settled");
        require(collateralAmount <= uint256(type(int256).max), "Value doesn't fit in int256");
        require(collateralAmount > 0, "Stable amount must be greater than zero");
        require(auction.collateralRemaining >= collateralAmount, "Not enough collateral remaining");

        uint256 currentPrice = purchasePrice(
            collateralAmount, auction.lastAuctionStartTime, decayConstant, auction.initialPrice
        );
        require(currentPrice <= maxAcceptablePrice, "Current price exceeds max acceptable price");
        //require allowed payment is sent with the transaction
        IBharat(bharatToken).safeTransferFrom(msg.sender, address(this), currentPrice);

        // EFFECTS: update auction state BEFORE transferring collateral
        // Linear lot auctions decay predictably over time; continuous timeline modifications are omitted.
        auction.collateralRemaining -= collateralAmount;
        auction.debtToCover -= int256(currentPrice);
        
        //transfer the collateral to the buyer
        (bool success,) = msg.sender.call{value: collateralAmount}("");
        require(success, "Transfer failed.");
        emit Purchased(auctionId, msg.sender, collateralAmount, currentPrice);
        
        //if the debtToCover is non positive, mark the auction as settled and transfer any remaining collateral to the beneficiary
        if (auction.debtToCover <= 0 || auction.collateralRemaining == 0) {
            settleAuction(auctionId);
        }
    }

    ///@notice calculates the current purchase price of the collateral based on the auction parameters
    ///and the time elapsed since the auction started
    /// Compute Price per Percentage-Based Linear Dutch Auction formula:
    /// dropPercentage = timeElapsed * decayConstant
    /// UnitPrice = max(0, initialPrice - (initialPrice * dropPercentage))
    /// totalCost = (collateralAmount * UnitPrice) / 1e18
    function purchasePrice(
        uint256 collateralAmount,
        uint256 _lastAuctionStartTime,
        uint256 _decayConstant,
        uint256 initialPrice
    ) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - _lastAuctionStartTime;
        
        // Calculate the percentage drop: (timeElapsed * decayConstant)
        uint256 dropPercentage = timeElapsed * _decayConstant;
        
        uint256 currentPricePerUnit;
        if (dropPercentage >= 1e18) {
            currentPricePerUnit = 0; // Fully decayed to floor price
        } else {
            // Linearly scale down the starting initial price by the elapsed percentage fraction
            uint256 priceLoss = (initialPrice * dropPercentage) / 1e18;
            currentPricePerUnit = initialPrice - priceLoss;
        }
        
        // Return total cost based on the exact asset slice requested
        return (collateralAmount * currentPricePerUnit) / 1e18;
    }

    function settleAuction(uint256 auctionId) internal {
        Auction storage auction = auctions[auctionId];
        require(!auction.settled, "Auction already settled");
        require(auction.debtToCover <= 0 || auction.collateralRemaining == 0, "Auction not yet completed");
        auction.settled = true;
        address recipient = auction.beneficiary;
        //transfer any remaining collateral to the owner of the vault and also send the negative debt to the vaultowner
        if (auction.collateralRemaining > 0) {
            uint256 remainingCollateral = auction.collateralRemaining;
            auction.collateralRemaining = 0;
            (bool success,) = recipient.call{value: remainingCollateral}("");
            require(success, "Transfer failed.");
        }
        if (auction.debtToCover < 0) {
            uint256 negativeDebt = uint256(-auction.debtToCover);
            auction.debtToCover = 0;
            bharatToken.safeTransfer(recipient, negativeDebt);
        }
        emit AuctionEnded(auctionId);
    }
    //Helper Functions
    /// @notice Returns the core state of the auction
    function getAuction(uint256 auctionId)
        external
        view
        returns (uint256 collateralRemaining, int256 debtRemaining, uint256 startTime, bool isSettled)
    {
        Auction storage auction = auctions[auctionId];
        return (auction.collateralRemaining, auction.debtToCover, auction.lastAuctionStartTime, auction.settled);
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

        return purchasePrice(
            amountToBuy, auction.lastAuctionStartTime, decayConstant, auction.initialPrice
        );
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