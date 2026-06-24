interface ISurplusPool {
    function recordSurplus(uint256 amount) external;
    function recordBadDebt(uint256 amount) external;

    function surplus() external view returns (uint256);
}
