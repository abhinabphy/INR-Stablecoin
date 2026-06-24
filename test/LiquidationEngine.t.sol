// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/LiquidationEngine.sol";
import "../src/Vaultmanager.sol";
import "../src/Bharat.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract LiquidationEngineTest is Test {
    LiquidationEngine public liquidationEngine;
    Vaultmanager public vaultManager;
    Bharat public bharatToken;


    address public owner = address(0x123);
    address public user = address(0x456);


    function setUp() public {
        vaultmanager=new Vaultmanager(address(0x1), address(0x2), address(0x3));
        bharatToken = new Bharat("ipfs://example-metadata-uri");
    }

    function testInitialize() public {
        assertEq(address(liquidationEngine), address(liquidationEngine));
    }

    function testExample() public {
        assertTrue(true);
    }
}