import { MDBAnimation, MDBBtn, MDBCard, MDBCol, MDBContainer, MDBIcon, MDBRow } from 'mdbreact';
import React, { Component } from 'react';
import ArtTable from '../components/ArtTable';
import ArtListItem from '../components/ArtListItem';
import HelperFunctions from '../utils/Util';
import TimeAgo from 'javascript-time-ago';
import Validator from '../utils/validator';
import ArtAlert from '../components/ArtAlert';
import Spinner from '../components/Spinner';
class MarketPlaceBuy extends Component {
    constructor(props){
        super(props);
        this.state = {
            _isMount: false,
            accounts: this.props.baseAppState.accounts,
            contract: this.props.baseAppState.contract,
            priceContract: this.props.baseAppState.priceFeed,
            price: 0,
            bidAmount: 0,
            artHash: [],
            count: 10,
            myBids:[],//contains art items already bidded for
            newBid: null,
            artItems: [],
            latestFetchBlock: 'latest',
            showNewBid: false,
            loading: {
                expiringItems: false,
                items: false,
                placeBidBtn: false,
                withdrawBtn: false,
                fetchArtItems: false
            },
            columns: [
                {
                  label: 'Name',
                  field: 'name',
                  sort: 'asc',
                  width: 150
                },
                {
                  label: 'Owner',
                  field: 'owner',
                  sort: 'asc',
                  width: 270
                },
                {
                  label: 'Price',
                  field: 'price',
                  sort: 'asc',
                  width: 200
                },
                {
                  label: 'Start date',
                  field: 'created',
                  sort: 'asc',
                  width: 250
                },      
                {
                  label: 'Auction Ending',
                  field: 'expiry',
                  sort: 'asc',
                  width: 80
                },
                {
                    label: 'Join Auction',
                    field: 'join',
                    sort: 'asc',
                    width: 120
                }
            ],            
            error: {
                placeBid: '',
                withdrawFunds: ''                
            },
            success: {
                placeBid: '',
                withdrawFunds: ''
            }
        };
        
        this.newBid = this.newBid.bind(this);
        this.placeBid = this.placeBid.bind(this);
        this.handleChange = this.handleChange.bind(this);
        this.selectBid = this.selectBid.bind(this);
        this.onFetchArtItems = this.onFetchArtItems.bind(this);

        this.fetchMyBids();
        this.fetchArtItems();        
    }

    handleChange = (event)=>{
        event.preventDefault();
        let key = event.target.name;
        let value = event.target.value;
        this.setState({[key]: value});
    }

    componentWillUnmount(){
        this.setState({_isMount: false});
        // clearInterval(()=>this.backgroundDataSync());
    }

    componentWillMount= async ()=>{
        const contract = this.state.contract;
        if ( !contract ) {
            let util = new HelperFunctions();
            let response = await util.reloadContractAndAccounts();
            this.setState({ web3: response.web3, accounts: response.accounts, contract: response.contract, priceContract: response.priceFeed });
        }
    }

    componentDidMount(){
        this.setState({_isMount: true});    
        // setInterval(()=>{
        //     if(this.state.contract && this.state.artItems.length < 1){
        //         this.fetchArtItems();
        //         //window.location.href='/marketplace/buy';
        //     }            
        // }, 10000); 
    }

    componentDidUpdate(){
        // setInterval(()=>{
        //     if(!this.state.contract){
        //         window.location.href='/marketplace/buy';
        //     }
        // }, 5000); 
    }

    backgroundDataSync =()=>{ //sync every 20 seconds
        setInterval(()=>{
            const contract = this.state.contract;
            if ( contract.methods ) {
                this.fetchArtItems();
                this.fetchMyBids();
            }
        }, 20000); 
    }

    //button fire up card to input new bid details
    newBid = (itemId, name, price, seller=null) => event =>{
        event.preventDefault();
        this.setState({showNewBid: true});
        this.setState({bidItemId: itemId});
        this.setState({bidItemOwner: seller});
        console.log('itemID clicked', itemId);

        let newBidObj = {name: name, itemId: itemId, currentHighestBid: price};
        this.setState({newBid: newBidObj});
        event.stopPropagation();
    }

