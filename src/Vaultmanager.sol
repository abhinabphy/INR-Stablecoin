// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITwaporacle.sol";

import "./Bharat.sol";
import "./interfaces/ILiquidationEngine.sol";
import "./interfaces/IVaultmanager.sol";

contract Vaultmanager is ReentrancyGuard, IVaultmanager,Ownable {
    ITwaporacle public pricefeed;
    Bharat public bharatToken;
    ILiquidationEngine public liquidationEngine;

    // ------------------- Constants -------------------

    uint256 public constant MIN_COLLATERISATION_RATIO = 150_000; // 150%
    uint256 public constant LIQUIDATION_THRESHOLD = 130_000;     // 130%
    uint256 public constant PRECISION_BPS = 100_000;
    uint256 public constant SECONDS_IN_YEARS = 31_536_000;
    uint256 public constant LIQUIDATION_PENALTY = 5_000;         // 5%

    // ------------------- State -------------------

    uint256 public STABILITY_FEE; // bps APR
    uint256 public vaultID;

    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => Vault) public vaults;
   
   /// @inheritdoc IVaultmanager
    struct Vault {
        uint256 collateral_amount;
        uint256 debt_amount;
        uint256 lastaccruedtime;
        bool seized;
    }

    // ------------------- Constructor -------------------

    constructor(
        address _priceFeed,
        address _bharatToken,
        address _liquidationEngine
    )Ownable(msg.sender) {
        pricefeed = ITwaporacle(_priceFeed);
        bharatToken = Bharat(_bharatToken);
        liquidationEngine = ILiquidationEngine(_liquidationEngine);
        STABILITY_FEE = 500; // 0.5% APR with PRECISION_BPS = 100_000
    }

    // ==================================================
    //                Vault Lifecycle
    // ==================================================

    function openVault() external returns (uint256 id) {
        id = ++vaultID;

        Vault storage v = vaults[id];
        v.collateral_amount = 0;
        v.debt_amount = 0;
        v.lastaccruedtime = block.timestamp;
        v.seized = false;

        ownerOf[id] = msg.sender;

        emit VaultOpened(id, msg.sender);
    }

    // ==================================================
    //                Collateral
    // ==================================================
    /// @inheritdoc IVaultmanager
    function depositEth(uint256 id) external payable {
        require(ownerOf[id] == msg.sender, "Not vault owner");
        require(msg.value > 0, "Zero deposit");

        vaults[id].collateral_amount += msg.value;

        emit CollateralDeposited(id, msg.value);
    }

    // ==================================================
    //                Borrowing
    // ==================================================
    /// @inheritdoc IVaultmanager
    function borrow(uint256 id, uint256 amount) external nonReentrant {
        require(ownerOf[id] == msg.sender, "Not vault owner");
        require(amount > 0, "Zero borrow");

        _accrueInterest(id);

        Vault storage v = vaults[id];
        v.debt_amount += amount;

        uint256 ratio = _collateralRatio(id);
        require(ratio >= MIN_COLLATERISATION_RATIO, "Undercollateralized");

        bharatToken.mint(msg.sender, amount);

        emit Borrowed(id, amount);
    }

    // ==================================================
    //                Repayment
    // ==================================================
    /// @inheritdoc IVaultmanager
    function repay(uint256 id, uint256 amount) external nonReentrant {
        require(ownerOf[id] == msg.sender, "Not vault owner");
        require(amount > 0, "Zero repay");

        _accrueInterest(id);

        Vault storage v = vaults[id];
        require(v.debt_amount >= amount, "Repay exceeds debt");

        v.debt_amount -= amount;
        bharatToken.burn(msg.sender, amount);

        emit Repaid(id, amount);
    }

    // ==================================================
    //                Liquidation
    // ==================================================
    /// @inheritdoc IVaultmanager
    function liquidate(uint256 id) external nonReentrant returns (uint256 auctionId) {
        Vault storage v = vaults[id];

        require(v.debt_amount > 0, "No debt");
        require(!v.seized, "Already seized");

        _accrueInterest(id);

        uint256 ratio = _collateralRatio(id);
        require(ratio < LIQUIDATION_THRESHOLD, "Not liquidatable");

        uint256 collateral = v.collateral_amount;
        uint256 debtWithPenalty = _liquidationDebt(id);

        // Freeze vault
        v.collateral_amount = 0;
        v.debt_amount = 0;
        v.seized = true;

        uint256 auctionId=liquidationEngine.startAuction{ value: collateral }(
            id,
            collateral,
            debtWithPenalty,
            ownerOf[id]
        );

        emit Liquidated(id);
    }

    // ==================================================
    //                Internal Helpers
    // ==================================================

    function _accrueInterest(uint256 id) internal {
        Vault storage v = vaults[id];

        uint256 dt = block.timestamp - v.lastaccruedtime;
        if (dt == 0) return;

        uint256 interest =
            (v.debt_amount * STABILITY_FEE * dt)
            / (PRECISION_BPS * SECONDS_IN_YEARS);

        v.debt_amount += interest;
        v.lastaccruedtime = block.timestamp;
    }

    function _collateralValue(uint256 id) internal view returns (uint256) {
        uint256 ethPrice = _getEthPrice(); // 8 decimals
        return (vaults[id].collateral_amount * ethPrice) / 1e8;
    }

    function _collateralRatio(uint256 id) internal view returns (uint256) {
        Vault storage v = vaults[id];
        if (v.debt_amount == 0) return type(uint256).max;

        uint256 value = _collateralValue(id);
        return (value * PRECISION_BPS) / v.debt_amount;
    }

    function _liquidationDebt(uint256 id) internal view returns (uint256) {
        Vault storage v = vaults[id];

        uint256 penalty =
            (v.debt_amount * LIQUIDATION_PENALTY) / PRECISION_BPS;

        return v.debt_amount + penalty;
    }

    function _getEthPrice() public view returns (uint256) {
        (, int256 price,,,) = pricefeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }
    function getEthPrice() external view returns (uint256) {
    return _getEthPrice();
}
     /// @notice Set the liquidation engine address after deployment
    /// @param _liquidationEngine The address of the LiquidationEngine contract
    function setLiquidationEngine(address _liquidationEngine) external onlyOwner() {
        require(address(liquidationEngine) == address(0), "Already set");
        liquidationEngine = ILiquidationEngine(_liquidationEngine);
    }

    // ==================================================
    //                ETH Receiver
    // ==================================================

    receive() external payable {}
}
