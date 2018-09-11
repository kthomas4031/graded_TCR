pragma solidity 0.4.24;
import "http://github.com/ConsenSys/Tokens/contracts/eip20/EIP20Interface.sol";

contract Registry {
    event _UpvoteCast(address upvoter, uint amount);
    event _DownvoteCast(address downvoter, uint amount);
    event _SubmissionPassed(bytes32 indexed listingHash);
    event _SubmissionDenied(bytes32 indexed listingHash);
    event _ListingSubmitted(bytes32 indexed listingHash);
    event _ListingRemoved(bytes32 indexed listingHash);

    struct Submission {
        address submitter; //Include submitter and initial token stake as first TokenStake
        uint expirationTime; //
        uint upvoteTotal;
        uint downvoteTotal;
        bytes32 submittedDataHash; //
        address[] promoters;
        address[] challengers;
        mapping(address => uint) balances;
        bool completed;
        bool exists;
    }
    
    // Global Variables
    address private owner;
    mapping( bytes32 => Submission ) public submissionsMapping; //Ensures uniqueness of submissions
    bytes32[] public submissionsArray; //Indexes mapping
    EIP20Interface public token;
    string public name;
    uint public minDeposit;
    
    //Constructor
    function Reigistry() public {
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
    
    function addSubmission(bytes32 givenDataHash, uint amount) public payable {
        //Validate that the submitter has met the minimum deposit and that they aren't submitting a previously used answer
        require(amount >= minDeposit && submissionsMapping[givenDataHash].exists, "Minimum Deposit not met");
        token.transferFrom(msg.sender, this, amount);
        
        //set exipration after one week (could make adjustable)
        Submission newSub;
        newSub.submitter = msg.sender;
        newSub.upvoteTotal = amount;
        newSub.downvoteTotal = 0;
        newSub.submittedDataHash = givenDataHash;
        newSub.completed = false;
        newSub.expirationTime = now + 604800;
        newSub.exists = true;
        newSub.promoters.push(msg.sender);
        newSub.balances[msg.sender] += amount;
        
        submissionsMapping[givenDataHash] = newSub;
        submissionsArray.push(givenDataHash);
        emit _ListingSubmitted(givenDataHash);
    }

    function removeListing(bytes32 listingHash) public submitterOnly(submissionsMapping[listingHash]) timeTested(submissionsMapping[listingHash]) {
        for (uint i = 0 ; i < submissionsMapping[listingHash].promoters.length ; i++) {
            uint share = submissionsMapping[listingHash].balances[submissionsMapping[listingHash].promoters[i]];
            submissionsMapping[listingHash].balances[submissionsMapping[listingHash].promoters[i]] = 0;
            token.transfer(submissionsMapping[listingHash].promoters[i], share);
        }
        for (i = 0 ; i < submissionsMapping[listingHash].challengers.length; i++) {
            share = submissionsMapping[listingHash].balances[submissionsMapping[listingHash].challengers[i]];
            submissionsMapping[listingHash].balances[submissionsMapping[listingHash].challengers[i]] = 0;
            token.transfer(submissionsMapping[listingHash].challengers[i], submissionsMapping[listingHash].balances[submissionsMapping[listingHash].challengers[i]]);
        }
        for (i = 0 ; i < submissionsArray.length ; i++) {
            if (submissionsMapping[submissionsArray[i]].submittedDataHash == submissionsMapping[listingHash].submittedDataHash) {
                submissionsMapping[submissionsArray[i]].exists = false;
                delete submissionsArray[i];
            }
        }
        emit _ListingRemoved(submissionsMapping[listingHash].submittedDataHash);
    }
    
    function upvote(bytes32 listingHash, uint amount) public timeTested(submissionsMapping[listingHash]) payable {
        token.transferFrom(msg.sender, this, amount);
        submissionsMapping[listingHash].promoters.push(msg.sender);
        submissionsMapping[listingHash].balances[msg.sender] += amount;
        emit _UpvoteCast(msg.sender, amount);
    }

    function downvote(bytes32 listingHash, uint amount) public timeTested(submissionsMapping[listingHash]) payable {
        token.transferFrom(msg.sender, this, amount);
        submissionsMapping[listingHash].challengers.push(msg.sender);
        submissionsMapping[listingHash].balances[msg.sender] += amount;
        emit _DownvoteCast(msg.sender, amount);
    }
    
    //Run daily from javascript code
    function calculateVotes() public {
        for (uint i = 0 ; i < submissionsArray.length ; i++) {
            if (submissionsMapping[submissionsArray[i]].expirationTime > now) {
                if (submissionsMapping[submissionsArray[i]].upvoteTotal > submissionsMapping[submissionsArray[i]].downvoteTotal) {
                    submissionPublish(submissionsArray[i]);
                } else if (submissionsMapping[submissionsArray[i]].downvoteTotal > submissionsMapping[submissionsArray[i]].upvoteTotal) {
                    submissionReject(submissionsArray[i], i);
                } else {
                    removeListing(submissionsArray[i]);
                }
            }
        }
    }
    
    function submissionPublish(bytes32 listingHash) internal {
        for (uint i = 0 ; i < submissionsMapping[listingHash].promoters.length ; i++) {
            uint ratio = ((submissionsMapping[listingHash].balances[submissionsMapping[listingHash].promoters[i]]*100) / (submissionsMapping[listingHash].upvoteTotal*100));
            uint amountWon = (ratio*(submissionsMapping[listingHash].downvoteTotal*100));
            token.transfer(submissionsMapping[listingHash].promoters[i], (amountWon/100));
            submissionsMapping[listingHash].balances[submissionsMapping[listingHash].promoters[i]] = 0;
        }
        submissionsMapping[listingHash].completed = true;
        
        emit _SubmissionPassed(submissionsMapping[listingHash].submittedDataHash);
    }
    
    function submissionReject(bytes32 listingHash, uint g) internal {
        for (uint i = 0 ; i < submissionsMapping[listingHash].challengers.length ; i++) {
            uint ratio = ((submissionsMapping[listingHash].balances[submissionsMapping[listingHash].challengers[i]]*100) / (submissionsMapping[listingHash].downvoteTotal*100));
            uint amountWon = (ratio*(submissionsMapping[listingHash].upvoteTotal*100));
            token.transfer(submissionsMapping[listingHash].challengers[i], (amountWon/100));
            submissionsMapping[listingHash].balances[submissionsMapping[listingHash].challengers[i]] = 0;
        }
        delete submissionsArray[g];
        emit _SubmissionDenied(submissionsMapping[listingHash].submittedDataHash);
    }
    
    function getAllHashes() public view returns(bytes32[] allListings) {
        return (submissionsArray);
    }
    
    function getListingData(bytes32 hashSearched) public view returns(uint[3] data) {
        return([submissionsMapping[hashSearched].expirationTime, submissionsMapping[hashSearched].upvoteTotal,submissionsMapping[hashSearched].downvoteTotal]);
    }
    
    function getMinDeposit() public view returns(uint amount) {
        return (minDeposit);
    }
}
