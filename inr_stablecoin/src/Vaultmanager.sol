
pragma solidity 0.8.24;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./Bharat.sol";
import "./Twaporacle.sol";
import "./interfaces/ILiquidationEngine.sol";

//solhint-disable not-rely-on-time
//solhint-disable reason-string


contract Vaultmanager is Bharat,ReentrancyGuard {
    using SafeERC20 for IERC20;
    AggregatorV3Interface public pricefeed ;
    //constants
    uint256 public constant MIN_COLLATERISATION_RATIO=150_000;
    uint256 public constant PRECISION_BPS=100_000;
    uint256 public constant LIQUIDATION_THRESHOLD=130_000;
    uint256 public constant MIN_COLLATERAL=0.001 ether;
    uint256 public constant SECONDS_IN_YEARS=31_536_000;
    uint256 public constant LIQUIDATION_PENALTY=5_000; //5%
   
     //variables
    uint256 public STABILITY_FEE;
    uint256 public vaultID;
    mapping (uint256=>address) public ownerOf;
    mapping (uint256=>Vault) public vaults;

    struct Vault{
        uint256 collateral_amount;
        uint256 debt_amount;
        uint256 lastaccruedtime;
        bool seized;
    }
    //events
    event VaultOpened(uint256 indexed vaultId, address indexed owner);
    event CollateralDeposited(uint256 indexed vaultId, uint256 amount);
    event CollateralWithdrawn(uint256 indexed vaultId, uint256 amount);

    event Borrowed(uint256 indexed vaultId, uint256 amount);
    event Repaid(uint256 indexed vaultId, uint256 amount);

    event Liquidated(uint256 indexed vaultId);
    event VaultClosed(uint256 indexed vaultId);

     constructor(
        address _priceFeed,
        string memory _contractMetadataURI
    )
        Bharat(address(this), _contractMetadataURI)   // call Bharat's constructor
    {
        pricefeed = AggregatorV3Interface(_priceFeed);
        STABILITY_FEE=500; //5% annual

    }


    function openVault() external returns (uint256 vaultID){
           // vaultID++;
            Vault storage vaultuser=vaults[vaultID];
            vaultuser.collateral_amount=0;
            vaultuser.debt_amount=0;
            vaultuser.lastaccruedtime=block.timestamp;
            vaultuser.seized=false;

            ownerOf[vaultID]=msg.sender;


            emit VaultOpened(vaultID, msg.sender); 
            vaultID++;
            return vaultID;
    }
    function depositEth(uint256 vaultID) external payable{
        Vault storage vaultuser=vaults[vaultID];
        require(ownerOf[vaultID]==msg.sender,"Not the owner of vault");
        require(msg.value>0,"Deposit amount should be greater than zero");
        vaultuser.collateral_amount+=msg.value;
        emit CollateralDeposited(vaultID, msg.value);
        //check debt and collateralization ratio
        
    }
    function borrow(uint256 vaultID,uint256 amount) external nonReentrant(){
        Vault storage vaultuser=vaults[vaultID];
        require(
        (ownerOf[vaultID] == msg.sender) && (ownerOf[vaultID] != address(0)),
        "Not the owner of vault"
        );
        require(amount>0,"Borrow amount should be greater than zero");
        //update debt amount with stability fee
        uint256 timepassed=block.timestamp - vaultuser.lastaccruedtime;
        uint256 interest=(vaultuser.debt_amount*STABILITY_FEE*timepassed)/(PRECISION_BPS*SECONDS_IN_YEARS);
        vaultuser.debt_amount+=interest;
        vaultuser.lastaccruedtime=block.timestamp;
        vaultuser.debt_amount+=amount;
        //check collateralization ratio
        uint256 ethTWAPprice=getEthprice();
        uint256 collateralprice=(vaultuser.collateral_amount*ethTWAPprice)/1e8;
        uint256 currentcollateralratio=(collateralprice*PRECISION_BPS)/vaultuser.debt_amount;
        require(currentcollateralratio>=MIN_COLLATERISATION_RATIO,"Undercollateralized vault");
        //mint stablecoin
        this.mint(msg.sender,amount);
        emit Borrowed(vaultID, amount);
    }

    function getEthprice() internal view returns (uint256) {
         (, int256 price, , , ) = pricefeed.latestRoundData();
         require(price>0,"eth price Invalid");
         return uint256(price);
    }

    function repay(uint256 vaultID,uint256 amount) external nonReentrant{
        Vault storage vaultuser=vaults[vaultID];
        require(
        (ownerOf[vaultID] == msg.sender) && (ownerOf[vaultID] != address(0)),
        "Not the owner of vault"
        );
        require(amount>0,"Repay amount should be greater than zero");
        //update debt amount with stability fee
        uint256 timepassed=block.timestamp - vaultuser.lastaccruedtime;
        uint256 interest=(vaultuser.debt_amount*STABILITY_FEE*timepassed)/(PRECISION_BPS*SECONDS_IN_YEARS);
        vaultuser.debt_amount+=interest;
        vaultuser.lastaccruedtime=block.timestamp;
        require(vaultuser.debt_amount>=amount,"Repay amount exceeds debt");
        vaultuser.debt_amount-=amount;
        //burn stablecoin
        this.burn(msg.sender,amount);
        emit Repaid(vaultID, amount);
        
    }

    function liquidate(uint256 vaultid) external nonReentrant{
        //liquidation logic
        Vault storage vaultuser=vaults[vaultid];
        uint256 timepassed=block.timestamp - vaultuser.lastaccruedtime;
        uint256 interest=(vaultuser.debt_amount*(STABILITY_FEE)*timepassed)/(PRECISION_BPS*SECONDS_IN_YEARS);
        vaultuser.debt_amount+=interest;
        uint256 penalty_fee= (vaultuser.debt_amount*LIQUIDATION_PENALTY)/PRECISION_BPS; 
        vaultuser.debt_amount+=penalty_fee;
        vaultuser.lastaccruedtime=block.timestamp;
        uint256 ethTWAPprice=getEthprice();
        uint256 collateralprice=(vaultuser.collateral_amount*ethTWAPprice)/1e8;
        uint256 currentcollateralratio=(collateralprice*PRECISION_BPS)/vaultuser.debt_amount;
        require(currentcollateralratio<LIQUIDATION_THRESHOLD,"Vault is not eligible for liquidation");
        // write liquidation logic now !!
        
        

    }
    receive external payable {
        // Accept ETH deposits
    }






    
    
}



