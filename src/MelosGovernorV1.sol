// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {EIP712Upgradeable, ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import {ERC165Upgradeable, IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract MelosGovernorV1 is Initializable, ContextUpgradeable, ERC165Upgradeable, EIP712Upgradeable {
    using SafeCastUpgradeable for uint256;
    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    /**
     * @dev Supported vote types. Matches Governor Bravo ordering.
     */
    enum VoteType {
        Against,
        For,
        Abstain
    }

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    struct Proposal {
        uint256 id;
        string title;
        string description;
        string pdfUri;
        string forumUri;
        address proposer;
        TimersUpgradeable.BlockNumber voteStart;
        TimersUpgradeable.BlockNumber voteEnd;
        bool executed;
        bool canceled;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
    }

    struct ProposalData {
        uint256 id;
        string title;
        string description;
        string pdfUri;
        string forumUri;
        address proposer;
        uint256 snapshot;
        uint256 deadline;
        ProposalState state;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
    }

    struct ProposalVote {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
    }

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    string private _name;

    mapping(uint256 => Proposal) private _proposals;

    uint256 public proposalCount;
    mapping(uint256 => uint256) private _proposalsIdByIndex;

    uint256 public draftProposalCount;
    mapping(uint256 => uint256) private _draftProposalsIdByIndex;

    uint256 private _votingDelay;
    uint256 private _votingPeriod;
    uint256 private _proposalThreshold;

    mapping(uint256 => ProposalVote) private _proposalVotes;

    IVotesUpgradeable public token;

    uint256 private _quorumNumerator;

    /**
     * @dev Emitted when a proposal is created.
     */
    event ProposalCreated(uint256 proposalId, address proposer, uint256 startBlock, uint256 endBlock);

    /**
     * @dev Emitted when a proposal is canceled.
     */
    event ProposalCanceled(uint256 proposalId);

    /**
     * @dev Emitted when a proposal is executed.
     */
    event ProposalExecuted(uint256 proposalId);

    /**
     * @dev Emitted when a vote is cast.
     *
     * Note: `support` values should be seen as buckets. There interpretation depends on the voting module used.
     */
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);

    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);
    event QuorumNumeratorUpdated(uint256 oldQuorumNumerator, uint256 newQuorumNumerator);

    /**
     * @dev Restrict access of functions to the governance executor, which may be the Governor itself or a timelock
     * contract, as specified by {_executor}. This generally means that function with this modifier must be voted on and
     * executed through the governance protocol.
     */
    modifier onlyGovernance() {
        require(_msgSender() == _executor(), "Governor: onlyGovernance");
        _;
    }

    constructor() initializer {}

    function initialize(IVotesUpgradeable _votesToken) public initializer {
        __Governor_init("MelosGovernor");
        _setVotingDelay(
            10 /* 10 block */
        );
        _setVotingPeriod(
            23 /* 300 second */
        );
        _setProposalThreshold(
            10e18 /* 10 vote melos threshold */
        );
        token = _votesToken;
        _updateQuorumNumerator(
            30 /* 30% */
        );
    }

    /**
     * @dev Sets the value for {name} and {version}
     */
    function __Governor_init(string memory name_) internal onlyInitializing {
        __EIP712_init_unchained(name_, version());
        __Governor_init_unchained(name_);
    }

    function __Governor_init_unchained(string memory name_) internal onlyInitializing {
        _name = name_;
    }

    function proposalByIndex(uint256 proposalIndex) public view returns (Proposal memory) {
        return _proposals[_proposalsIdByIndex[proposalIndex]];
    }

    function draftProposalByIndex(uint256 draftProposalIndex) public view returns (Proposal memory) {
        return _proposals[_proposalsIdByIndex[draftProposalIndex]];
    }

    function getProposalList(
        uint256 start,
        uint256 count,
        bool reverse,
        bool draft
    ) external view returns (ProposalData[] memory, uint256) {
        uint256 total = draft ? draftProposalCount : proposalCount;
        if (start > total) {
            return (new ProposalData[](0), total);
        }
        uint256 end;
        if (reverse) {
            start = total - start;
            end = (start > count) ? (start - count) : 0;
            count = start - end;
        } else {
            end = (start + count) > total ? total : (start + count);
            count = end - start;
        }
        ProposalData[] memory tmp = new ProposalData[](count);
        uint256 tmpIndex = 0;
        if (reverse) {
            while ((tmpIndex < count) && start > 0) {
                start--;
                tmp[tmpIndex++] = draft ? getDraftProposalDataByIndex(start) : getProposalDataByIndex(start);
            }
        } else {
            while ((tmpIndex < count) && start < total) {
                start++;
                tmp[tmpIndex++] = draft ? getDraftProposalDataByIndex(start + 1) : getProposalDataByIndex(start + 1);
            }
        }
        return (tmp, total);
    }

    function getProposalData(uint256 _proposalId) public view returns (ProposalData memory) {
        Proposal memory proposal = _proposals[_proposalId];
        return
            ProposalData({
                id: proposal.id,
                title: proposal.title,
                description: proposal.description,
                pdfUri: proposal.pdfUri,
                forumUri: proposal.forumUri,
                proposer: proposal.proposer,
                snapshot: proposal.voteStart.getDeadline(),
                deadline: proposal.voteEnd.getDeadline(),
                state: _state(proposal),
                targets: proposal.targets,
                values: proposal.values,
                calldatas: proposal.calldatas
            });
    }

    function getProposalDataByIndex(uint256 proposalIndex) public view returns (ProposalData memory) {
        return getProposalData(_proposalsIdByIndex[proposalIndex]);
    }

    function getDraftProposalDataByIndex(uint256 draftProposalIndex) public view returns (ProposalData memory) {
        return getProposalData(_draftProposalsIdByIndex[draftProposalIndex]);
    }

    /**
     * @dev Returns the current quorum numerator. See {quorumDenominator}.
     */
    function quorumNumerator() public view virtual returns (uint256) {
        return _quorumNumerator;
    }

    /**
     * @dev Returns the quorum denominator. Defaults to 100, but may be overridden.
     */
    function quorumDenominator() public view virtual returns (uint256) {
        return 100;
    }

    /**
     * @dev Returns the quorum for a block number, in terms of number of votes: `supply * numerator / denominator`.
     */
    function quorum(uint256 blockNumber) public view virtual returns (uint256) {
        return (token.getPastTotalSupply(blockNumber) * quorumNumerator()) / quorumDenominator();
    }

    /**
     * @dev Changes the quorum numerator.
     *
     * Emits a {QuorumNumeratorUpdated} event.
     *
     * Requirements:
     *
     * - Must be called through a governance proposal.
     * - New numerator must be smaller or equal to the denominator.
     */
    function updateQuorumNumerator(uint256 newQuorumNumerator) external virtual onlyGovernance {
        _updateQuorumNumerator(newQuorumNumerator);
    }

    /**
     * @dev Changes the quorum numerator.
     *
     * Emits a {QuorumNumeratorUpdated} event.
     *
     * Requirements:
     *
     * - New numerator must be smaller or equal to the denominator.
     */
    function _updateQuorumNumerator(uint256 newQuorumNumerator) internal virtual {
        require(
            newQuorumNumerator <= quorumDenominator(),
            "GovernorVotesQuorumFraction: quorumNumerator over quorumDenominator"
        );

        uint256 oldQuorumNumerator = _quorumNumerator;
        _quorumNumerator = newQuorumNumerator;

        emit QuorumNumeratorUpdated(oldQuorumNumerator, newQuorumNumerator);
    }

    /**
     * Read the voting weight from the token's built in snapshot mechanism (see {IGovernor-getVotes}).
     */
    function getVotes(address account, uint256 blockNumber) public view virtual returns (uint256) {
        return token.getPastVotes(account, blockNumber);
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure virtual returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /**
     * @dev See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256 proposalId, address account) public view virtual returns (bool) {
        return _proposalVotes[proposalId].hasVoted[account];
    }

    /**
     * @dev Accessor to the internal vote counts.
     */
    function proposalVotes(uint256 proposalId)
        public
        view
        virtual
        returns (
            uint256 againstVotes,
            uint256 forVotes,
            uint256 abstainVotes
        )
    {
        ProposalVote storage proposalvote = _proposalVotes[proposalId];
        return (proposalvote.againstVotes, proposalvote.forVotes, proposalvote.abstainVotes);
    }

    /**
     * @dev See {Governor-_quorumReached}.
     */
    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        ProposalVote storage proposalvote = _proposalVotes[proposalId];

        return quorum(proposalSnapshot(proposalId)) <= proposalvote.forVotes + proposalvote.abstainVotes;
    }

    /**
     * @dev See {Governor-_voteSucceeded}. In this module, the forVotes must be strictly over the againstVotes.
     */
    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        ProposalVote storage proposalvote = _proposalVotes[proposalId];

        return proposalvote.forVotes > proposalvote.againstVotes;
    }

    /**
     * @dev See {Governor-_countVote}. In this module, the support follows the `VoteType` enum (from Governor Bravo).
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight
    ) internal {
        ProposalVote storage proposalvote = _proposalVotes[proposalId];

        require(!proposalvote.hasVoted[account], "GovernorVotingSimple: vote already cast");
        proposalvote.hasVoted[account] = true;

        if (support == uint8(VoteType.Against)) {
            proposalvote.againstVotes += weight;
        } else if (support == uint8(VoteType.For)) {
            proposalvote.forVotes += weight;
        } else if (support == uint8(VoteType.Abstain)) {
            proposalvote.abstainVotes += weight;
        } else {
            revert("GovernorVotingSimple: invalid value for enum VoteType");
        }
    }

    /**
     * @dev See {IGovernor-votingDelay}.
     */
    function votingDelay() public view returns (uint256) {
        return _votingDelay;
    }

    /**
     * @dev See {IGovernor-votingPeriod}.
     */
    function votingPeriod() public view returns (uint256) {
        return _votingPeriod;
    }

    /**
     * @dev See {Governor-proposalThreshold}.
     */
    function proposalThreshold() public view returns (uint256) {
        return _proposalThreshold;
    }

    /**
     * @dev Update the voting delay. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingDelaySet} event.
     */
    function setVotingDelay(uint256 newVotingDelay) public virtual onlyGovernance {
        _setVotingDelay(newVotingDelay);
    }

    /**
     * @dev Update the voting period. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingPeriodSet} event.
     */
    function setVotingPeriod(uint256 newVotingPeriod) public virtual onlyGovernance {
        _setVotingPeriod(newVotingPeriod);
    }

    /**
     * @dev Update the proposal threshold. This operation can only be performed through a governance proposal.
     *
     * Emits a {ProposalThresholdSet} event.
     */
    function setProposalThreshold(uint256 newProposalThreshold) public virtual onlyGovernance {
        _setProposalThreshold(newProposalThreshold);
    }

    /**
     * @dev Internal setter for the voting delay.
     *
     * Emits a {VotingDelaySet} event.
     */
    function _setVotingDelay(uint256 newVotingDelay) internal virtual {
        emit VotingDelaySet(_votingDelay, newVotingDelay);
        _votingDelay = newVotingDelay;
    }

    /**
     * @dev Internal setter for the voting period.
     *
     * Emits a {VotingPeriodSet} event.
     */
    function _setVotingPeriod(uint256 newVotingPeriod) internal virtual {
        // voting period must be at least one block long
        require(newVotingPeriod > 0, "GovernorSettings: voting period too low");
        emit VotingPeriodSet(_votingPeriod, newVotingPeriod);
        _votingPeriod = newVotingPeriod;
    }

    /**
     * @dev Internal setter for the proposal threshold.
     *
     * Emits a {ProposalThresholdSet} event.
     */
    function _setProposalThreshold(uint256 newProposalThreshold) internal virtual {
        emit ProposalThresholdSet(_proposalThreshold, newProposalThreshold);
        _proposalThreshold = newProposalThreshold;
    }

    /**
     * @dev Function to receive ETH that will be handled by the governor (disabled if executor is a third party contract)
     */
    receive() external payable virtual {
        require(_executor() == address(this));
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable) returns (bool) {
        return interfaceId == type(IGovernorUpgradeable).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IGovernor-name}.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IGovernor-version}.
     */
    function version() public view virtual returns (string memory) {
        return "1";
    }

    /**
     * @dev See {IGovernor-state}.
     */
    function state(uint256 proposalId) public view virtual returns (ProposalState) {
        return _state(_proposals[proposalId]);
    }

    function _state(Proposal memory proposal) private view returns (ProposalState) {
        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposal.id);

        if (snapshot == 0) {
            revert("Governor: unknown proposal id");
        }

        if (snapshot >= block.number) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(proposal.id);

        if (deadline >= block.number) {
            return ProposalState.Active;
        }

        if (_quorumReached(proposal.id) && _voteSucceeded(proposal.id)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Defeated;
        }
    }

    /**
     * @dev See {IGovernor-proposalSnapshot}.
     */
    function proposalSnapshot(uint256 proposalId) public view virtual returns (uint256) {
        return _proposals[proposalId].voteStart.getDeadline();
    }

    /**
     * @dev See {IGovernor-proposalDeadline}.
     */
    function proposalDeadline(uint256 proposalId) public view virtual returns (uint256) {
        return _proposals[proposalId].voteEnd.getDeadline();
    }

    /**
     * @dev See {IGovernor-propose}.
     */
    function propose(
        string memory title,
        string memory description,
        string memory pdfUri,
        string memory forumUri,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) public virtual returns (uint256) {
        require(
            getVotes(msg.sender, block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        uint256 proposalId = uint256(keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))));

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal and not a draft");

        require(_proposals[proposalId].voteStart.isUnset(), "Governor: proposal already exists");

        _proposalsIdByIndex[proposalCount++] = proposalId;

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        Proposal storage proposal = _proposals[proposalId];

        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.title = title;
        proposal.description = description;
        proposal.pdfUri = pdfUri;
        proposal.forumUri = forumUri;
        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;

        emit ProposalCreated(proposalId, _msgSender(), snapshot, deadline);

        return proposalId;
    }

    function proposeDraft(
        string memory title,
        string memory description,
        string memory pdfUri,
        string memory forumUri
    ) public virtual returns (uint256) {
        require(
            getVotes(msg.sender, block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        uint256 draftProposalId = uint256(keccak256(bytes(abi.encode("draft", description))));

        Proposal storage draftProposal = _proposals[draftProposalId];
        require(draftProposal.voteStart.isUnset(), "Governor: proposal already exists");

        _draftProposalsIdByIndex[draftProposalCount++] = draftProposalId;

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        draftProposal.id = draftProposalId;
        draftProposal.proposer = msg.sender;
        draftProposal.title = title;
        draftProposal.description = description;
        draftProposal.pdfUri = pdfUri;
        draftProposal.forumUri = forumUri;
        draftProposal.voteStart.setDeadline(snapshot);
        draftProposal.voteEnd.setDeadline(deadline);

        emit ProposalCreated(draftProposalId, _msgSender(), snapshot, deadline);
        return draftProposalId;
    }

    /**
     * @dev See {IGovernor-execute}.
     */
    function execute(uint256 proposalId) public payable virtual returns (uint256) {
        ProposalState status = state(proposalId);
        require(
            status == ProposalState.Succeeded || status == ProposalState.Queued,
            "Governor: proposal not successful"
        );
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        _execute(_proposals[proposalId].targets, _proposals[proposalId].values, _proposals[proposalId].calldatas);

        return proposalId;
    }

    /**
     * @dev Internal execution mechanism. Can be n to implement different execution mechanism
     */
    function _execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal virtual {
        string memory errorMessage = "Governor: call reverted without message";
        for (uint256 i = 0; i < targets.length; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);
            AddressUpgradeable.verifyCallResult(success, returndata, errorMessage);
        }
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed proposals.
     *
     * Emits a {IGovernor-ProposalCanceled} event.
     */
    function _cancel(uint256 proposalId) internal virtual returns (uint256) {
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /**
     * @dev See {IGovernor-castVote}.
     */
    function castVote(uint256 proposalId, uint8 support) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev See {IGovernor-castVoteWithReason}.
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    /**
     * @dev See {IGovernor-castVoteBySig}.
     */
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns (uint256) {
        address voter = ECDSAUpgradeable.recover(
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))),
            v,
            r,
            s
        );
        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason
    ) internal virtual returns (uint256) {
        Proposal storage proposal = _proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        uint256 weight = getVotes(account, proposal.voteStart.getDeadline());
        _countVote(proposalId, account, support, weight);

        emit VoteCast(account, proposalId, support, weight, reason);

        return weight;
    }

    /**
     * @dev Relays a transaction or function call to an arbitrary target. In cases where the governance executor
     * is some contract other than the governor itself, like when using a timelock, this function can be invoked
     * in a governance proposal to recover tokens or Ether that was sent to the governor contract by mistake.
     * Note that if the executor is simply the governor itself, use of `relay` is redundant.
     */
    function relay(
        address target,
        uint256 value,
        bytes calldata data
    ) external virtual onlyGovernance {
        AddressUpgradeable.functionCallWithValue(target, data, value);
    }

    /**
     * @dev Address through which the governor executes action. Will be overloaded by module that execute actions
     * through another contract such as a timelock.
     */
    function _executor() internal view virtual returns (address) {
        return address(this);
    }
}
