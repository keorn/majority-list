var MajorityList = artifacts.require("../contracts/MajorityList.sol");

// testrpc --account 0xe00a3d4e0ed5638fde85df50739f767c7d85d72a7d1a5548f21ed7f0d05b90c1,99999999999999999999 --account 0xb8b9b0006a8a353836aa296af16b1c92aa0a2b0569d1d7fb1fac7f25dbbccba2,99999999999999999999 --account 0x9856d83361e3ef6f594f25ee471416cf6a7d1c55fe777f42597243c0aa2c8fa9,99999999999999999999

contract('MajorityList', function(accounts) {
  it("should contain the first validator", function() {
    return MajorityList.deployed().then(function(instance) {
      return instance.getValidators.call();
    }).then(function(list) {
      assert.equal(list.valueOf()[0], accounts[0], "incorrect validators");
    });
  });

  it("should get high support", function() {
    return MajorityList.deployed().then(function(instance) {
      return instance.getSupport.call(accounts[0]);
    }).then(function(result) {
      assert.equal(result.toNumber(), 1, "first should support itself");
    });
  });

  it("should get low support", function() {
    return MajorityList.deployed().then(function(instance) {
      return instance.getSupport.call(accounts[1]);
    }).then(function(result) {
      assert.equal(result.toNumber(), 0, "first should support itself");
    });
  });

  it("should judge validator", function() {
    return MajorityList.deployed().then(function(instance) {
      return instance.highSupport.call(accounts[0]);
    }).then(function(result) {
      assert.equal(result.valueOf(), true, "should have high support");
    });
  });

  it("should judge not a validator", function() {
    return MajorityList.deployed().then(function(instance) {
      return instance.highSupport.call(accounts[1]);
    }).then(function(result) {
      assert.equal(result.valueOf(), false, "should have low support");
    });
  });

  it("should add a supported address", function() {
    return MajorityList.deployed().then(function(instance) {
      return instance.addSupport(accounts[1]);
    }).then(function(result) {
      assert.equal(result.logs[0].event, "ValidatorSet", "validator alteration log not present");
      assert.equal(result.logs[1].event, "Support", "support log not present");
    });
  });

  it("should event on benign misbehaviour report", function() {
    return MajorityList.deployed().then(function(instance) {
      return instance.reportBenign(accounts[1]);
    }).then(function(result) {
      assert.equal(result.logs[0].event, "Report", "report log not present");
    });
  });


});
