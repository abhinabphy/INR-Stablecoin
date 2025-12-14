// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*
 * Production-style custom INR/USD oracle
 * - Feeds price of 1 USD in INR with 8 decimals
 * - Access-controlled submitter(s)
 * - Chainlink AggregatorV3-compatible interface
 *
 * NOTES:
 * - Use a multisig (e.g. Safe) as DEFAULT_ADMIN_ROLE for production.
 * - Have your off-chain bot call submitPrice() from an ORACLE_ROLE address.
 */

interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/**
 * Minimal AccessControl-like pattern to avoid external deps.
 * (If you prefer OpenZeppelin, you can replace this with OZ AccessControl.)
 */
abstract contract SimpleAccessControl {
    mapping(bytes32 => mapping(address => bool)) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "ACCESS_CONTROL: missing role");
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(bytes32 role, address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }
}

contract InrUsdOracle is IAggregatorV3, SimpleAccessControl {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    // 1 USD in INR, with 8 decimals. Example: 83.51230000 INR = 8_351_230_000
    uint8 private constant _DECIMALS = 8;
    string private constant _DESCRIPTION = "INR / USD Oracle (1 USD in INR, 8 decimals)";
    uint256 private constant _VERSION = 1;

    struct Round {
        int256 answer;          // price
        uint256 startedAt;      // when submission for this round started (we set = updatedAt)
        uint256 updatedAt;      // when it was last updated
        uint80 answeredInRound; // round in which answer was computed
    }

    mapping(uint80 => Round) private _rounds;
    uint80 private _latestRoundId;

    event AnswerUpdated(
        int256 indexed current,
        uint80 indexed roundId,
        uint256 updatedAt
    );

    constructor(address initialOracle) {
        // Deployer is admin (from SimpleAccessControl constructor)
        // Optionally grant ORACLE_ROLE to an initial submitter
        if (initialOracle != address(0)) {
            _grantRole(ORACLE_ROLE, initialOracle);
        }
    }

    // ------------------ Admin / Oracle management ------------------

    function addOracle(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "invalid oracle");
        _grantRole(ORACLE_ROLE, account);
    }

    function removeOracle(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ORACLE_ROLE, account);
    }

    // ------------------ Price submission ------------------

    /**
     * @notice Submit new price
     * @param _answer Price of 1 USD in INR, with 8 decimals
     *        e.g., 83.51230000 INR => 8_351_230_000
     */
    function submitPrice(int256 _answer) external onlyRole(ORACLE_ROLE) {
        require(_answer > 0, "invalid price");

        uint80 newRoundId = _latestRoundId + 1;
        uint256 time = block.timestamp;

        _rounds[newRoundId] = Round({
            answer: _answer,
            startedAt: time,
            updatedAt: time,
            answeredInRound: newRoundId
        });

        _latestRoundId = newRoundId;

        emit AnswerUpdated(_answer, newRoundId, time);
    }

    // ------------------ AggregatorV3-style interface ------------------

    function decimals() external pure override returns (uint8) {
        return _DECIMALS;
    }

    function description() external pure override returns (string memory) {
        return _DESCRIPTION;
    }

    function version() external pure override returns (uint256) {
        return _VERSION;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        Round memory r = _rounds[_roundId];
        require(r.updatedAt != 0, "no data for round");

        return (_roundId, r.answer, r.startedAt, r.updatedAt, r.answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = _latestRoundId;
        require(roundId != 0, "no data");

        Round memory r = _rounds[roundId];
        return (roundId, r.answer, r.startedAt, r.updatedAt, r.answeredInRound);
    }

    // ------------------ Extra helpers for consumers ------------------

    /// @notice Returns latest price only (reverts if none)
    function latestAnswer() external view returns (int256) {
        uint80 roundId = _latestRoundId;
        require(roundId != 0, "no data");
        return _rounds[roundId].answer;
    }

    /// @notice Last update timestamp (0 if no data)
    function latestTimestamp() external view returns (uint256) {
        uint80 roundId = _latestRoundId;
        if (roundId == 0) return 0;
        return _rounds[roundId].updatedAt;
    }

    /// @notice Check if data is stale vs a max allowed age
    /// @param maxAgeSeconds maximum allowed age in seconds
    function isStale(uint256 maxAgeSeconds) external view returns (bool) {
        uint80 roundId = _latestRoundId;
        if (roundId == 0) return true;

        uint256 updatedAt = _rounds[roundId].updatedAt;
        return block.timestamp > updatedAt + maxAgeSeconds;
    }
}

