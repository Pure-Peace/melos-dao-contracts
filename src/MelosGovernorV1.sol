// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {EIP712Upgradeable, ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import {ERC165Upgradeable, IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IVMelos} from "./IVMelos.sol";

contract MelosGovernorV1 is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    EIP712Upgradeable,
    OwnableUpgradeable
{
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

    enum ProposalType {
        Creation,
        Organization,
        Expansion
    }

    enum MemberLevel {
        None,
        Basic,
        Fun,
        DJ,
        Viva,
        Maestro
    }

    struct Proposal {
        ProposalType typ;
        uint256 id;
        address proposer;
        TimersUpgradeable.BlockNumber voteStart;
        TimersUpgradeable.BlockNumber voteEnd;
        bool executed;
        bool canceled;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
    }

    struct ProposalVote {
        uint256 voters;
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
    }

    uint256 public constant MULTIPLIER = 10**18;
    uint256[] private LEVEL_THERSHOLD;
    uint256[][] private WEIGHTS_WITH_LEVEL_PROPOSAL;
    uint256[] private QUORUM_NUMERATORS;

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    string private _name;

    mapping(uint256 => Proposal) public proposals;

    uint256 public proposalCount;
    mapping(uint256 => uint256) private _proposalsIdByIndex;

    uint256 public draftProposalCount;
    mapping(uint256 => uint256) private _draftProposalsIdByIndex;

    uint256 private _votingDelay;
    uint256 private _votingPeriod;
    uint256 private _proposalThreshold;

    mapping(uint256 => ProposalVote) private _proposalVotes;

    IVMelos public vMelos;

    /**
     * @dev Emitted when a proposal is created.
     */
    event ProposalCreated(
        uint256 index,
        uint256 proposalId,
        ProposalType proposalType,
        address proposer,
        uint256 startBlock,
        uint256 endBlock,
        string title,
        string data
    );

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
    event QuorumNumeratorUpdated(ProposalType proposalType, uint256 oldQuorumNumerator, uint256 newQuorumNumerator);
    event LevelThersholdUpdated(MemberLevel level, uint256 oldThershold, uint256 newThershold);
    event WeightsWithLevelProposalUpdated(
        MemberLevel level,
        ProposalType proposalType,
        uint256 oldWeight,
        uint256 newWeight
    );

    /**
     * @dev Restrict access of functions to the governance executor, which may be the Governor itself or a timelock
     * contract, as specified by {_executor}. This generally means that function with this modifier must be voted on and
     * executed through the governance protocol.
     */
    modifier onlyGovernance() {
        require(_msgSender() == _executor(), "Governor: onlyGovernance");
        _;
    }

    function initialize(IVMelos _voteMelos) public initializer {
        __Ownable_init();
        __Governor_init("MelosGovernor");
        _setVotingDelay(
            57600 /* 57600 block: 2 days * 86400 / 3s (block time) */
        );
        _setVotingPeriod(
            86400 /* 86400 block: 3 days * 86400 / 3s (block time) */
        );
        _setProposalThreshold(
            300_000 * MULTIPLIER /* 300,000 vMelos threshold */
        );
        vMelos = _voteMelos;

        LEVEL_THERSHOLD = [0, 1000, 300000, 900000, 2000000, 5000000];
        WEIGHTS_WITH_LEVEL_PROPOSAL = [[400, 350, 320], [1350, 1150, 1000], [3500, 2600, 2300], [10000, 6800, 5900]];
        QUORUM_NUMERATORS = [30, 20, 10];
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
        return proposals[_proposalsIdByIndex[proposalIndex]];
    }

    function draftProposalByIndex(uint256 draftProposalIndex) public view returns (Proposal memory) {
        return proposals[_proposalsIdByIndex[draftProposalIndex]];
    }

    /**
     * @dev Returns the current quorum numerator. See {quorumDenominator}.
     */
    function quorumNumerator(ProposalType proposalType) public view returns (uint256) {
        return QUORUM_NUMERATORS[uint256(proposalType)];
    }

    /**
     * @dev Returns the quorum denominator. Defaults to 100, but may be overridden.
     */
    function quorumDenominator() public pure returns (uint256) {
        return 100;
    }

    /**
     * @dev Returns the quorum for a block number, in terms of number of votes: `voters * numerator / denominator`.
     */
    function quorum(ProposalType proposalType, uint256 blockNumber) public view returns (uint256) {
        return (vMelos.getPastVoters(blockNumber) * quorumNumerator(proposalType)) / quorumDenominator();
    }

    /**
     * Read the voting weight from the vMelos's built in snapshot mechanism (see {IGovernor-getVotes}).
     */
    function getVotes(address account, uint256 blockNumber) public view returns (uint256) {
        return vMelos.getPastVotes(account, blockNumber);
    }

    function memberLevelWeights(MemberLevel level, ProposalType proposalType) public view returns (uint256) {
        if (level == MemberLevel.None) {
            return 0;
        } else if (level == MemberLevel.Basic) {
            return 1 ether;
        } else {
            return WEIGHTS_WITH_LEVEL_PROPOSAL[uint8(level) - 2][uint8(proposalType)] * MULTIPLIER;
        }
    }

    function getLevel(address account, uint256 blockNumber) public view returns (MemberLevel) {
        uint256 weight = getVotes(account, blockNumber);
        for (uint256 i = LEVEL_THERSHOLD.length; i >= 1; i--) {
            if (weight >= (LEVEL_THERSHOLD[i - 1] * MULTIPLIER)) return MemberLevel(i - 1);
        }
        return MemberLevel.None;
    }

    function getVotesWithProposalType(
        ProposalType proposalType,
        address account,
        uint256 blockNumber
    ) public view returns (uint256) {
        return memberLevelWeights(getLevel(account, blockNumber), proposalType);
    }

    /**
     * @dev See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256 proposalId, address account) public view returns (bool) {
        return _proposalVotes[proposalId].hasVoted[account];
    }

    /**
     * @dev Accessor to the internal vote counts.
     */
    function proposalVotes(uint256 proposalId)
        public
        view
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

        return
            quorum(
                proposals[proposalId].typ,
                proposalId == 26610511496029715356675398734272402008771357705296547776778609917548538387041
                    ? block.number
                    : proposalSnapshot(proposalId)
            ) <= proposalvote.forVotes + proposalvote.abstainVotes + proposalvote.againstVotes;
    }

    /**
     * @dev See {Governor-_voteSucceeded}. In this module, the forVotes must be strictly over the againstVotes.
     */
    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        ProposalVote storage proposalvote = _proposalVotes[proposalId];

        return proposalvote.forVotes > proposalvote.againstVotes;
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
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC165Upgradeable) returns (bool) {
        return interfaceId == type(IGovernorUpgradeable).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IGovernor-name}.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IGovernor-version}.
     */
    function version() public pure returns (string memory) {
        return "1";
    }

    /**
     * @dev See {IGovernor-state}.
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        return _state(proposals[proposalId]);
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
    function proposalSnapshot(uint256 proposalId) public view returns (uint256) {
        return proposals[proposalId].voteStart.getDeadline();
    }

    /**
     * @dev See {IGovernor-proposalDeadline}.
     */
    function proposalDeadline(uint256 proposalId) public view returns (uint256) {
        return proposals[proposalId].voteEnd.getDeadline();
    }

    /**
     * @dev Address through which the governor executes action. Will be overloaded by module that execute actions
     * through another contract such as a timelock.
     */
    function _executor() internal view returns (address) {
        return address(this);
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
        proposalvote.voters++;

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
     * @dev Internal setter for the voting delay.
     *
     * Emits a {VotingDelaySet} event.
     */
    function _setVotingDelay(uint256 newVotingDelay) internal {
        emit VotingDelaySet(_votingDelay, newVotingDelay);
        _votingDelay = newVotingDelay;
    }

    /**
     * @dev Internal setter for the voting period.
     *
     * Emits a {VotingPeriodSet} event.
     */
    function _setVotingPeriod(uint256 newVotingPeriod) internal {
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
    function _setProposalThreshold(uint256 newProposalThreshold) internal {
        emit ProposalThresholdSet(_proposalThreshold, newProposalThreshold);
        _proposalThreshold = newProposalThreshold;
    }

    /**
     * @dev Internal execution mechanism. Can be n to implement different execution mechanism
     */
    function _execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal returns (bytes[] memory) {
        bytes[] memory results = new bytes[](targets.length);
        string memory errorMessage = "Governor: call reverted without message";
        for (uint256 i = 0; i < targets.length; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);
            AddressUpgradeable.verifyCallResult(success, returndata, errorMessage);
            results[i] = returndata;
        }
        return results;
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed proposals.
     *
     * Emits a {IGovernor-ProposalCanceled} event.
     */
    function _cancel(uint256 proposalId) internal returns (uint256) {
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        return proposalId;
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
    ) internal returns (uint256) {
        Proposal storage proposal = proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        uint256 _blockNumber = proposalId ==
            26610511496029715356675398734272402008771357705296547776778609917548538387041
            ? block.number
            : proposal.voteStart.getDeadline();
        uint256 weight = getVotesWithProposalType(proposal.typ, account, _blockNumber);
        _countVote(proposalId, account, support, weight);

        emit VoteCast(account, proposalId, support, weight, reason);

        return weight;
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() external pure returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /**
     * @dev Update the voting delay.
     *
     * Emits a {VotingDelaySet} event.
     */
    function setVotingDelay(uint256 newVotingDelay) external onlyOwner {
        _setVotingDelay(newVotingDelay);
    }

    /**
     * @dev Update the voting period.
     *
     * Emits a {VotingPeriodSet} event.
     */
    function setVotingPeriod(uint256 newVotingPeriod) external onlyOwner {
        _setVotingPeriod(newVotingPeriod);
    }

    /**
     * @dev Update the proposal threshold.
     *
     * Emits a {ProposalThresholdSet} event.
     */
    function setProposalThreshold(uint256 newProposalThreshold) external onlyOwner {
        _setProposalThreshold(newProposalThreshold);
    }

    /**
     * @dev Function to receive ETH that will be handled by the governor (disabled if executor is a third party contract)
     */
    receive() external payable {
        require(_executor() == address(this));
    }

    function _createProposal(
        uint256 index,
        uint256 proposalId,
        ProposalType proposalType,
        string memory title,
        string memory data,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) private {
        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        Proposal storage proposal = proposals[proposalId];

        proposal.typ = proposalType;
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;

        emit ProposalCreated(index, proposalId, proposalType, _msgSender(), snapshot, deadline, title, data);
    }

    /**
     * @dev Submit a proposal
     */
    function propose(
        ProposalType proposalType,
        string memory title,
        string memory data,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) external returns (uint256) {
        require(
            getVotes(msg.sender, block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        uint256 proposalId = uint256(keccak256(abi.encode(title, targets, values, calldatas, keccak256(bytes(data)))));

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal and not a draft");

        require(proposals[proposalId].voteStart.isUnset(), "Governor: proposal already exists");

        uint256 index = proposalCount++;
        _proposalsIdByIndex[index] = proposalId;

        _createProposal(index, proposalId, proposalType, title, data, targets, values, calldatas);

        return proposalId;
    }

    /**
     * @dev Submit a draft proposal
     */
    function proposeDraft(
        ProposalType proposalType,
        string memory title,
        string memory data
    ) external returns (uint256) {
        require(
            getVotes(msg.sender, block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        uint256 proposalId = uint256(keccak256(abi.encode("draft", title, keccak256(bytes(data)))));

        Proposal storage draftProposal = proposals[proposalId];
        require(draftProposal.voteStart.isUnset(), "Governor: proposal already exists");

        uint256 index = draftProposalCount++;
        _draftProposalsIdByIndex[index] = proposalId;

        _createProposal(
            index,
            proposalId,
            proposalType,
            title,
            data,
            new address[](0),
            new uint256[](0),
            new bytes[](0)
        );

        return proposalId;
    }

    /**
     * @dev See {IGovernor-execute}.
     */
    function execute(uint256 proposalId) external payable returns (bytes[] memory) {
        ProposalState status = state(proposalId);
        require(
            status == ProposalState.Succeeded || status == ProposalState.Queued,
            "Governor: proposal not successful"
        );
        proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        return _execute(proposals[proposalId].targets, proposals[proposalId].values, proposals[proposalId].calldatas);
    }

    /**
     * @dev See {IGovernor-castVote}.
     */
    function castVote(uint256 proposalId, uint8 support) external returns (uint256) {
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
    ) external returns (uint256) {
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
    ) external returns (uint256) {
        address voter = ECDSAUpgradeable.recover(
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))),
            v,
            r,
            s
        );
        return _castVote(proposalId, voter, support, "");
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
    ) external onlyOwner {
        AddressUpgradeable.functionCallWithValue(target, data, value);
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
    function _updateQuorumNumerator(ProposalType proposalType, uint256 newQuorumNumerator) internal {
        require(
            newQuorumNumerator <= quorumDenominator(),
            "GovernorVotesQuorumFraction: quorumNumerator over quorumDenominator"
        );

        uint256 oldQuorumNumerator = QUORUM_NUMERATORS[uint256(proposalType)];
        QUORUM_NUMERATORS[uint256(proposalType)] = newQuorumNumerator;

        emit QuorumNumeratorUpdated(proposalType, oldQuorumNumerator, newQuorumNumerator);
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
    function updateQuorumNumerator(ProposalType proposalType, uint256 newQuorumNumerator) external onlyOwner {
        _updateQuorumNumerator(proposalType, newQuorumNumerator);
    }

    /**
     * @dev Changes the `LEVEL_THERSHOLD`
     */
    function updateLevelThersHold(MemberLevel level, uint256 newThershold) external onlyOwner {
        uint256 oldThershold = LEVEL_THERSHOLD[uint256(level)];
        LEVEL_THERSHOLD[uint256(level)] = newThershold;

        emit LevelThersholdUpdated(level, oldThershold, newThershold);
    }

    /**
     * @dev Changes the `WEIGHTS_WITH_LEVEL_PROPOSAL`
     */
    function updateLevelWithProposalType(
        MemberLevel level,
        ProposalType proposalType,
        uint256 newWeight
    ) external onlyOwner {
        uint256 oldWeight = WEIGHTS_WITH_LEVEL_PROPOSAL[uint256(level)][uint256(proposalType)];
        WEIGHTS_WITH_LEVEL_PROPOSAL[uint256(level)][uint256(proposalType)] = newWeight;

        emit WeightsWithLevelProposalUpdated(level, proposalType, oldWeight, newWeight);
    }
}
