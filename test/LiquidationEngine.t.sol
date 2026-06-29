// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import "forge-std/Test.sol";
import "../src/LiquidationEngine.sol";
import "../src/Vaultmanager.sol";
import "../src/Bharat.sol";
import "../src/Mocks/MockOracle.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Base.t.sol";
import {SD59x18, sd, wrap, unwrap, convert} from "@prb-math/SD59x18.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

function toString(SD59x18 value) internal pure returns (string memory) {
    return Strings.toString(uint256(unwrap(value)));
}

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

    // Setup vault: 1 ETH collateral, 1000 Bharat debt, Oracle starts at $3000
    uint256 vaultId = setupVaultwithPrice(user, 1 * 10 ** 18, 1000 * 10 ** 18, 3000 * 10 ** 8); 
    
    // Set oracle price down to $1000 to trigger liquidation
    vm.startPrank(owner);
    priceFeed.setPrice(1000 * 10 ** 8); 

    // Perform liquidation -> triggers startAuction internally
    uint256 auctionId = vaultManager.liquidate(vaultId);
    vm.stopPrank();

    // Verify vault records are cleanly cleared out post-seizure
    (uint256 collateral, uint256 debt,,) = vaultManager.vaults(vaultId);
    assertEq(collateral, 0, "Collateral should be seized");
    assertEq(debt, 0, "Debt should be cleared");

    // Prepare our liquidation buyer
    vm.deal(AuctionBuyer, 10 ether);
    vm.startPrank(owner);
    bharatToken.mint(AuctionBuyer, 100000 * 10 ** 18); 
    vm.stopPrank();

    // Check the price at second zero (t = 0)
    uint256 priceAtStart = liquidationEngine.getExpectedCost(auctionId, 1.0 ether);
    assertEq(priceAtStart, 1000 * 10 ** 18, "Starting price should match the $1000 oracle price");

    // TWEAK: Warp time forward by 10 minutes (600 seconds) to test the linear percentage decay slope
    // Math: 600 seconds * 0.00019e18 (decayConstant) = 0.114e18 (11.4% price drop)
    // Expected Price: 1000 ETH * (1 - 0.114) = 886 ETH
    vm.warp(block.timestamp + 10 minutes);

    uint256 priceAfterDecay = liquidationEngine.getExpectedCost(auctionId, 1.0 ether);
    assertEq(priceAfterDecay, 886 * 10 ** 18, "Price should have linearly decayed by 11.4%");

    // AuctionBuyer buys collateral from the auction pool at the discounted rate
    vm.startPrank(AuctionBuyer);
    IBharat(bharatToken).approve(address(liquidationEngine), type(uint256).max);
    
    liquidationEngine.buyCollateral(auctionId, 1.0 ether, type(uint256).max); 
    vm.stopPrank();

    // FIXED: Corrected return parameters to match your contract signature:
    // (uint256 collateralRemaining, int256 debtRemaining, uint256 startTime, bool isSettled)
    (uint256 collateralRemaining, int256 debtToCover, uint256 auctionStartTime, bool settlementstatus) =
        liquidationEngine.getAuction(auctionId);

    // Verify final structural outcomes
    assertEq(collateralRemaining, 0, "All collateral should be bought");
    assertTrue(settlementstatus, "Auction should be completely marked as settled");
    assertLe(debtToCover, 0, "Remaining auction debt tracker should be zeroed or negative");
}
    function testExample() public {
        assertTrue(true);
    }

    function testAuctionUnits() public pure {
        uint256 ethPrice = 1000e8;

        uint256 initialPrice = ethPrice * 1e10;

        SD59x18 price = wrap(int256(initialPrice));

        SD59x18 quantity = wrap(int256(1 ether));
        // Log the wrapped values as strings
        console.log("Wrapped price (SD59x18):", toString(price));
        console.log("Wrapped quantity (SD59x18):", toString(quantity));

        console.logInt(unwrap(price));
        console.logInt(unwrap(quantity));
    }
    // Helper function to convert SD59x18 to string
    //check
}
