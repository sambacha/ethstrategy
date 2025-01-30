pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";  
import {Script} from "forge-std/Script.sol";
import {AtmAuction} from "../src/AtmAuction.sol";
import {BondAuction} from "../src/BondAuction.sol";
import {EthStrategy} from "../src/EthStrategy.sol";
import {EthStrategyGovernor} from "../src/EthStrategyGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Deposit} from "../src/Deposit.sol";

contract SignAddresses is Script {
  struct Encode {
    address[] whitelist;
  }
  function run() public {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/whitelist.json");
    string memory json = vm.readFile(path);
    bytes memory data = vm.parseJson(json);
    address[] memory addresses = (abi.decode(data, (Encode))).whitelist;

    vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
    string memory output;
    string memory addressesJson = "addresses";
    for(uint256 i = 0; i < addresses.length; i++) {
      address _address = addresses[i];
      bytes32 hash = keccak256(abi.encodePacked(_address));
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(vm.envUint("PRIVATE_KEY")), hash);
      bytes memory signature = abi.encodePacked(r, s, v);
      output = vm.serializeBytes(addressesJson, toString(abi.encodePacked(_address)), signature);
    }
    vm.writeJson(output, "./signed-whitelist.json");

  }

  function toString(bytes memory data) public pure returns(string memory) {
    bytes memory alphabet = "0123456789abcdef";

    bytes memory str = new bytes(2 + data.length * 2);
    str[0] = "0";
    str[1] = "x";
    for (uint i = 0; i < data.length; i++) {
        str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
        str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
    }
    return string(str);
  }
}