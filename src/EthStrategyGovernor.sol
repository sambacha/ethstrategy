// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import {IGovernor, Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

contract EthStrategyGovernor is 
    Governor, 
    GovernorVotes, 
    GovernorCountingSimple, 
    GovernorVotesQuorumFraction 
{
    constructor(
        IVotes _token,
        uint256 _quorumPercentage
    )
        Governor("EthStrategyGovernor")
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(_quorumPercentage)
    {}

    // The following functions are overrides required by Solidity.

    function votingDelay() public pure override returns (uint256) {
        return 7200; // 1 day at 12 sec block time
    }

    function votingPeriod() public pure override returns (uint256) {
        return 50400; // 1 week at 12 sec block time
    }

    function proposalThreshold() public pure override returns (uint256) {
        return 0; // Minimum token threshold to propose (e.g., 1000 tokens)
    }

    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    function supportsInterface(bytes4 interfaceId) public view override(Governor) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
