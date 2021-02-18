pragma solidity 0.6.3;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";


contract ArtAuction is ERC721 {
    
    using SafeMath for uint256;  //For Future use

    //Note: Token is minted after it is sold or after auction ends
  
    //variables that remain static or constant
    mapping(uint256 => ArtItem) private _artItems;  //Map id to ArtItem
    // TODO: why is owner address public?
    address public owner; //contract owner
  
    //variables that are dynamic or change
    //TODO: why are these ID markers public?
    uint256 public _tokenIds;  //unique id used to mint tokens for arts at close/cancel of auction
    uint256 public _artItemIds; //unique id of all arts up for sale (tokenized + untokenized)
    
    //map tokenid to fundsByBidder
    //artItemId => bidder => totalBidFunds
    mapping(uint256 => mapping(address => uint256)) public fundsByBidder;
    mapping(uint256 => Bidding) public bids;  //mapping tokenid to bidding
    bool auctionstarted = false;  //to check if auction started
    bool firsttime = false;  //to mart first successfull 
    
    // bool public canceled; REPLACED
    enum AuctionStates {BEFORE_OPENED, OPENED, CLOSED}    

    //Events
    event LogBid(address bidder, uint bid, address highestBidder, uint highestBid, uint highestBindingBid);   
    event LogWithdrawal(address withdrawer, address withdrawalAccount, uint amount);
    event LogCanceled();
    event ItemAdded(address indexed seller, uint256 indexed artId);

    //Art Item 
    struct ArtItem {
        address payable seller; // address of seller
        uint256 minBid; // minimum selling price by artist
        string tokenURI;  // IPFS URL of art
        bool exists;
        uint bidIncrement; // each bid iteration increments by this value
        bool isBid; // to mark first successful bid 
        AuctionStates currentAuctionState; // when added, default is AuctionStates.BEFORE_OPENED
        uint created; // timestamp
        uint auctionDuration; //art is available for auction until duration elapses
    }
    
    struct Bidding{
        //TODO: change highestBindingBid to "totalStakedFunds"
        uint highestBindingBid; //highestBindingBid of the tokenid
        address payable highestBidder;     
    }

    constructor() ERC721("DART", "ART")  //Initializing ERC721 
    {   
        owner=msg.sender;        
    }
  
   //modifiers
    modifier artItemExists(uint256 id) {   //check if item exists
        require(_artItems[id].exists, "Not Found");
        _;
    }

    modifier isSeller(uint256 id){
        ArtItem memory artItem = _artItems[id];   
        if (msg.sender != artItem.seller) revert();
         _;
    }
    
    modifier isNotSeller(uint256 id) {// check if art seller is calling
        ArtItem memory artItem = _artItems[id];
        if (msg.sender == artItem.seller) revert();
        _;
    }

    modifier sufficientFundsForBid(uint256 id)
    {
        ArtItem memory artItem = _artItems[id];
        if(msg.value < artItem.minBid) revert();
        _;
    }

    modifier auctionNotClosed(uint256 id){ // ensure that auction is not cancelled/closed
        ArtItem memory artItem = _artItems[id];
        if (artItem.currentAuctionState == AuctionStates.CLOSED) revert();
        _;
    }

    modifier auctionIsOpened(uint256 id){ // ensure that auction is opened
        ArtItem memory artItem = _artItems[id];
        require(artItem.currentAuctionState == AuctionStates.OPENED, "aution is not opened");
        _;
    }

    modifier auctionIsClosed(uint256 id){ // ensure that auction is closed
        ArtItem memory artItem = _artItems[id];
        require(artItem.currentAuctionState == AuctionStates.CLOSED, "aution is not closed");
        _;
    }
    
    modifier isSellerOrTimeOut(uint256 id){
        ArtItem memory artItem = _artItems[id];   
        require(msg.sender == artItem.seller || block.timestamp > artItem.created + artItem.auctionDuration, "caller is not item seller and auction duration not expired");
         _;
    }

    // seller can add art item for aunction
    function addArtItem(uint256 price, string memory tokenURI, uint _bidIncrement) public {
        require(price >= 0, "Price cannot be lesss than 0");
        
        _artItemIds++;
        _artItems[_artItemIds] = ArtItem(payable(address(msg.sender)), price, tokenURI, true, _bidIncrement, false, AuctionStates.BEFORE_OPENED, block.timestamp, 1 days);
        emit ItemAdded(msg.sender, _artItemIds);
    }

    //get art item info
    function getArtItem(uint256 id) 
        public
        view
        artItemExists(id)
        returns (uint256, uint256, string memory, uint256)
    {
        ArtItem memory artItem = _artItems[id];
        Bidding memory bid = bids[id]; 
        return (id, artItem.minBid, artItem.tokenURI, bid.highestBindingBid);
    }
    
    
    
    //auction functions : 
    
    // seller (auction's owner) manually close the auction
    // auto-close when aution duration is elapsed
    // the highest bidder gets art    
    function cancelAuction(uint256 id) 
        public 
        payable 
        isSellerOrTimeOut(id)
        auctionIsOpened(id)
        // auctionNotClosed(id)        
        returns (bool success)
    {
        ArtItem storage artItem = _artItems[id];   
        Bidding storage bid = bids[id]; 
        // canceled = true;
        artItem.currentAuctionState = AuctionStates.CLOSED;
        
        //mint art token for seller, not just msg.sender
        _tokenIds++; 
        _safeMint(artItem.seller, _tokenIds);
        _setTokenURI(_tokenIds, artItem.tokenURI);
        
        // the item seller (auction's owner) should be allowed to withdraw the highestBindingBid        
        if (bid.highestBindingBid == 0) revert();
        fundsByBidder[id][bid.highestBidder] -= bid.highestBindingBid;

        // send the funds
        if (!payable(address(msg.sender)).send(bid.highestBindingBid)) revert();
        
        LogCanceled();
        return true;
    }
   
    // buyers can place bids immediately the item has been added until auction is CLOSED
    // the first bid changes item's auction state from BEFORE_OPENED to OPENED    
    function placeBid(uint256 id) 
        public
        payable
        auctionNotClosed(id)
        isNotSeller(id)
        sufficientFundsForBid(id)
        returns (bool success)
    {
        // reject payments of 0 ETH
        require(msg.value > 0, "no amount was sent");
        
        // calculate the user's total bid
        // based on the accumulated amount they've sent to the contract and fresh funds
        // plus whatever has been sent with this transaction
        Bidding storage bid = bids[id]; 
        // auctionstarted = true;
        ArtItem storage artItem = _artItems[id];  
        // open auction as first bidder
        if(artItem.currentAuctionState == AuctionStates.BEFORE_OPENED){
            artItem.currentAuctionState = AuctionStates.OPENED;
        }
        
        uint newBid = fundsByBidder[id][msg.sender] + msg.value;
        
        
        // if the user isn't even willing to overbid the highest binding bid, there's nothing for us
        // to do except revert the transaction.
        // if (newBid <= bid.highestBindingBid) revert();
        require(newBid > bid.highestBindingBid, "bidder must overbid the highest binding bid");
        
        // grab the previous highest bid (before updating fundsByBidder, in case msg.sender is already the
        // highestBidder and is just increasing their maximum bid).
        uint highestBid = fundsByBidder[id][bid.highestBidder];
        
        fundsByBidder[id][msg.sender] = newBid;
        
        if (newBid <= highestBid) {
            // if the user has overbid the highestBindingBid but not the highestBid, we simply
            // increase the highestBindingBid and leave highestBidder alone.
        
            // note that this case is impossible if msg.sender == highestBidder because you can never
            // bid less ETH than you already have.

            if(newBid + artItem.bidIncrement > highestBid)
            {
                bid.highestBindingBid = highestBid;
            } else {
                bid.highestBindingBid = newBid + artItem.bidIncrement;
            }
        } else {
            // if msg.sender is already the highest bidder, they must simply be wanting to raise
            // their maximum bid, in which case we shouldn't increase the highestBindingBid.
        
            // if the user is NOT highestBidder, and has overbid highestBid completely, we set them
            // as the new highestBidder and recalculate highestBindingBid.
        
            if (msg.sender != bid.highestBidder) {
                bid.highestBidder = payable(address(msg.sender));
                
                if(newBid + artItem.bidIncrement > highestBid){
                    if(artItem.isBid == false){
                        bid.highestBindingBid = highestBid;
                    }
                    else{
                        bid.highestBindingBid = artItem.minBid + artItem.bidIncrement;
                        artItem.isBid = true;
                    }
                }
                else
                {
                    bid.highestBindingBid = newBid + artItem.bidIncrement;
                }
            }
            highestBid = newBid;
        }
        
        LogBid(msg.sender, newBid, bid.highestBidder, highestBid, bid.highestBindingBid);
        return true;
    }
    
    function withdraw(uint256 id) 
        public
        payable
        isNotSeller(id)
        auctionIsClosed(id)
        returns (bool success)
    {   
        // require(canceled==true);
        // require(auctionstarted==true);
        address payable withdrawalAccount;
        uint withdrawalAmount;
        Bidding memory bid = bids[id]; 
        
        if (msg.sender == bid.highestBidder) {
            // the highest bidder should only be allowed to withdraw the difference between their
            // highest bid and the highestBindingBid
            withdrawalAccount = bid.highestBidder;
            withdrawalAmount = fundsByBidder[id][bid.highestBidder];
        }
        else {
            // anyone who participated but did not win the auction should be allowed to withdraw
            // the full amount of their funds
            withdrawalAccount = payable(address(msg.sender));
            withdrawalAmount = fundsByBidder[id][withdrawalAccount];
        }
        
        require(withdrawalAmount > 0, "no fund to withdraw");
        
        fundsByBidder[id][withdrawalAccount] -= withdrawalAmount;
        
        // send the funds
        if (!payable(address(msg.sender)).send(withdrawalAmount)) revert();
        
        LogWithdrawal(msg.sender, withdrawalAccount, withdrawalAmount);
        
        return true;
    }    
}