    reBid = (itemId, name, price, currentHighestBidder, isCancelled) =>{
        this.setState({showNewBid: true});
        this.setState({bidItemId: itemId});        
        console.log('itemID clicked', itemId);

        let newBidObj = {name: name, itemId: itemId, currentHighestBid: price, currentHighestBidder: currentHighestBidder, isCancelled: isCancelled};
        this.setState({newBid: newBidObj});
    }

    // selects existing bid
    selectBid=(event)=>{
        event.preventDefault();
        let itemId = event.target.value;

        let bidItem  = this.state.myBids.find(item => item.itemId === itemId);

        let name = bidItem.name;
        let currentHighestBid = bidItem.currentHighestBid;
        let currentHighestBidder = bidItem.currentHighestBidder;
        let isCancelled = bidItem.isCancelled;
        console.log('item selected name', name);
        console.log('item selected id', itemId);
        console.log('item selected price',currentHighestBid);
        console.log('item selected isCanclled',currentHighestBid);
        this.reBid(itemId, name, currentHighestBid, currentHighestBidder, isCancelled);
        event.stopPropagation();
    }

    getArtItem = (itemId)=>{
        console.log("get bid method");
        const contract = this.state.contract;
        if(!this.state.accounts) return;
        const account = this.state.accounts[0];    

        return contract.methods.getArtItem(itemId).call({from: account});
    }

    fetchMyBids = () => {
        console.log("fetch my bids method");
        const contract = this.state.contract;
        if(!this.state.accounts) return;
        const account = this.state.accounts[0];        

        // get added items through events emitted
        contract.getPastEvents('LogBid', {
            filter: {bidder: account},  
            fromBlock: 0,
            toBlock: 'latest'
        }, (error, events) => {       
            if (!error){
                console.log('events', events);                
                
                //pick the last user bid for unique items                
                //(address indexed bidder, uint artItemId, uint indexed bid, address indexed highestBidder, uint highestBid, uint highestBindingBid);  
                let myBids = [];
                let myBidsSet = new Set();

                for(let i = events.length - 1; i >= 0; i--){
                    let itemId = events[i].returnValues[1];
                    let currentHighestBid = events[i].returnValues[4];
                    let currentHighestBidder = events[i].returnValues[3];
                    let name = '';
                    let expiry = 0;

                    //if item bid has been saved, skip
                    if(myBidsSet.has(itemId)){
                        continue;
                    }
                    myBidsSet.add(itemId);
                    
                    let response = this.getArtItem(itemId);
                    response.then(result => {
                        console.log('place bid: ', result);
                        if(result){
                            name = result[7];
                            expiry = result[5];
                            let isCancelled = result[6];   
                            console.log('art item fetched');
                            myBids.push({
                                itemId: itemId, 
                                name: name,
                                currentHighestBid: currentHighestBid, 
                                currentHighestBidder: currentHighestBidder, 
                                expiry: expiry,
                                isCancelled: isCancelled
                            });
                        }

                        this.setState({myBids: myBids});

                    }).catch(error=>{
                        console.log('get art item error', error);
                    });                    
                }
            }
            else {
                console.log(error)
            }
        })
    }

