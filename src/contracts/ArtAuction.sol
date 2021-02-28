pragma solidity ^0.6.3;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/8108f2f9b917616a8cd0661c31a211ad9f988110/contracts/token/ERC721/ERC721.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/8108f2f9b917616a8cd0661c31a211ad9f988110/contracts/math/SafeMath.sol";

contract ArtAuction is ERC721 {
   
    using SafeMath for uint256;  //For Future use


    /*********************************** */
    /****     STATE VARIABLES      ***** */
    /*********************************** */  

    //static and constant state variables
    mapping(uint256 => ArtItem) private _artItems;  //Map id to ArtItem
    address public owner;   // contract owner

    //dynamic and changing state variables
    uint256 public _tokenIds;  // Unique Image ID that are tokenized
    uint256 public _artItemIds; // Unique ID of images for sale but not tokenized    
 
    mapping(uint256=>mapping(address => uint256)) public fundsByBidder; //map _artItemIds to fundsByBidder    
    mapping(int256=>uint256) token; //Map tokenIds to _artItemIds so as to connect to struct.
    mapping(uint256=>bidding) public bid;  //mapping tokenid to bidding
    bool firsttime = false;  //to mart first successfull bid



    /***************************** */
    /*****      EVENTS      ****** */
    /***************************** */  

    event LogBid(address indexed bidder, uint indexed artItemId, uint bid, address indexed highestBidder, uint highestBid, uint highestBindingBid);  
    event LogWithdrawal(uint indexed artItemId, address indexed withdrawer, address indexed withdrawalAccount, uint amount);
    event LogCanceled(uint256 indexed artItemId,address indexed seller,address indexed winner);
    event LogAddItem(uint256 _artItemIds, string name, address payable indexed seller, uint256 price, uint nowTime, uint timePeriod);

  
    /***************************** */
    /*****     STRUCTS      ****** */
    /***************************** */  

    struct ArtItem {
        address payable seller; //address of seller
        uint256 minbid; //minimum price by artist
        string tokenURI;  //IPFS URL
        bool exists;    //token by id exists or not
        uint bidIncrement; //incremention of bid
        uint time;          // art item creation timestamp
        uint timePeriod;    // duration of auction
        bool cancelled;     // checks if auction is closed
        bool auctionstarted;    // checks if aution is open
        string name;        // name of art item
    }
   
    struct bidding{
        uint highestBindingBid; // highestBindingBid of the tokenid(tokenized artId)
        address payable highestBidder; //current highest bidder
    }


    /******************************* */
    /****     CONSTRUCTOR      ***** */
    /******************************* */  
    
    //Note: Token is minted after it is sold or after auction ends
    //Initializing ERC721
    constructor() public ERC721("DART", "ART"){
        owner=msg.sender;
    }


 
    /***************************** */
    /****     MODIFIERS      ***** */
    /***************************** */  
 
    // check if item exists
    modifier artItemExist(uint256 id) {
        require(_artItems[id].exists, "Not Found");
        _;
    }
   
    // ensure caller is art item owner
    modifier onlyNotOwner(uint256 id) {
        ArtItem memory artItem = _artItems[id];  
        if (msg.sender == artItem.seller) revert();
        _;
    }

    modifier onlyOwner(uint256 id)
    {
        ArtItem memory artItem = _artItems[id];  
        if (msg.sender != artItem.seller) revert();
         _;
    }
     
    modifier minbid(uint256 id){
        ArtItem memory artItem = _artItems[id];
        if(msg.value<artItem.minbid) revert();
        _;
    }


    /************************************** */
    /****     ART ITEM FUNCTIONS      ***** */
    /************************************** */  

    function addArtItem(uint256 price, string memory tokenURI, uint _bidincrement, uint timePeriod, string memory name) public {
        require(price >= 0, "Price cannot be lesss than 0");

        _artItemIds++;
        uint nowTime = now;
        _artItems[_artItemIds] = ArtItem(msg.sender, price, tokenURI, true, _bidincrement, nowTime, timePeriod,false,false,name);
        emit LogAddItem(_artItemIds, name, msg.sender, price, nowTime, timePeriod);
    }

       
    //get art item info
    function getArtItem(uint256 id)
        public
        view
        artItemExist(id)
        returns (uint256, uint256, string memory, uint, uint, uint, bool, string memory, address payable)
    {
        ArtItem memory artItem = _artItems[id];
        bidding memory bid = bid[id];
        return (id, artItem.minbid, artItem.tokenURI, bid.highestBindingBid,artItem.time,artItem.timePeriod,artItem.cancelled,artItem.name,artItem.seller);
    }
   



    /************************************** */
    /****     AUCTION FUNCTIONS      ***** */
    /************************************** */  
   
    //Cancel auction
    function cancelAuction(uint256 id) 
        public 
        payable 
        returns (bool success)
    {
        ArtItem storage artItem = _artItems[id];  
        require(artItem.cancelled == false);

        if((artItem.time + (artItem.timePeriod * 1 seconds) < now)){  //mint token if auctionstarted and not expired
            bidding storage bid = bid[id];
            artItem.cancelled = true;
            // the auction's owner should be allowed to withdraw the highestBindingBid
            
            if (bid.highestBindingBid != 0 && artItem.auctionstarted == true){
                _tokenIds++;
                //token[_tokenIds] = _artItemIds;    
                _safeMint(bid.highestBidder, _tokenIds);
                _setTokenURI(_tokenIds, artItem.tokenURI);
                fundsByBidder[id][bid.highestBidder] -= bid.highestBindingBid;

                // send the funds
                (artItem.seller).send(bid.highestBindingBid); 
            }

            LogCanceled(id,artItem.seller,bid.highestBidder);
        }
        return artItem.cancelled;   
    }
   
    function placeBid(uint256 id) 
        public
        payable
        onlyNotOwner(id)
        minbid(id)
        returns (bool success)
    {  
    
        // reject payments of 0 ETH/MATIC
        if (msg.value == 0) revert();
    
        // calculate the user's total bid based on the current amount they've sent to the contract
        // plus whatever has been sent with this transaction
        bidding storage bid = bid[id];
        ArtItem storage artItem = _artItems[id];  
        require((artItem.time + (artItem.timePeriod * 1 seconds) > now));
        require(artItem.cancelled == false);
    
        uint newBid = fundsByBidder[id][msg.sender] + msg.value;

        // if the user isn't even willing to overbid the highest binding bid, there's nothing for us
        // to do except revert the transaction.
        if (newBid <= bid.highestBindingBid) revert();

        // grab the previous highest bid (before updating fundsByBidder, in case msg.sender is the
        // highestBidder and is just increasing their maximum bid).
        uint highestBid = fundsByBidder[id][bid.highestBidder];

        fundsByBidder[id][msg.sender] = newBid;

        if (newBid <= highestBid) {
            // if the user has overbid the highestBindingBid but not the highestBid, we simply
            // increase the highestBindingBid and leave highestBidder alone.

            // note that this case is impossible if msg.sender == highestBidder because you can never
            // bid less ETH than you already have.
            if(newBid + artItem.bidIncrement > highestBid){
                bid.highestBindingBid = highestBid;
            }
            else {
                bid.highestBindingBid = newBid + artItem.bidIncrement;
            }
        } else {
            // if msg.sender is already the highest bidder, they must simply be wanting to raise
            // their maximum bid, in which case we shouldn't increase the highestBindingBid.

            // if the user is NOT highestBidder, and has overbid highestBid completely, we set them
            // as the new highestBidder and recalculate highestBindingBid.

            if (msg.sender != bid.highestBidder) {
                bid.highestBidder = msg.sender;

                if(newBid + artItem.bidIncrement > highestBid){
                    if(firsttime == false){
                        bid.highestBindingBid = highestBid;
                    }
                    else{
                        bid.highestBindingBid = artItem.minbid + artItem.bidIncrement;
                        firsttime=true;
                    }
                }
                else{
                    bid.highestBindingBid = newBid + artItem.bidIncrement;
                }
            }

            highestBid = newBid;
        }

        if(artItem.auctionstarted == false){
            bid.highestBindingBid = msg.value;
        }

        LogBid(msg.sender, id, newBid, bid.highestBidder, highestBid, bid.highestBindingBid);
        artItem.auctionstarted = true;
        return true;
    }
   
    function withdraw(uint256 id) 
        public 
        payable 
        onlyNotOwner(id)
        returns (bool success)
    {  
        require(_artItems[id].cancelled == true);
        require(_artItems[id].auctionstarted == true);
        address payable withdrawalAccount;
        uint withdrawalAmount;
        bidding storage bid = bid[id];
   
        if (msg.sender == bid.highestBidder) {
            // the highest bidder should only be allowed to withdraw the difference between their
            // highest bid and the highestBindingBid
            withdrawalAccount = bid.highestBidder;
            withdrawalAmount = fundsByBidder[id][bid.highestBidder];
        }
        else {
            // anyone who participated but did not win the auction should be allowed to withdraw
            // the full amount of their funds
            withdrawalAccount = msg.sender;
            withdrawalAmount = fundsByBidder[id][withdrawalAccount];
        }

        if (withdrawalAmount == 0) revert();

        fundsByBidder[id][withdrawalAccount] -= withdrawalAmount;

        // send the funds
        if (!msg.sender.send(withdrawalAmount)) revert();

        LogWithdrawal(id, msg.sender, withdrawalAccount, withdrawalAmount);

        return true;
    }
       
}
