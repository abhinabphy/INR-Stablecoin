// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILiquidationEngine {
    
    // ==========================================
    //                  EVENTS
    // ==========================================
    
    event AuctionStarted(
        uint256 indexed auctionId, 
        uint256 indexed vaultID, 
        uint256 collateralAmount, 
        uint256 debtAmount
    );
    
    event Purchased(
        uint256 indexed auctionId, 
        address indexed buyer, 
        uint256 collateralBought, 
        uint256 cost
    );
    
    event RefundCredited(
        address indexed user, 
        address indexed paymentToken, 
        uint256 amount
    );
    
    event AuctionEnded(uint256 indexed auctionId);
    
    event Withdrawn(
        address indexed to, 
        address indexed token, 
        uint256 amount
    );

    // ==========================================
    //            EXTERNAL FUNCTIONS
    // ==========================================

    function startAuction(
        uint256 vaultId, 
        uint256 collateralETH, 
        uint256 debtToCoverForAuction, 
        address vaultOwner
    ) external payable returns (uint256 auctionId);

    function buyCollateral(
        uint256 auctionId, 
        uint256 collateralAmount, 
        uint256 maxAcceptablePrice
    ) external payable;

    function purchasePrice(
        uint256 collateralAmount,
        uint256 _lastAuctionStartTime,
        uint256 _decayConstant,
        uint256 initialPrice
    ) external view returns (uint256);

    function getAuction(uint256 auctionId)
        external
        view
        returns (
            uint256 collateralRemaining, 
            int256 debtRemaining, 
            uint256 startTime, 
            bool isSettled
        );

    function getExpectedCost(uint256 auctionId, uint256 amountToBuy) external view returns (uint256);

    // ==========================================
    //            ADMIN FUNCTIONS
    // ==========================================

    function pause() external;

    function unpause() external;
}