    placeBid = event =>{
        event.preventDefault();
        
        const contract = this.state.contract;
        const account = this.state.accounts[0];
        let bidAmount = this.state.bidAmount;
        let itemId = this.state.bidItemId;  
        let itemOwner = this.state.bidItemOwner;
        let currentHighestBid = this.state.newBid.currentHighestBid;
        
        let validator = new Validator();
        
        if(account === itemOwner){
            this.setState(prevState => ({
                error: {
                    ...prevState.error,
                    placeBid: 'Error — You can not bid for your own art'
            }})); 
            return;
        }

        if(!validator.isValidBidAmount(bidAmount, currentHighestBid)){
            this.setState(prevState => ({
                error: {
                    ...prevState.error,
                    placeBid: 'Error — Invalid Bid Amount was placed'
            }})); 
            return;
        }

        if(bidAmount < currentHighestBid){
            this.setState(prevState => ({
                error: {
                    ...prevState.error,
                    placeBid: 'Error — Bid Amount is smaller than current highest bid price'
            }})); 
            return;
        }

        if(isNaN(itemId) || isNaN(bidAmount)){
            console.log("invalid input was detected!");
            return null;
        }

        let response = contract.methods.placeBid(itemId).send({from: account, value: bidAmount});
        
        response.then(result => {
            console.log('place bid: ', result);
            if(result.status && result.events.LogBid){
                this.setState(prevState => ({
                    success: {
                        ...prevState.success,
                        placeBid: 'Success — New Bid was placed successfully!'
                }}));
                this.fetchArtItems();
                this.fetchMyBids();
            }else{
                console.log('place bid contract call error occured')
                this.setState(prevState => ({
                    error: {
                        ...prevState.error,
                        placeBid: 'Error — A minor error occured. Take a look at the log'
                }})); 
            }
        }).catch(error=>{
            console.log('place bid error: ', error);
            this.setState(prevState => ({
                error: {
                    ...prevState.error,
                    placeBid: error.message
            }})); 
        }); 
    }

    resetMessage = () =>{
        let errors = Object.keys(this.state.error);
        for(var propIndex in errors){

            let prop = errors[propIndex];
            console.log(prop);

            this.setState(prevState => ({
                error: {
                    ...prevState.error,
                    [prop]: ''
            }}));
         
        }        
    }

    fetchArtItems = () =>{
        // if(!this.state._isMount) return;
        const timeAgo = new TimeAgo('en-US');
        this.setState(prevState => ({
            loading: {
                ...prevState.loading,
                fetchArtItems: true
        }}));

        console.log("fetch art items method");
        const contract = this.state.contract;
        if(!this.state.contract) return;        

        let count = this.state.count;

        //get last art items added
        contract.getPastEvents('LogAddItem', {
            fromBlock: 0,
            toBlock: this.state.latestFetchBlock
        }, (error, events) => {       
            if (!error){
                // console.log('events', events);                
                
                let oldArtItems = [];
                let util = new HelperFunctions();

                for(let event of events){
                    let itemId = event.returnValues[0];
                    let name = event.returnValues[1];
                    let seller = event.returnValues[2];
                    let price = event.returnValues[3];
                    let created = event.returnValues[4];
                    let expiry = event.returnValues[5];

                    let expiryDate = timeAgo.format(util.GetDateFromUNIXTime(Number(created) + Number(expiry)));
                    // console.log('expiring', expiry);
                    // console.log('created', created);
                    let createdDate = util.GetDateFromUNIXTime(created).toDateString() + ' ' + util.GetDateFromUNIXTime(created).toLocaleTimeString();
                    
                    let isExpired = false;
                    if(new Date() - util.GetDateFromUNIXTime(Number(created) + Number(expiry)) >= 0){
                        isExpired = true;
                    }

                    //check for existing bids on item, and update price with current highest bid on the item
                    //address indexed bidder, uint indexed artItemId, uint bid, address indexed highestBidder, uint highestBid, uint highestBindingBid);  
                    contract.getPastEvents('LogBid', {
                        filter: {artItemId: itemId},  
                        fromBlock: 0,
                        toBlock: 'latest'
                    }, (error, events) => {       
                        if (!error){
                            console.log('events', events); 

                            //pick the last bid on item
                            let lastBid = events[events.length - 1];
                            if(lastBid){
                                let lastBidCurrentHighestBid = lastBid.returnValues[4];
                                if(lastBidCurrentHighestBid){
                                    price = lastBidCurrentHighestBid;
                                }
                            }

                            //check if auction is closed already                            
                            let response = this.getArtItem(itemId);
                            response.then(result =>{
                                console.log('get art - fetch my arts ',result);
                                // if(result){
                                    let isCancelled = result[6];   

                                    let specialStatus = null; 
                                    if(isCancelled){
                                        specialStatus = <MDBBtn className="disabled" color="warning" size="sm">CANCELLED</MDBBtn>;
                                    }else if(isExpired){
                                        specialStatus = <MDBBtn className="disabled" color="danger" size="sm">EXPIRED</MDBBtn>;
                                    }
                                    
                                    //excluse canceled autions
                                    // if(!isCancelled){
                                        oldArtItems.push({
                                            itemId: itemId, 
                                            name: name, 
                                            owner: util.GetMaskedAccount(seller), 
                                            price: new Intl.NumberFormat().format(price), 
                                            created: createdDate, 
                                            expiry: expiryDate,
                                            join: <section>{ specialStatus ?  specialStatus
                                                : <MDBBtn color="success" size="sm" onClick={this.newBid(itemId, name, price, seller)}>JOIN</MDBBtn>}</section>
                                        });
                                        
                                        count--;                    
                                        if(count < 1) {
                                            this.setState({latestFetchBlock: event.blockNumber});
                                            // break; limit fetched items
                                        }
                                        this.setState({latestFetchBlock: event.blockNumber});
                                        this.setState({artItems: oldArtItems});
                                    // }
                                // }
                            }).catch(error=>{
                                console.log('get art item for fetchMyArtItems error', error);
                            });                            
                        }
                    });                    
                }       
                this.setState(prevState => ({
                    loading: {
                        ...prevState.loading,
                        fetchArtItems: false
                }}));                         
            }
            else {
                console.log(error)
            }
        })
    }

