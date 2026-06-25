// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IVaultmanager
/// @notice Interface for the Vaultmanager contract that manages collateralized debt positions
interface IVaultmanager {
    
    // ==================== Events ====================
    
    /// @notice Emitted when a new vault is opened
    /// @param vaultId The unique identifier of the newly opened vault
    /// @param owner The address of the vault owner
    event VaultOpened(uint256 indexed vaultId, address indexed owner);
    
    /// @notice Emitted when collateral is deposited into a vault
    /// @param vaultId The vault identifier
    /// @param amount The amount of ETH deposited
    event CollateralDeposited(uint256 indexed vaultId, uint256 amount);
    
    /// @notice Emitted when collateral is withdrawn from a vault
    /// @param vaultId The vault identifier
    /// @param amount The amount of ETH withdrawn
    event CollateralWithdrawn(uint256 indexed vaultId, uint256 amount);
    
    /// @notice Emitted when stablecoins are borrowed against collateral
    /// @param vaultId The vault identifier
    /// @param amount The amount of stablecoins borrowed
    event Borrowed(uint256 indexed vaultId, uint256 amount);
    
    /// @notice Emitted when borrowed stablecoins are repaid
    /// @param vaultId The vault identifier
    /// @param amount The amount of stablecoins repaid
    event Repaid(uint256 indexed vaultId, uint256 amount);
    
    /// @notice Emitted when a vault is liquidated
    /// @param vaultId The vault identifier
    event Liquidated(uint256 indexed vaultId);
    
    /// @notice Emitted when a vault is closed
    /// @param vaultId The vault identifier
    event VaultClosed(uint256 indexed vaultId);
    
    // ==================== Constants ====================
    
    /// @notice Minimum collateralization ratio (in basis points)
    /// @return The minimum collateral to debt ratio required
    function MIN_COLLATERISATION_RATIO() external view returns (uint256);
    
    /// @notice Precision for basis point calculations
    /// @return 100,000 (100%)
    function PRECISION_BPS() external view returns (uint256);
    
    /// @notice Liquidation threshold ratio (in basis points)
    /// @return The collateral to debt ratio below which liquidation is allowed
    function LIQUIDATION_THRESHOLD() external view returns (uint256);
    

    
    /// @notice Seconds in a year (for interest calculations)
    /// @return 31,536,000 seconds
    function SECONDS_IN_YEARS() external view returns (uint256);
    
    /// @notice Liquidation penalty percentage (in basis points)
    /// @return 5,000 (5%)
    function LIQUIDATION_PENALTY() external view returns (uint256);
    
    // ==================== State Variables ====================
    
    /// @notice The stability fee applied annually (in basis points)
    function STABILITY_FEE() external view returns (uint256);
    
    /// @notice Current vault ID counter
    function vaultID() external view returns (uint256);
    
    /// @notice Mapping of vault ID to owner address
    /// @param vaultId The vault identifier
    /// @return The address of the vault owner
    function ownerOf(uint256 vaultId) external view returns (address);
    
    // ==================== Vault Operations ====================
    
    /// @notice Opens a new vault for the caller
    /// @return id The ID of the newly opened vault
    function openVault() external returns (uint256 id);
    
    /// @notice Deposits ETH collateral into a vault
    /// @param id The vault identifier
    /// @dev Caller must be the vault owner
    function depositEth(uint256 id) external payable;
    
    /// @notice Borrows stablecoins against vault collateral
    /// @param id The vault identifier
    /// @param amount The amount of stablecoins to borrow
    /// @dev Vault must maintain minimum collateralization ratio after borrow
    /// @dev Caller must be the vault owner
    function borrow(uint256 id, uint256 amount) external;
    
    /// @notice Repays borrowed stablecoins
    /// @param id The vault identifier
    /// @param amount The amount of stablecoins to repay
    /// @dev Caller must be the vault owner
    /// @dev Includes accrued stability fees in the repayment
    function repay(uint256 id, uint256 amount) external;
    
    /// @notice Liquidates an undercollateralized vault
    /// @param vaultid The vault identifier to liquidate
    /// @dev Vault must be below liquidation threshold
    /// @dev Applies liquidation penalty to the debt
    function liquidate(uint256 vaultid) external returns (uint256 auctionId);
    function getEthPrice() external view returns (uint256);

}
