// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {IGovernor, Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

contract EthStrategyGovernor is Governor, GovernorVotes, GovernorCountingSimple, GovernorVotesQuorumFraction {
    uint256 immutable votingDelay_;
    uint256 immutable votingPeriod_;
    uint256 immutable proposalThreshold_;
    /// @notice The constructor for the EthStrategyGovernor contract, initializes the governor
    /// @param _token The token to use for voting
    /// @param _quorumPercentage The quorum percentage for the governor
    /// @param _votingDelay The voting delay for the governor (in blocks)
    /// @param _votingPeriod The voting period for the governor (in blocks)
    /// @param _proposalThreshold The proposal threshold for the governor (in tokens)

    constructor(
        IVotes _token,
        uint256 _quorumPercentage,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold
    ) Governor("EthStrategyGovernor") GovernorVotes(_token) GovernorVotesQuorumFraction(_quorumPercentage) {
        votingDelay_ = _votingDelay;
        votingPeriod_ = _votingPeriod;
        proposalThreshold_ = _proposalThreshold;
    }
    /// @inheritdoc Governor

    function votingDelay() public view override returns (uint256) {
        return votingDelay_;
    }
    /// @inheritdoc Governor

    function votingPeriod() public view override returns (uint256) {
        return votingPeriod_;
    }
    /// @inheritdoc Governor

    function proposalThreshold() public view override returns (uint256) {
        return proposalThreshold_;
    }
}
