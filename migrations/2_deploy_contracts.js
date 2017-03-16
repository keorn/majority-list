var MajorityList = artifacts.require("./MajorityList.sol");

module.exports = function(deployer) {
  deployer.deploy(MajorityList);
};
