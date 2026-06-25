// Role

// Mint / burn only

// No logic, no fees

// mint(address to, uint256 amount)
// burn(address from, uint256 amount)


// Invariant

// Only VaultManager can mint/burn
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IBharat.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Bharat is ERC20,AccessControl,IBharat{
    address public vaultManager;
    using SafeERC20 for ERC20;
    string public contractMetadataURI;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory _contractMetadataURI) ERC20("Bharat", "BHR") {
        require(msg.sender != address(0), "Owner address cannot be zero");
        contractMetadataURI=_contractMetadataURI;
        _grantRole(DEFAULT_ADMIN_ROLE,msg.sender);
        //should be checked if needed or not, as the vaultManager will be set after deployment
        _grantRole(MINTER_ROLE, msg.sender); // Grant the deployer the MINTER_ROLE
        
    }
  
    function setVaultManager(address _vaultManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(vaultManager == address(0), "Already initialized");
        require(_vaultManager != address(0), "VaultManager address cannot be zero");
        vaultManager = _vaultManager;
        _grantRole(MINTER_ROLE, _vaultManager);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }
    ///@notice optional metadata enhancement to store coin metadata 
     function contractURI() external view returns (string memory) {
        return contractMetadataURI;
    }

}
