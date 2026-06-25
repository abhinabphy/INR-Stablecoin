// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
// Import standard IERC20

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBharat is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function contractURI() external view returns (string memory);
    function setVaultManager(address _vaultManager) external;
    function vaultManager() external view returns (address);
}
