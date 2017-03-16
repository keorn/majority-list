pragma solidity ^0.4.8;

// Existing validators can give support to addresses.
// Once given support can be removed.
// Addresses supported by more than half of the existing validators are the validators.
// Both reporting functions simply remove support.
contract MajorityList {
    event ValidatorSet(bool indexed added, address indexed validator);
    event Report(address indexed reporter, address indexed reported, bool indexed malicious);
    event Support(address indexed supporter, address indexed supported, bool indexed added);

    struct ValidatorStatus {
        // Index in the validatorList.
        uint index;
        // Validator addresses which supported the validator.
        SupportTracker support;
    }

    // Tracks the amount of support for a given validator.
    struct SupportTracker {
        uint votes;
        // Keeps track of who voted for given address, prevent double voting.
        mapping(address => bool) voted;
    }

    // Support can not be added once this number of validators is reached.
    uint maxValidators = 30;
    // Accounts used for testing: "0".sha3() and "1".sha3()
    address[] public validatorsList;
    mapping(address => ValidatorStatus) validatorsStatus;

    // Each validator is initially supported by all others.
    function MajorityList() {
        validatorsList.push(0xF5777f8133aAe2734396ab1d43ca54aD11BFB737);

        if (validatorsList.length > maxValidators) { throw; }

        for (uint i = 0; i < validatorsList.length; i++) {
            address validator = validatorsList[i];
            validatorsStatus[validator] = ValidatorStatus({
                index: i,
                support: SupportTracker({
                    votes: validatorsList.length
                })
            });
            for (uint j = 0; j < validatorsList.length; j++) {
                address supporter = validatorsList[j];
                validatorsStatus[validator].support.voted[supporter] = true;
                Support(supporter, validator, true);
            }
            ValidatorSet(true, validator);
        }
    }

    // Called on every block to update node validator list.
    function getValidators() constant returns (address[]) {
        return validatorsList;
    }

    // Find the total support for a given address.
    function getSupport(address validator) constant returns (uint) {
        return validatorsStatus[validator].support.votes;
    }

    // Vote to include a validator.
    function addSupport(address validator) onlyValidator notVoted(validator) freeValidatorSlots {
        newStatus(validator);
        validatorsStatus[validator].support.votes++;
        addValidator(validator);
        validatorsStatus[validator].support.voted[msg.sender] = true;
        Support(msg.sender, validator, true);
    }

    // Called when a validator should be removed.
    function reportMalicious(address validator) onlyValidator hasHighSupport(validator) {
        removeSupport(msg.sender, validator);
        Report(msg.sender, validator, true);
        removeValidator(validator);
    }

    // Called when a validator should be removed.
    function reportBenign(address validator) onlyValidator hasHighSupport(validator) {
        Report(msg.sender, validator, false);
    }

    // Remove support for a validator.
    function removeSupport(address sender, address validator) private hasVotes(sender, validator) {
        validatorsStatus[validator].support.votes--;
        validatorsStatus[validator].support.voted[sender] = false;
        //Support(sender, validator, false);
        // Remove validator from the list if there is not enough support.
        removeValidator(validator);
    }

    // Add a status tracker for unknown validator.
    function newStatus(address validator) private hasNoVotes(validator) {
        validatorsStatus[validator] = ValidatorStatus({
            index: validatorsList.length,
            support: SupportTracker({ votes: 0 })
        });
    }

    // Add the validator if supported by majority.
    // Since the number of validators increases it is possible to some fall below the threshold.
    function addValidator(address validator) private hasHighSupport(validator) {
        validatorsStatus[validator].index = validatorsList.length;
        validatorsList.push(validator);
        // New validator should support itself.
        validatorsStatus[validator].support.votes++;
        validatorsStatus[validator].support.voted[validator] = true;
        ValidatorSet(true, validator);
    }

    // Remove a validator without enough support.
    // Can be called to clean low support validators after making the list longer.
    function removeValidator(address validator) hasLowSupport(validator) {
        uint removedIndex = validatorsStatus[validator].index;
        // Can not remove the last validator.
        uint lastIndex = validatorsList.length-1;
        address lastValidator = validatorsList[lastIndex];
        // Override the removed validator with the last one.
        validatorsList[removedIndex] = lastValidator;
        // Update the index of the last validator.
        validatorsStatus[lastValidator].index = removedIndex;
        delete validatorsList[lastIndex];
        validatorsList.length--;
        validatorsStatus[validator].index = 0;
        // Remove all support given by the removed validator.
        for (uint i = 0; i < validatorsList.length; i++) {
            removeSupport(validator, validatorsList[i]);
        }
        ValidatorSet(false, validator);
    }

    function highSupport(address validator) constant returns (bool) {
        return getSupport(validator) > validatorsList.length/2;
    }

    modifier hasNoVotes(address validator) {
        if (validatorsStatus[validator].support.votes == 0) _;
    }

    modifier freeValidatorSlots() {
        if (validatorsList.length >= maxValidators) throw; _;
    }

    modifier hasHighSupport(address validator) {
        if (highSupport(validator)) _;
    }

    modifier hasLowSupport(address validator) {
        if (!highSupport(validator)) _;
    }

    modifier onlyValidator() {
        if (!highSupport(msg.sender)) throw; _;
    }

    modifier notVoted(address validator) {
        if (validatorsStatus[validator].support.voted[msg.sender]) throw; _;
    }

    modifier hasVotes(address sender, address validator) {
        if (validatorsStatus[validator].support.votes > 0
            && validatorsStatus[validator].support.voted[sender]) _;
    }
}
