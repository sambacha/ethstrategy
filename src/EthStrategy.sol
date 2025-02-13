// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {IGovernor, Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {
    TimelockController, ERC1155Holder, ERC721Holder
} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorPreventLateQuorum} from "@openzeppelin/contracts/governance/extensions/GovernorPreventLateQuorum.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Votes, VotesExtended} from "@openzeppelin/contracts/governance/utils/VotesExtended.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

interface INavAccountant {
    struct NavValue {
        address token;
        uint256 value;
    }

    function getNavValue(uint256 _amount, uint256 _discount) external view returns (NavValue[] memory navValues);
}

interface IEthStrategy is INavAccountant {
    function decimals() external view returns (uint8);
    function mint(address _to, uint256 _amount) external;
}

contract EthStrategy is
    ERC20Votes,
    VotesExtended,
    Governor,
    TimelockController,
    INavAccountant,
    GovernorVotes,
    GovernorCountingSimple,
    GovernorVotesQuorumFraction,
    GovernorSettings,
    GovernorPreventLateQuorum,
    GovernorTimelockControl
{
    uint16 public rageQuitPenalty;

    error RageQuitPenaltyTooHigh();
    error TransferPaused();
    error ProposalNotQueued();
    error ForVotesCannotRageQuit();
    error AmountExceedsPastBalance();
    /// @dev The role for the minter is able to mint unlimited tokens

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @dev The role of the pauser can pause transfers of tokens
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @dev The role for the admin
    bytes32 public constant NAV_ADMIN_ROLE = keccak256("NAV_ADMIN_ROLE");
    /// @dev The transfer pause status, minting is still allowed
    bool public isTransferPaused = true;
    /// @dev The error for when a transfer is attempted but transfers are paused (minting is still allowed)
    address[] public navTokens;

    error AmountIsZero();

    mapping(uint256 => mapping(address => uint8)) proposalSupport;

    /// @notice The constructor for the EthStrategyGovernor contract, initializes the governor
    /// @param _quorumPercentage The quorum percentage for the governor
    /// @param _votingDelay The voting delay for the governor (in blocks)
    /// @param _votingPeriod The voting period for the governor (in blocks)
    /// @param _proposalThreshold The proposal threshold for the governor (in tokens)
    constructor(
        uint256 _quorumPercentage,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold,
        uint48 _voteExtension,
        uint256 _timelockDelay
    )
        ERC20("EthStrategy", "ETHXR")
        Governor("EthStrategy")
        GovernorVotes(this)
        GovernorVotesQuorumFraction(_quorumPercentage)
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
        GovernorPreventLateQuorum(_voteExtension)
        GovernorTimelockControl(this)
        TimelockController(_timelockDelay, new address[](0), new address[](0), address(this))
    {
        _grantRole(PROPOSER_ROLE, address(this));
        _grantRole(EXECUTOR_ROLE, address(this));
        _grantRole(MINTER_ROLE, address(this));
        _grantRole(PAUSER_ROLE, address(this));
        _grantRole(NAV_ADMIN_ROLE, address(this));
        _grantRole(DEFAULT_ADMIN_ROLE, address(this));
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _mint(msg.sender, 1);
    }
    /// @inheritdoc Governor

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.votingDelay();
    }
    /// @inheritdoc Governor

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.votingPeriod();
    }
    /// @inheritdoc Governor

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.proposalThreshold();
    }
    /// @inheritdoc Governor

    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override
        returns (uint256)
    {
        proposalSupport[proposalId][account] = support;
        return super._castVote(proposalId, account, support, reason, params);
    }
    /// @inheritdoc GovernorPreventLateQuorum

    function _tallyUpdated(uint256 proposalId) internal override(GovernorPreventLateQuorum, Governor) {
        GovernorPreventLateQuorum._tallyUpdated(proposalId);
    }
    /// @inheritdoc GovernorPreventLateQuorum

    function proposalDeadline(uint256 proposalId)
        public
        view
        override(GovernorPreventLateQuorum, Governor)
        returns (uint256)
    {
        return GovernorPreventLateQuorum.proposalDeadline(proposalId);
    }
    /// @inheritdoc GovernorTimelockControl

    function state(uint256 proposalId)
        public
        view
        override(GovernorTimelockControl, Governor)
        returns (ProposalState)
    {
        return GovernorTimelockControl.state(proposalId);
    }
    /// @inheritdoc GovernorTimelockControl

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(GovernorTimelockControl, Governor)
        returns (bool)
    {
        return GovernorTimelockControl.proposalNeedsQueuing(proposalId);
    }
    /// @inheritdoc GovernorTimelockControl

    function _executor() internal view override(GovernorTimelockControl, Governor) returns (address) {
        return GovernorTimelockControl._executor();
    }
    /// @inheritdoc GovernorTimelockControl

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorTimelockControl, Governor) returns (uint256) {
        return GovernorTimelockControl._cancel(targets, values, calldatas, descriptionHash);
    }
    /// @inheritdoc GovernorTimelockControl

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override(GovernorTimelockControl, Governor) {
        GovernorTimelockControl._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }
    /// @inheritdoc GovernorTimelockControl

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override(GovernorTimelockControl, Governor) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }
    /// @inheritdoc Governor

    function onERC1155Received(address, address, uint256, uint256, bytes memory)
        public
        virtual
        override(ERC1155Holder, Governor)
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }
    /// @inheritdoc Governor

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory)
        public
        virtual
        override(ERC1155Holder, Governor)
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
    /// @inheritdoc Governor

    function onERC721Received(address, address, uint256, bytes memory)
        public
        pure
        override(ERC721Holder, Governor)
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    /// @inheritdoc Governor
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Governor, TimelockController)
        returns (bool)
    {
        return Governor.supportsInterface(interfaceId) || TimelockController.supportsInterface(interfaceId);
    }
    /// @inheritdoc Governor

    receive() external payable virtual override(Governor, TimelockController) {}
    // /// @inheritdoc ERC20

    function name() public view virtual override(Governor, ERC20) returns (string memory) {
        return ERC20.name();
    }
    /// @notice A function to mint tokens, only callable by the owner or roles
    /// @param _to The address to mint the tokens to
    /// @param _amount The amount of tokens to mint

    function mint(address _to, uint256 _amount) public onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }
    /// @inheritdoc ERC20

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && isTransferPaused) {
            revert TransferPaused();
        }
        super._update(from, to, value);
    }
    /// @notice An external function to set the transfer pause status,
    /// @param _isTransferPaused The new transfer pause status

    function setIsTransferPaused(bool _isTransferPaused) public onlyRole(PAUSER_ROLE) {
        isTransferPaused = _isTransferPaused;
    }
    /// @inheritdoc Governor

    function CLOCK_MODE() public view virtual override(Governor, GovernorVotes, Votes) returns (string memory) {
        return "mode=timestamp";
    }
    /// @inheritdoc Governor

    function clock() public view virtual override(Governor, GovernorVotes, Votes) returns (uint48 result) {
        return uint48(block.timestamp);
    }

    function addNavToken(address _navToken) public onlyRole(NAV_ADMIN_ROLE) {
        navTokens.push(_navToken);
    }

    function removeNavToken(address _navToken) public onlyRole(NAV_ADMIN_ROLE) {
        uint256 i = 0;
        uint256 len = navTokens.length;
        for (; i < len;) {
            if (navTokens[i] == _navToken) {
                navTokens[i] = navTokens[len - 1];
                navTokens.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    function getNavValue(uint256 _amount, uint256 _discount) external view returns (NavValue[] memory navValues) {
        return _getNavValue(_amount, _discount);
    }

    function _getNavValue(uint256 _amount, uint256 _discount) internal view returns (NavValue[] memory navValues) {
        if (_amount == 0) {
            revert AmountIsZero();
        }
        uint256 totalSupply = 0;
        navValues = new NavValue[](navTokens.length + 1);
        uint256 i = 0;
        uint256 newLen = 0;
        uint256 len = navTokens.length;
        address _owner = address(this);
        for (; i < len;) {
            address navToken = navTokens[i];
            uint256 _balance = IERC20(navToken).balanceOf(_owner);
            if (_balance != 0) {
                uint256 proportion = (_balance * _amount) / totalSupply;
                if (_balance > 0 && proportion == 0) {
                    proportion = 1;
                }
                if (_discount > 0) {
                    proportion = (proportion * (100 - _discount)) / 100;
                }
                navValues[newLen] = NavValue({token: navToken, value: proportion});
                unchecked {
                    ++newLen;
                }
            }
            unchecked {
                ++i;
            }
        }
        uint256 balance = _owner.balance;
        if (balance > 0) {
            navValues[newLen] = NavValue({token: address(0), value: balance});
            unchecked {
                ++newLen;
            }
        }
        assembly ("memory-safe") {
            mstore(navValues, newLen)
        }
    }

    function rageQuit(uint256 amount, uint256 proposalId) external {
        if (!isTransferPaused) {
            IGovernor.ProposalState _state = state(proposalId);
            if (_state != IGovernor.ProposalState.Queued) {
                revert ProposalNotQueued();
            }
            uint256 timepoint = proposalSnapshot(proposalId);
            address delegate = address(0);
            uint256 balance = getPastBalanceOf(msg.sender, timepoint);
            uint8 support = proposalSupport[proposalId][delegate];
            if (support == uint8(GovernorCountingSimple.VoteType.For)) {
                revert ForVotesCannotRageQuit();
            }
            if (balance < amount) {
                revert AmountExceedsPastBalance();
            }
        }
        NavValue[] memory navValues = _getNavValue(amount, rageQuitPenalty);
        _burn(msg.sender, amount);
        uint256 i;
        uint256 len = navValues.length;
        for (; i < len;) {
            NavValue memory navValue = navValues[i];
            if (navValue.token == address(0)) {
                SafeTransferLib.safeTransferETH(msg.sender, navValue.value);
            } else {
                SafeTransferLib.safeTransfer(navValue.token, msg.sender, navValue.value);
            }
            unchecked {
                ++i;
            }
        }
    }

    function setRageQuitPenalty(uint16 _rageQuitPenalty) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_rageQuitPenalty > 100_00) {
            revert RageQuitPenaltyTooHigh();
        }
        rageQuitPenalty = _rageQuitPenalty;
    }

    function _transferVotingUnits(address from, address to, uint256 amount)
        internal
        virtual
        override(Votes, VotesExtended)
    {
        VotesExtended._transferVotingUnits(from, to, amount);
    }

    function _delegate(address account, address delegatee) internal virtual override(Votes, VotesExtended) {
        VotesExtended._delegate(account, delegatee);
    }
}
