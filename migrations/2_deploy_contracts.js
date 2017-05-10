var MajorityList = artifacts.require("MajorityList");
var AddressSet = artifacts.require("AddressSet");

module.exports = function(deployer) {
  deployer.deploy(AddressSet);
  deployer.link(AddressSet, MajorityList);
  deployer.deploy(MajorityList);
};
