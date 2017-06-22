pragma solidity ^0.4.8;

contract ValidatorSet {
    event InitiateChange(bytes32 indexed _parent_hash, address[] _new_set);

    function getValidators() constant returns (address[] _validators);
    function finalizeChange();
}

// Existing validators can give support to addresses.
// Support can not be added once MAX_VALIDATORS are present.
// Once given, support can be removed.
// Addresses supported by more than half of the existing validators are the validators.
// Malicious behaviour causes support removal.
// Benign misbehaviour causes supprt removal if its called again after MAX_INACTIVITY.
// Benign misbehaviour can be absolved before being called the second time.

contract MajorityList is ValidatorSet {
    // EVENTS
    event Report(address indexed reporter, address indexed reported, bool indexed malicious);
    event Support(address indexed supporter, address indexed supported, bool indexed added);
    event ChangeFinalized(address[] current_set);

    struct ValidatorStatus {
        // Is this a validator.
        bool isValidator;
        // Index in the validatorList.
        uint index;
        // Validator addresses which supported the address.
        AddressSet.Data support;
        // Keeps track of the votes given out while the address is a validator.
        address[] supported;
        // Initial benign misbehaviour time tracker.
        mapping(address => uint) firstBenign;
        // Repeated benign misbehaviour counter.
        AddressSet.Data benignMisbehaviour;
    }

    // System address, used by the block sealer.
    address SYSTEM_ADDRESS = 0xf5777f8133aae2734396ab1d43ca54ad11bfb737;//2**160 - 2;
    // Support can not be added once this number of validators is reached.
    uint public constant MAX_VALIDATORS = 30;
    // Time after which the validators will report a validator as malicious.
    uint public constant MAX_INACTIVITY = 6 hours;
    // Ignore misbehaviour older than this number of blocks.
    uint public constant RECENT_BLOCKS = 20;
    /// Last block at which the validator set was altered.
    uint public lastTransitionBlock;
    // Current list of addresses entitled to participate in the consensus.
    address[] public validatorsList;
    // Pending list of validator addresses.
    address[] pendingList;
    // Was the last validator change finalized.
    bool finalized;
    // Tracker of status for each address.
    mapping(address => ValidatorStatus) validatorsStatus;

    // Used to lower the constructor cost.
    AddressSet.Data initialSupport;

    // Each validator is initially supported by all others.
    function MajorityList() {
        pendingList.push(0xf5777f8133aae2734396ab1d43ca54ad11bfb737);

        initialSupport.count = pendingList.length;
        for (uint i = 0; i < pendingList.length; i++) {
            address supporter = pendingList[i];
            initialSupport.inserted[supporter] = true;
        }

        for (uint j = 0; j < pendingList.length; j++) {
            address validator = pendingList[j];
            validatorsStatus[validator] = ValidatorStatus({
                isValidator: true,
                index: j,
                support: initialSupport,
                supported: pendingList,
                benignMisbehaviour: AddressSet.Data({ count: 0 }),
            });
        }
        validatorsList = pendingList;
        finalized = true;
    }

    // Called on every block to update node validator list.
    function getValidators() constant returns (address[]) {
        return validatorsList;
    }

    // Log desire to change the current list.
    function initiateChange() private when_finalized {
        finalized = false;
        InitiateChange(block.blockhash(block.number - 1), pendingList);
    }

    function finalizeChange() only_system_and_not_finalized {
        validatorsList = pendingList;
        finalized = true;
        ChangeFinalized(validatorsList);
    }

    // SUPPORT LOOKUP AND MANIPULATION

    // Find the total support for a given address.
    function getSupport(address validator) constant returns (uint) {
        return AddressSet.count(validatorsStatus[validator].support);
    }

    function getSupported(address validator) constant returns (address[]) {
        return validatorsStatus[validator].supported;
    }

    // Vote to include a validator.
    function addSupport(address validator) only_validator not_voted(validator) free_validator_slots {
        newStatus(validator);
        AddressSet.insert(validatorsStatus[validator].support, msg.sender);
        validatorsStatus[msg.sender].supported.push(validator);
        addValidator(validator);
        Support(msg.sender, validator, true);
    }

    // Remove support for a validator.
    function removeSupport(address sender, address validator) private {
        if (!AddressSet.remove(validatorsStatus[validator].support, sender)) { throw; }
        Support(sender, validator, false);
        // Remove validator from the list if there is not enough support.
        removeValidator(validator);
    }

    // MALICIOUS BEHAVIOUR HANDLING

    // Called when a validator should be removed.
    function reportMalicious(address validator, uint blockNumber, bytes proof) only_validator is_recent(blockNumber) {
        removeSupport(msg.sender, validator);
        Report(msg.sender, validator, true);
    }

    // BENIGN MISBEHAVIOUR HANDLING

    // Report that a validator has misbehaved in a benign way.
    function reportBenign(address validator, uint blockNumber) only_validator is_validator(validator) is_recent(blockNumber) {
        firstBenign(validator);
        repeatedBenign(validator);
        Report(msg.sender, validator, false);
    }

    // Find the total number of repeated misbehaviour votes.
    function getRepeatedBenign(address validator) constant returns (uint) {
        return AddressSet.count(validatorsStatus[validator].benignMisbehaviour);
    }

    // Track the first benign misbehaviour.
    function firstBenign(address validator) private has_not_benign_misbehaved(validator) {
        validatorsStatus[validator].firstBenign[msg.sender] = now;
    }

    // Report that a validator has been repeatedly misbehaving.
    function repeatedBenign(address validator) private has_repeatedly_benign_misbehaved(validator) {
        AddressSet.insert(validatorsStatus[validator].benignMisbehaviour, msg.sender);
        confirmedRepeatedBenign(validator);
    }

    // When enough long term benign misbehaviour votes have been seen, remove support.
    function confirmedRepeatedBenign(address validator) private agreed_on_repeated_benign(validator) {
        validatorsStatus[validator].firstBenign[msg.sender] = 0;
        AddressSet.remove(validatorsStatus[validator].benignMisbehaviour, msg.sender);
        removeSupport(msg.sender, validator);
    }

    // Absolve a validator from a benign misbehaviour.
    function absolveFirstBenign(address validator) has_benign_misbehaved(validator) {
        validatorsStatus[validator].firstBenign[msg.sender] = 0;
        AddressSet.remove(validatorsStatus[validator].benignMisbehaviour, msg.sender);
    }

    // PRIVATE UTILITY FUNCTIONS

    // Add a status tracker for unknown validator.
    function newStatus(address validator) private has_no_votes(validator) {
        validatorsStatus[validator] = ValidatorStatus({
            isValidator: false,
            index: pendingList.length,
            support: AddressSet.Data({ count: 0 }),
            supported: new address[](0),
            benignMisbehaviour: AddressSet.Data({ count: 0 })
        });
    }

    // ENACTMENT FUNCTIONS (called when support gets out of line with the validator list)

    // Add the validator if supported by majority.
    // Since the number of validators increases it is possible to some fall below the threshold.
    function addValidator(address validator) is_not_validator(validator) has_high_support(validator) {
        validatorsStatus[validator].index = pendingList.length;
        pendingList.push(validator);
        validatorsStatus[validator].isValidator = true;
        // New validator should support itself.
        AddressSet.insert(validatorsStatus[validator].support, validator);
        validatorsStatus[validator].supported.push(validator);
        initiateChange();
    }

    // Remove a validator without enough support.
    // Can be called to clean low support validators after making the list longer.
    function removeValidator(address validator) is_validator(validator) has_low_support(validator) {
        uint removedIndex = validatorsStatus[validator].index;
        // Can not remove the last validator.
        uint lastIndex = pendingList.length-1;
        address lastValidator = pendingList[lastIndex];
        // Override the removed validator with the last one.
        pendingList[removedIndex] = lastValidator;
        // Update the index of the last validator.
        validatorsStatus[lastValidator].index = removedIndex;
        delete pendingList[lastIndex];
        pendingList.length--;
        // Reset validator status.
        validatorsStatus[validator].index = 0;
        validatorsStatus[validator].isValidator = false;
        // Remove all support given by the removed validator.
        address[] toRemove = validatorsStatus[validator].supported;
        for (uint i = 0; i < toRemove.length; i++) {
            removeSupport(validator, toRemove[i]);
        }
        delete validatorsStatus[validator].supported;
        initiateChange();
    }

    // MODIFIERS

    function highSupport(address validator) constant returns (bool) {
        return getSupport(validator) > pendingList.length/2;
    }

    function firstBenignReported(address reporter, address validator) constant returns (uint) {
        return validatorsStatus[validator].firstBenign[reporter];
    }

    modifier has_high_support(address validator) {
        if (highSupport(validator)) { _; }
    }

    modifier has_low_support(address validator) {
        if (!highSupport(validator)) { _; }
    }

    modifier has_not_benign_misbehaved(address validator) {
        if (firstBenignReported(msg.sender, validator) == 0) { _; }
    }

    modifier has_benign_misbehaved(address validator) {
        if (firstBenignReported(msg.sender, validator) > 0) { _; }
    }

    modifier has_repeatedly_benign_misbehaved(address validator) {
        if (firstBenignReported(msg.sender, validator) - now > MAX_INACTIVITY) { _; }
    }

    modifier agreed_on_repeated_benign(address validator) {
        if (getRepeatedBenign(validator) > pendingList.length/2) { _; }
    }

    modifier free_validator_slots() {
        if (pendingList.length >= MAX_VALIDATORS) { throw; }
        _;
    }

    modifier only_validator() {
        if (!validatorsStatus[msg.sender].isValidator) { throw; }
        _;
    }

    modifier is_validator(address someone) {
        if (validatorsStatus[someone].isValidator) { _; }
    }

    modifier is_not_validator(address someone) {
        if (!validatorsStatus[someone].isValidator) { _; }
    }

    modifier not_voted(address validator) {
        if (AddressSet.contains(validatorsStatus[validator].support, msg.sender)) {
            throw;
        }
        _;
    }

    modifier has_no_votes(address validator) {
        if (AddressSet.count(validatorsStatus[validator].support) == 0) { _; }
    }

    modifier is_recent(uint blockNumber) {
        if (block.number > blockNumber + RECENT_BLOCKS) { throw; }
        _;
    }

    modifier only_system_and_not_finalized() {
        if (msg.sender != SYSTEM_ADDRESS || finalized) { throw; }
        _;
    }

    modifier when_finalized() {
        if (!finalized) { throw; }
        _;
    }

    // Fallback function throws when called.
    function() {
        throw;
    }
}

library AddressSet {
    // Tracks the number of votes from different addresses.
    struct Data {
        uint count;
        // Keeps track of who voted, prevents double vote.
        mapping(address => bool) inserted;
    }

    function count(Data storage self) constant returns (uint) {
        return self.count;
    }

    function contains(Data storage self, address voter) returns (bool) {
        return self.inserted[voter];
    }

    function insert(Data storage self, address voter) returns (bool) {
        if (self.inserted[voter]) { return false; }
        self.count++;
        self.inserted[voter] = true;
        return true;
    }

    function remove(Data storage self, address voter) returns (bool) {
        if (!self.inserted[voter]) { return false; }
        self.count--;
        self.inserted[voter] = false;
        return true;
    }
}
