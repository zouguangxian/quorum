pragma solidity ^0.5.3;

contract ContractExtender {

    //target details - what, who and when to extend
    address public creator;
    string public targetRecipientPublicKeyHash;
    address public contractToExtend;

    //list of wallet addresses that can cast votes
    address[] public walletAddressesToVote;
    uint256 public totalNumberOfVoters;
    mapping(address => bool) walletAddressesToVoteMap;
    uint256 numberOfVotesSoFar;
    mapping(address => bool) hasVotedMapping;
    mapping(address => bool) public votes;

    //contains the total outcome of voting
    //true if ALL nodes vote true, false if ANY node votes false
    bool public voteOutcome;

    //the hash of the shared payload
    string public sharedDataHash;
    string[] uuids;

    //if creator cancelled this extension
    bool public isFinished;

    // General housekeeping
    event NewContractExtensionContractCreated(address toExtend); //to tell nodes a new extension is happening
    event AllNodesHaveVoted(bool outcome); //when all nodes have voted
    event CanPerformStateShare(); //when all nodes have voted & the recipient has accepted
    event ExtensionFinished(); //if the extension is cancelled or completed
    event NewVote(bool vote, address voter); // when someone voted (either true or false)
    event StateShared(address toExtend, string tesserahash, string uuid); //when the state is shared and can be replayed into the database
    event UpdateMembers(address toExtend, string uuid); //to update the original transaction hash for the new party member

    constructor(address contractAddress, address[] memory walletAddresses, string memory recipientHash, string memory uuid) public {
        creator = msg.sender;

        targetRecipientPublicKeyHash = recipientHash;

        contractToExtend = contractAddress;
        walletAddressesToVote = walletAddresses;
        sharedDataHash = "";

        voteOutcome = true;
        numberOfVotesSoFar = 0;

        // check if we exist in the list of voters
        bool found = false;
        for (uint256 i = 0; i < walletAddresses.length; i++) {
            walletAddressesToVoteMap[walletAddresses[i]] = true;
            if (walletAddresses[i] == msg.sender) {
                found = true;
            }
        }
        // if not, then add ourselves, then immediately vote
        if (!found) {
            walletAddressesToVote.push(msg.sender);
            walletAddressesToVoteMap[msg.sender] = true;
        }
        totalNumberOfVoters = walletAddressesToVote.length;

        emit NewContractExtensionContractCreated(contractAddress);

        //set the sender to vote true, else why would they create the contract?
        doVote(true, uuid);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //modifiers
    /////////////////////////////////////////////////////////////////////////////////////
    modifier notFinished() {
        require(!isFinished, "extension has been marked as finished");
        _;
    }

    modifier onlyCreator() {
        require(msg.sender == creator, "only leader may perform this action");
        _;
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //main
    /////////////////////////////////////////////////////////////////////////////////////
    function haveAllNodesVoted() public view returns (bool) {
        return walletAddressesToVote.length == numberOfVotesSoFar;
    }

    // single node vote to either extend or not
    // can't have voted before
    function doVote(bool vote, string memory nextuuid) public notFinished() {
        cast(vote);
        if (vote) {
            setUuid(nextuuid);
        }
        // check if voting has finished
        checkVotes();
        emit NewVote(vote, msg.sender);
    }

    // this event is emitted to tell each node to use this tx as the original tx
    // only if they voted for it
    function updatePartyMembers() public {
        for(uint256 i = 0; i < uuids.length; i++) {
            emit UpdateMembers(contractToExtend, uuids[i]);
        }
    }

    //state has been shared off chain via a private transaction, the hash the PTM generated is set here
    function setSharedStateHash(string memory hash) public onlyCreator() notFinished() {
        bytes memory hashAsBytes = bytes(sharedDataHash);
        bytes memory incomingAsBytes = bytes(hash);

        require(incomingAsBytes.length != 0, "new hash cannot be empty");
        require(hashAsBytes.length == 0, "state hash already set");
        sharedDataHash = hash;

        for(uint256 i = 0; i < uuids.length; i++) {
            emit StateShared(contractToExtend, sharedDataHash, uuids[i]);
        }

        finish();
    }

    //close the contract to further modifications
    function finish() public notFinished() onlyCreator() {
        setFinished();
    }

    //this sets a unique code that only the sending node has access to, that can be referred to later
    function setUuid(string memory nextuuid) public notFinished() {
        uuids.push(nextuuid);
    }

    // Internal methods
    function setFinished() internal {
        isFinished = true;
        emit ExtensionFinished();
    }

    // checks if all the conditions for voting have been met
    // either all voted true and target accepted, or someone voted false
    function checkVotes() internal {
        if (!voteOutcome) {
            emit AllNodesHaveVoted(false);
            setFinished();
            return;
        }

        if (haveAllNodesVoted()) {
            emit AllNodesHaveVoted(true);
            emit CanPerformStateShare();
        }
    }

    function cast(bool vote) internal {
        require(walletAddressesToVoteMap[msg.sender], "not allowed to vote");
        require(!hasVotedMapping[msg.sender], "already voted");
        require(voteOutcome, "voting already declined");

        hasVotedMapping[msg.sender] = true;
        votes[msg.sender] = vote;
        numberOfVotesSoFar++;
        voteOutcome = voteOutcome && vote;
    }
}