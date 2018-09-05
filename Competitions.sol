pragma solidity 0.4.21;
import "tokens/eip20/EIP20Interface.sol";

contract Registry{
    
    event _UpvoteCast(address upvoter, uint amount);
    event _DownvoteCast(address downvoter, uint amount);
    event _SubmissionPassed(bytes32 indexed listingHash);
    event _SubmissionDenied(bytes32 indexed listingHash);
    event _ListingSubmitted(bytes32 indexed listingHash);
    event _ListingRemoved(bytes32 indexed listingHash);

    struct Submission{
        address submitter; //Include submitter and initial token stake as first TokenStake
        uint expirationTime; //
        uint upvoteTotal;
        uint downvoteTotal;
        bytes32 submittedDataHash; //
        address[] promoters;
        address[] challengers;
        mapping( address => uint ) balances;
        bool completed;
    }
    
    // Global Variables
    address private owner;
    mapping( bytes32 => Submission ) public submissionsMapping; //Ensures uniqueness of submissions
    bytes32[] public submissionsArray; //Indexes mapping
    EIP20Interface public token;
    string public name;
    uint public minDeposit;
    
    //Constructor
    function Competitions() public{
        owner = msg.sender;
        minDeposit = 50;
    }
    
    //Modifiers
    modifier submitterOnly (Submission sub) {
        require(msg.sender == sub.submitter || msg.sender == owner, "Invalid Credentials");
        _;
    }
    modifier ownerOnly {
        require(msg.sender == owner, "You are not the owner.");
        _;
    }
    modifier timeTested (Submission sub) {
        require(sub.expirationTime < now, "Expiration time has passed.");
        _;
    }

    /**
    @dev Initializer. Can only be called once.
    @param _token The address where the ERC20 token contract is deployed
    */
    function init(address _token, string _name) public {
        require(_token != 0 && address(token) == 0, "Token provided invalid");
        token = EIP20Interface(_token);
        name = _name;
    }
    
    function addSubmission(bytes32 givenDataHash, uint amount) public payable{
        //Validate that the submitter has met the minimum deposit and that they aren't submitting a previously used answer
        require(amount >= minDeposit && submissionsMapping[givenDataHash] == 0);
        token.transferFrom(msg.sender, this, amount);
        
        //set exipration after one week (could make adjustable)
        Submission newSub = Submission({submitter: msg.sender, upvoteTotal: amount, downvoteTotal: 0, submittedDataHash: givenDataHash, expirationTime: now + 604800, completed: false});
        newSub.promoters.push(msg.sender);
        newSub.balances[msg.sender] += amount;
        
        submissionsMapping[givenDataHash] = newSub;
        submissionsArray.push(givenDataHash);
        
        emit _ListingSubmitted(givenDataHash);
    }
    
    function removeListing(Submission listing) submitterOnly(listing) timeTested(listing) public {
        for (uint i = 0 ; i < listing.promoters.length ; i++){
            token.transfer(listing.promoters[i], balances[listing.promoters[i]]);
        }
        for (uint i = 0 ; i < listing.challengers.length; i++){
            token.transfer(listing.challengers[i], balances[listing.challengers[i]]);
        }
        for (uint i = 0 ; i < submissionsArray.length ; i++){
            if (submissionsMapping[submissionsArray[i]].submittedDataHash == listing.submittedDataHash){
                submissionsMapping[submissionsArray[i]] = 0;
                delete submissionsArray[i];
            }
        }
        
        emit _ListingRemoved(listing.submittedDataHash);
    }
    
    function upvote(Submission listing, uint amount) public timeTested(listing) payable{
        token.transferFrom(msg.sender, this, amount);
        listing.promoters.push(msg.sender);
        listing.balances[msg.sender] += amount;
        
        emit _UpvoteCast(msg.sender, amount);
    }

    function downvote(Submission listing, uint amount) public timeTested(listing) payable{
        token.transferFrom(msg.sender, this, amount);
        listing.challengers.push(msg.sender);
        listing.balances[msg.sender] += amount;
        
        emit _DownvoteCast(msg.sender, amount);
    }
    
    //Run daily from javascript code
    function calculateVotes() public view {
        for (uint i = 0 ; i < submissionsArray.length ; i++){
            if (submissionsMapping[submissionsArray[i]].expirationTime > now){
                if (submissionsMapping[submissionsArray[i]].upvoteTotal > downvoteTotal){
                    submissionPublish(submissionsMapping[submissionsArray[i]]);
                } else if (submissionsMapping[submissionsArray[i]].downvoteTotal > upvoteTotal) {
                    submissionReject(submissionsMapping[submissionsArray[i]]);
                } else {
                    removeListing(submissionsMapping[submissionsArray[i]]);
                }
            }
        }
    }
    
    function submissionPublish(Submission winner) internal{
        for (uint i = 0 ; i < winner.promoters.length ; i++){
            uint ratio = ((balances[winner.promoters[i]]*100) / (winner.upvoteTotal*100));
            uint amountWon = (ratio*(winner.downvoteTotal*100));
            token.transfer(winner.promoters[i], (amountWon/100));
        }
        
        winner.completed = true;
        balances = 0;
        
        emit _SubmissionPassed(winner.submittedDataHash);
    }
    
    function submissionReject(Submission loser) internal{
        for (uint i = 0 ; i < loser.challengers.length ; i++){
            uint ratio = ((balances[loser.challengers[i]]*100) / (loser.downvoteTotal*100));
            uint amountWon = (ratio*(loser.upvoteTotal*100));
            token.transfer(loser.challengers[i], (amountWon/100));
        }
        for (uint i = 0 ; i < submissionsArray.length ; i++){
            if (submissionsMapping[submissionsArray[i]].submittedDataHash == loser.submittedDataHash){
                submissionsMapping[submissionsArray[i]] = 0;
                delete submissionsArray[i];
            }
        }
        balances = 0;
        
        emit _SubmissionDenied(loser.submittedDataHash);
    }
    
    function getAllHashes() public view returns(bytes32[] allListings){
        return (submissionsArray);
    }
    
    function getListingData(bytes32 hashSearched) public view returns(uint[3] data){
        return([submissionsMapping[hashSearched].expirationTime, submissionsMapping[hashSearched].upvoteTotal, submissionsMapping[hashSearched].downvoteTotal]);
    }
    
    function getMinDeposit() public view returns(uint amount){
        return (minDeposit);
    }


}
