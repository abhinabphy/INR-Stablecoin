// Role

// Mint / burn only

// No logic, no fees

// mint(address to, uint256 amount)
// burn(address from, uint256 amount)


// Invariant

// Only VaultManager can mint/burn
pragma solidity 0.8.24;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Bharat is ERC20 {
    address public vaultManager;
    string public contractMetadataURI;

    constructor(address _vaultManager,string memory _contractMetadataURI) ERC20("Bharat", "BHR") {
        require(_vaultManager != address(0), "VaultManager address cannot be zero");
        vaultManager = _vaultManager;
        contractMetadataURI=_contractMetadataURI;
    }
    ///@notice only vaultmanager can access mint and burn
    modifier onlyVaultManager() {
        require(msg.sender == vaultManager, "Caller is not the VaultManager");
        _;
    }

    function mint(address to, uint256 amount) external onlyVaultManager {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyVaultManager {
        _burn(from, amount);
    }
    ///@notice optional metadata enhancement to store coin metadata 
     function contractURI() external view returns (string memory) {
        return contractMetadataURI;
    }

}
