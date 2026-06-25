// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/LiquidationEngine.sol";
import "../src/Vaultmanager.sol";
import "../src/Bharat.sol";
import "../src/Mocks/MockOracle.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract Base is Test {
    LiquidationEngine public liquidationEngine;
    Vaultmanager public vaultManager;
    Bharat public bharatToken;
    MockOracle public priceFeed;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address pool = makeAddr("pool");
    //someone buys collateral from auction pool
    address AuctionBuyer = makeAddr("AuctionBuyer");

    function setUp() public virtual {
        vm.startPrank(owner);
        priceFeed = new MockOracle();
        bharatToken = new Bharat("https://example.com/metadata.json");

        vaultManager = new Vaultmanager(address(priceFeed), address(bharatToken), address(0x0));
        liquidationEngine = new LiquidationEngine(
            address(vaultManager), address(bharatToken), uint256(5000), uint256(100000), address(pool)
        );
        vaultManager.setLiquidationEngine(address(liquidationEngine));
        bharatToken.setVaultManager(address(vaultManager));
        vm.stopPrank();
    }

    function setupVaultwithPrice(address _user, uint256 collateralAmount, uint256 debtAmount, uint256 Price)
        public
        returns (uint256 vaultId)
    {
        vm.startPrank(_user);
        priceFeed.setPrice(int256(Price));
        vaultId = vaultManager.openVault();
        vm.deal(_user, collateralAmount);
        vaultManager.depositEth{value: collateralAmount}(vaultId);
        vaultManager.borrow(vaultId, debtAmount);
        vm.stopPrank();
    }
}