    withdrawFunds =(itemId)=>event=>{
        event.preventDefault();
        const contract = this.state.contract;
        const account = this.state.accounts[0];

        let response = contract.methods.withdraw(itemId).send({from: account});
        
        response.then(result => {
            console.log('withdraw bid: ', result);
            if(result.status && result.events.LogWithdrawal){
                let amount = result.events.LogWithdrawal.returnValues[2];
                this.setState(prevState => ({
                    success: {
                        ...prevState.success,
                        withdrawFunds: `Success — All your staked funds (${amount}) have been withdrawn!`
                }}));
                this.fetchArtItems();
                this.fetchMyBids();
            }else{
                console.log('withdraw call error occured')
                this.setState(prevState => ({
                    error: {
                        ...prevState.error,
                        withdrawFunds: 'Error — You do not have any funds staked for this art item.'
                }})); 
            }
        }).catch(error=>{
            console.log('withdraw error: ', error);
            this.setState(prevState => ({
                error: {
                    ...prevState.error,
                    withdrawFunds: error.message
            }})); 
        }); 
    }

    onFetchArtItems =event=>{
        event.preventDefault();
        this.fetchArtItems();
        event.stopPropagation();
    }

    render() {
        let util = new HelperFunctions();
        return (
            <MDBContainer className="page-container">
                <MDBRow>
                    <MDBCol md="9" lg="9" xl="9">
                        <MDBRow>
                            <MDBCard className="p-5 w-100 mr-2">
                                <h1>Buy an Art (NFT)</h1>
                                <MDBCol className="p-2 mt-4">
                                    <MDBAnimation type="">
                                        <section>
                                            <MDBBtn rounded style={{position:'absolute', right:'10px', top:'-45px'}} onClick={this.onFetchArtItems} color="info" >{this.state.loading.fetchArtItems ? <Spinner style={{position: 'relative', left: '-15px'}} size="small"/> : <span>Reload <MDBIcon className="ml-2" icon="sync-alt" /></span> }</MDBBtn>
                                        </section>
                                        <ArtTable rows={this.state.artItems} columns={this.state.columns}/>
                                        
                                    </MDBAnimation>
                                </MDBCol>  
                            </MDBCard>                                                              
                        </MDBRow>
                    </MDBCol>
                    
                    {/* show closing and latest auctions */}
                    <MDBCol md="3" lg="3" xl="3" className="sidebar">
                        {/* AUCTION BIDDING */}
                        <h2>MY BIDS</h2>
                        <hr />
                        <MDBCard className="p-4">
                            <h5>My Current Bids</h5>
                            <select className="browser-default custom-select" onChange={this.selectBid}>
                                <option>-- Select Auction --</option> 
                                {this.state.myBids.length > 0 ?
                                    this.state.myBids.map((bidItem, index)=>{
                                        console.log('mybids', this.state.myBids);
                                        return <option key={index} value={bidItem.itemId}>
                                            {bidItem.name}  ({bidItem.currentHighestBid})
                                         </option>;
                                    })
                                :null}
                            </select>                                    
                        </MDBCard>
                        {this.state.showNewBid && this.state.newBid ?
                            <section className="mt-3">                                
                                <MDBCard className="p-4">
                                    {this.state.error.withdrawFunds ? 
                                        <ArtAlert onCloseCallback={this.resetMessage} type="danger" message={this.state.error.withdrawFunds} />                                        
                                    :null}
                                    {this.state.success.withdrawFunds ? 
                                        <ArtAlert onCloseCallback={this.resetMessage} type="success" message={this.state.success.withdrawFunds} />                                        
                                    :null}   
                                    {this.state.error.placeBid ? 
                                        <ArtAlert onCloseCallback={this.resetMessage} type="danger" message={this.state.error.placeBid} />                                        
                                    :null}
                                    {this.state.success.placeBid ? 
                                        <ArtAlert onCloseCallback={this.resetMessage} type="success" message={this.state.success.placeBid} />                                        
                                    :null}   
                                    <label htmlFor="bidAmount" className="grey-text small text-uppercase">
                                        Art Name
                                    </label>                                    
                                    <input type="text" disabled value={this.state.newBid.name} id="artName" name="artName" className="form-control" />
                                    <label htmlFor="highestBidder" className="grey-text small text-uppercase">
                                        Highest Bidder (Current)
                                    </label>                                    
                                    <input type="text" disabled value={util.GetMaskedAccount(this.state.newBid.currentHighestBidder) ? util.GetMaskedAccount(this.state.newBid.currentHighestBidder) : '-- Not Available --'} id="highestBidder" name="artName" className="form-control" />
                                    <label htmlFor="currentHighestBid" className="grey-text mt-2 small text-uppercase">
                                            Highest Bid (Current)
                                        </label>                                    
                                        <input type="number" disabled value={this.state.newBid.currentHighestBid}  
                                                id="currentHighestBid" 
                                                name="currentHighestBid" className="form-control" />

                                    {!this.state.newBid.isCancelled ? 
                                    <>
                                        <label htmlFor="bidAmount" className="grey-text mt-2 small text-uppercase">
                                            Bid Amount
                                        </label>
                                        <input type="number" min={0} value={this.state.bidAmount} onChange={this.handleChange} id="bidAmount" name="bidAmount" className="form-control" />
                                        
                                        <MDBRow>
                                            <MDBContainer className="mt-2">
                                                <MDBBtn onClick={this.placeBid} block color="info" >{this.state.loading.placeBidBtn ? <Spinner size="small"/> : <span>Place Bid</span> }</MDBBtn>
                                            </MDBContainer>
                                        </MDBRow>
                                    </>
                                    : 
                                        <MDBRow>
                                            <MDBContainer className="mt-2">
                                                <MDBBtn onClick={this.withdrawFunds(this.state.newBid.itemId)} block color="info" >{this.state.loading.withdrawBtn ? <Spinner size="small"/> : <span>Withdraw</span> }</MDBBtn>
                                            </MDBContainer>
                                        </MDBRow>
                                    }
                                    
                                </MDBCard>
                            </section>                            
                        :null}
                        {/* <div className="art-side-bar-wrapper pr-2">
                            {this.state.myBids.length > 0 ?
                                this.state.myBids.map((item, index) => {
                                    return(
                                        <ArtListItem key={index} artTitle={item.name} currentHighestBid="" timeLeft={""} />
                                    );
                                })
                            : <h6 className="mt-3">There are no bids</h6>}
                        </div> */}
                    </MDBCol>
                </MDBRow>
            </MDBContainer>
    
        );
    }
}

export default MarketPlaceBuy;