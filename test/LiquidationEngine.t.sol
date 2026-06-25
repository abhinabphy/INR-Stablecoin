// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import "forge-std/Test.sol";
import "../src/LiquidationEngine.sol";
import "../src/Vaultmanager.sol";
import "../src/Bharat.sol";
import "../src/Mocks/MockOracle.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Base.t.sol";

contract LiquidationEngineTest is Base {
    using SafeERC20 for IERC20;
    // LiquidationEngine public liquidationEngine;
    // Vaultmanager public vaultManager;
    // Bharat public bharatToken;
    // MockOracle public priceFeed;

    function setUp() public override {
        super.setUp(); // This runs the deployment logic in TestBase
    }

    // address public _owner = ;
    // address public _user = address(0x456);
    // address _pool=makeAddr("pool");

    // function setUp() public {
    //     vm.startPrank(owner);
    //     priceFeed = new MockOracle();
    //     bharatToken = new Bharat("https://example.com/metadata.json");

    //     vaultManager=new Vaultmanager(address(priceFeed), address(bharatToken), address(0x0));
    //     liquidationEngine = new LiquidationEngine(address(vaultManager), address(bharatToken),uint256(5000),uint256(100000),address(pool));
    //     vaultManager.setLiquidationEngine(address(liquidationEngine));
    //     bharatToken.setVaultManager(address(vaultManager));
    //     vm.stopPrank();

    // }

    function testDeposit() public {
        vm.startPrank(user);
        priceFeed.setPrice(3000 * 10 ** 8); // Set price to $200
        uint256 vaultId = vaultManager.openVault();
        uint256 collateralAmount = 1 ether; // 1 ETH
        uint256 debtAmount = 1000 * 10 ** 18; // 100 Bharat tokens

        // Approve and deposit collateral
        vm.deal(user, collateralAmount);
        vaultManager.depositEth{value: collateralAmount}(vaultId);
        // Borrow Bharat tokens
        vaultManager.borrow(vaultId, debtAmount);

        // Check vault state
        (uint256 collateral, uint256 debt,,) = vaultManager.vaults(vaultId);
        assertEq(collateral, collateralAmount);
        assertEq(debt, debtAmount);
        console.log("Vault ID:", vaultId);
        console.log("Collateral Amount:", collateral);
        assertEq(collateral, collateralAmount);
        assertEq(bharatToken.balanceOf(user), debtAmount);

        vm.stopPrank();
    }

    function testLiquidation() public {
        vm.deal(user, 10 ether);

        uint256 vaultId = setupVaultwithPrice(user, 1 * 10 ** 18, 1000 * 10 ** 18, 3000 * 10 ** 8); // Collateral: 1 ETH, Debt: 1000 Bharat tokens, Price: $3000
        // Set price to trigger liquidation
        vm.startPrank(owner);
        priceFeed.setPrice(1000 * 10 ** 8); // Set price to $1000

        // Perform liquidation
        uint256 auctionId = vaultManager.liquidate(vaultId);

        // Check vault state after liquidation
        (uint256 collateral, uint256 debt,,) = vaultManager.vaults(vaultId);
        assertEq(collateral, 0, "Collateral should be seized");
        assertEq(debt, 0, "Debt should be cleared");
        //assertTrue(vaultManager.ownerOf(vaultId) == address(0), "Vault should be closed");

        vm.deal(AuctionBuyer, 10 ether);
        bharatToken.mint(AuctionBuyer, 100000000000 * 10 ** 18); // Mint Bharat tokens to AuctionBuyer
        vm.stopPrank();

        //AuctionBuyer buys collateral from the auction pool
        vm.startPrank(AuctionBuyer);
        IERC20(bharatToken).approve(address(liquidationEngine), type(uint256).max);
        liquidationEngine.buyCollateral(auctionId, 1.0 ether, type(uint256).max); // Buying 1 ETH collateral at max price of 3000 Bharat tokens
        vm.stopPrank();

        //get the auction state after the purchase
        (uint256 collateralRemaining, int256 debtToCover, uint256 currentPrice, bool settlementstatus) =
            liquidationEngine.getAuction(auctionId);
    }

    function testExample() public {
        assertTrue(true);
    }
}
