// read in json file
// read in private key
// start broadcast
// deploy contracts
// configure owner
// write args to file
//

pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";  
import {Script} from "forge-std/Script.sol";
import {AtmAuction} from "../src/AtmAuction.sol";
import {BondAuction} from "../src/BondAuction.sol";
import {EthStrategy} from "../src/EthStrategy.sol";
import {EthStrategyGovernor} from "../src/EthStrategyGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Deposit} from "../src/Deposit.sol";
contract Deploy is Script {

  struct Config {
    uint256 depositCap;
    uint256 depositConversionPremium;
    uint256 depositConversionRate;
    address depositSigner;
    address lst;
    uint256 proposalThreshold;
    uint256 quorumPercentage;
    address usdc;
    uint256 votingDelay;
    uint256 votingPeriod;
    bool whiteListEnabled;
  }

  function run() public { 

    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/deploy.config.json");
    string memory json = vm.readFile(path);
    bytes memory data = vm.parseJson(json);
    Config memory config = abi.decode(data, (Config));

    console2.log("votingDelay: ", config.votingDelay);
    console2.log("votingPeriod: ", config.votingPeriod);
    console2.log("proposalThreshold: ", config.proposalThreshold);
    console2.log("quorumPercentage: ", config.quorumPercentage);
    console2.log("lst: ", config.lst);
    console2.log("usdc: ", config.usdc);
    console2.log("depositCap: ", config.depositCap);
    console2.log("depositConversionRate: ", config.depositConversionRate);
    console2.log("depositConversionPremium: ", config.depositConversionPremium);
    console2.log("depositSigner: ", config.depositSigner);

    vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
    address publicKey = vm.addr(vm.envUint("PRIVATE_KEY"));
    console2.log("publicKey: ", publicKey);

    EthStrategy ethStrategy = new EthStrategy(publicKey);
    EthStrategyGovernor ethStrategyGovernor = new EthStrategyGovernor(IVotes(address(ethStrategy)), config.quorumPercentage, config.votingDelay, config.votingPeriod, config.proposalThreshold);
    AtmAuction atmAuction = new AtmAuction(address(ethStrategy), address(ethStrategyGovernor), config.lst);
    BondAuction bondAuction = new BondAuction(address(ethStrategy), address(ethStrategyGovernor), config.usdc);
    Deposit deposit = new Deposit(address(ethStrategyGovernor), address(ethStrategy), config.depositSigner, config.depositConversionRate, config.depositConversionPremium, config.depositCap, config.whiteListEnabled);

    ethStrategy.grantRoles(address(atmAuction), ethStrategy.MINTER_ROLE());
    ethStrategy.grantRoles(address(bondAuction), ethStrategy.MINTER_ROLE());
    ethStrategy.grantRoles(address(deposit), ethStrategy.MINTER_ROLE());
    ethStrategy.mint(publicKey, 1);
    
    ethStrategy.transferOwnership(address(ethStrategyGovernor));

    vm.stopBroadcast();

    string memory deployments = "deployments";

    vm.serializeAddress(deployments, "EthStrategy", address(ethStrategy));
    vm.serializeAddress(deployments, "EthStrategyGovernor", address(ethStrategyGovernor));
    vm.serializeAddress(deployments, "AtmAuction", address(atmAuction));
    vm.serializeAddress(deployments, "BondAuction", address(bondAuction));
    vm.serializeAddress(deployments, "Deposit", address(deposit));
    vm.serializeUint(deployments, "DepositCap", config.depositCap);
    vm.serializeUint(deployments, "DepositConversionRate", config.depositConversionRate);
    vm.serializeUint(deployments, "DepositConversionPremium", config.depositConversionPremium);
    vm.serializeAddress(deployments, "DepositSigner", config.depositSigner);
    vm.serializeUint(deployments, "startBlock", block.number);
    vm.serializeAddress(deployments, "lst", config.lst);
    vm.serializeUint(deployments, "proposalThreshold", config.proposalThreshold);
    vm.serializeUint(deployments, "quorumPercentage", config.quorumPercentage);
    vm.serializeAddress(deployments, "usdc", config.usdc);
    vm.serializeUint(deployments, "votingDelay", config.votingDelay);
    string memory output = vm.serializeUint(deployments, "votingPeriod", config.votingPeriod);

    vm.writeJson(output, "./out/deployments.json");
  }
}
