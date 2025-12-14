interface ILiquidationEngine {
    function startAuction(
        uint256 vaultId,
        uint256 collateralETH,
        uint256 debtToCover,
        address vaultOwner
    ) external payable;
}
