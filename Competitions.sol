pragma solidity 0.4.21;
import "tokens/eip20/EIP20Interface.sol";

contract Competitions{
    
    event _UpvoteCast(address upvoter, uint amount);
    event _DownvoteCast(address downvoter, uint amount);
    event _SubmissionPassed(string indexed listingHash);
    event _SubmissionDenied(string indexed listingHash);
    event _ListingSubmitted(string indexed listingHash);
    event _ListingRemoved(string indexed listingHash);

    struct Submission{
        address submitter; //Include submitter and initial token stake as first TokenStake
        uint expirationTime;
        uint128 upvoteTotal;
        uint128 downvoteTotal;
        bytes32 submittedDataHash;
        address[] promoters;
        address[] challengers;
        mapping( address => uint ) balances;
    }
    
    // Global Variables
    address owner;
    //mapping( uint =>Submission ) submissionsArray; //Option
    Submission[] submissionsArray; //Serves as the submissionID for all submissions in contract
    EIP20Interface token;
    string name;
    
    //Constructor
    function Competitions() public{
        owner = msg.sender;
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
        Submission newSub;
        token.transferFrom(msg.sender, this, amount);
        newSub.submitter = msg.sender;
        newSub.upvoteTotal = amount;
        newSub.downvoteTotal = 0;
        newSub.submittedDataHash = givenDataHash;
        newsub.expirationTime = now + 604800; //set exipration after one week (could make adjustable)
        newsub.promoters.push(msg.sender);
        balances[msg.sender] += amount;
    }
    
    function removeListing(Submission listing) submitterOnly(listing) timeTested(listing) public {
        for (uint i = 0 ; i < listing.promoters.length ; i++){
            token.transfer(listing.promoters[i], balances[listing.promoters[i]]);
        }
        for (uint i = 0 ; i < listing.challengers.length; i++){
            token.transfer(listing.challengers[i], balances[listing.challengers[i]]);
        }
        for (uint i = 0 ; i < submissionsArray.length ; i++){
            if (submissionsArray[i] == listing){
                delete submissionsArray[i];
            }
        }
    }
    
    function upvote(Submission listing, uint amount) public timeTested(listing) payable{
        token.transferFrom(msg.sender, this, amount);
        listing.promoters.push(msg.sender);
        listing.balances[msg.sender] += amount;
	    
    }

    function downvote(Submission listing, uint amount) public timeTested(listing) payable{
        token.transferFrom(msg.sender, this, amount);
        listing.challengers.push(msg.sender);
        listing.balances[msg.sender] += amount;
    }
    
    function calculateVotes() public ownerOnly {
        for (uint i = 0 ; i < submissionsArray.length ; i++){
            if (submissionsArray[i].upvoteTotal > downvoteTotal){
                submissionPublished(submissionsArray[i]);
            } else if (submissionsArray[i].downvoteTotal > upvoteTotal) {
                submissionRejected(submissionsArray[i]);
            } else {
                
            }
        }
    }
    
    function submissionPublished(Submission winner) internal{
        for (uint i = 0 ; i < winner.promoters.length ; i++){
            uint ratio = (balances[winner.promoters[i]] / winner.upvoteTotal)*100;
            uint amountWon = (ratio*winner.downvoteTotal)/100;
            token.transfer(winner.promoters[i], amountWon);
        }
        balances = 0;
    }
    
    function submissionRejected(Submission loser) internal{
        for (uint i = 0 ; i < loser.challengers.length ; i++){
            uint ratio = (balances[loser.challengers[i]] / loser.downvoteTotal)*100;
            uint amountWon = (ratio*loser.upvoteTotal)/100;
            token.transfer(loser.challengers[i], amountWon);
        }
        balances = 0;
    }

}
