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

contract Deploy is Script {

  struct Config {
    address lst;
    uint256 proposalThreshold;
    uint256 quorumPercentage;
    address usdc;
    uint256 votingDelay;
    uint256 votingPeriod;
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

    vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
    address publicKey = vm.addr(vm.envUint("PRIVATE_KEY"));
    console2.log("publicKey: ", publicKey);

    EthStrategy ethStrategy = new EthStrategy(publicKey);
    EthStrategyGovernor ethStrategyGovernor = new EthStrategyGovernor(IVotes(address(ethStrategy)), config.quorumPercentage, config.votingDelay, config.votingPeriod, config.proposalThreshold);
    AtmAuction atmAuction = new AtmAuction(address(ethStrategy), address(ethStrategyGovernor), config.lst);
    BondAuction bondAuction = new BondAuction(address(ethStrategy), address(ethStrategyGovernor), config.usdc);

    ethStrategy.mint(publicKey, 1);
    ethStrategy.transferOwnership(address(ethStrategyGovernor));

    vm.stopBroadcast();

    string memory deployed = "deployed";
    string memory deployedConfig = "deployedConfig";

    vm.serializeAddress(deployed, "EthStrategy", address(ethStrategy));
    vm.serializeAddress(deployed, "EthStrategyGovernor", address(ethStrategyGovernor));
    vm.serializeAddress(deployed, "AtmAuction", address(atmAuction));
    string memory deployedOutput = vm.serializeAddress(deployed, "BondAuction", address(bondAuction));
    vm.writeJson(deployedOutput, "./out/deployed.json");

    vm.serializeUint(deployedConfig, "startBlock", block.number);
    vm.serializeAddress(deployedConfig, "lst", config.lst);
    vm.serializeUint(deployedConfig, "proposalThreshold", config.proposalThreshold);
    vm.serializeUint(deployedConfig, "quorumPercentage", config.quorumPercentage);
    vm.serializeAddress(deployedConfig, "usdc", config.usdc);
    vm.serializeUint(deployedConfig, "votingDelay", config.votingDelay);
    vm.serializeAddress(deployedConfig, "ethStrategyInitialOwner", publicKey);
    string memory deployedConfigOutput = vm.serializeUint(deployedConfig, "votingPeriod", config.votingPeriod);

    vm.writeJson(deployedConfigOutput, "./out/deployed.config.json");
  }
}
