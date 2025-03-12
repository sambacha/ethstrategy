
// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.28;

contract CryticInterface{
    address internal crytic_owner = address(0x627306090abaB3A6e1400e9345bC60c78a8BEf57);
    address internal crytic_user = address(0xf17f52151EbEF6C7334FAD080c5704D77216b732);
    address internal crytic_attacker = address(0xC5fdf4076b8F3A5357c5E395ab970B5B54098Fef);
    uint internal initialTotalSupply;
    uint internal initialBalance_owner;
    uint internal initialBalance_user;
    uint internal initialBalance_attacker;
}
