var MajorityList = artifacts.require("../contracts/MajorityList.sol");

// testrpc --account 0xe00a3d4e0ed5638fde85df50739f767c7d85d72a7d1a5548f21ed7f0d05b90c1,99999999999999999999 --account 0xb8b9b0006a8a353836aa296af16b1c92aa0a2b0569d1d7fb1fac7f25dbbccba2,99999999999999999999 --account 0x9856d83361e3ef6f594f25ee471416cf6a7d1c55fe777f42597243c0aa2c8fa9,99999999999999999999

contract('MajorityList', function(accounts) {
  it("should remove an unsupported address", function() {
		var validators;
    return MajorityList.deployed().then(function(instance) {
			validators = instance;
      return validators.addSupport(accounts[1]);
		}).then(function(result) {
			return validators.addSupport(accounts[0], { "from": accounts[1] });
		}).then(function(result) {
      assert.equal(result.logs[0].event, "Support", "support log not present");
			return validators.reportMalicious(accounts[1], 100, "0x0", { "from": accounts[0] });
    }).then(function(result) {
      assert.equal(result.logs[0].event, "Support", "support log not present");
      assert.equal(result.logs[1].event, "Support", "support log not present");
      assert.equal(result.logs[2].event, "Support", "support log not present");
      assert.equal(result.logs[3].event, "ValidatorsChanged", "validator alteration log not present");
      return validators.getSupport.call(accounts[0]);
    }).then(function(result) {
      assert.equal(result.toNumber(), 1, "first should support itself");
      return validators.getSupport.call(accounts[1]);
    }).then(function(result) {
      assert.equal(result.toNumber(), 0, "second should no longer have support");
			return validators.getValidators.call();
    }).then(function(list) {
      assert.equal(list.valueOf()[0], accounts[0], "incorrect validator");
      assert.equal(list.valueOf().length, 1, "wrong number of validators");
    });
  });
});
