interface ILiquidationEngine {
    function startAuction(
        uint256 vaultId,
        uint256 collateralETH,
        uint256 debtToCover,
        address vaultOwner
    ) external payable
    returns (uint256 auctionId);

    function buyCollateral(
        uint256 auctionId,
        uint256 collateralAmount,
        uint256 maxAcceptablePrice
    ) external payable;

    function getAuction(uint256 auctionId)
        external
        view
        returns (
            uint256 collateralRemaining,
            int256 debtRemaining,
            uint256 startTime,
            bool isSettled
        );
}
