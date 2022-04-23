// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface ICurveGauge {

    function minter() external view returns (address);
    function crv_token() external view returns (address);
    function lp_token() external view returns (address);
    function controller() external view returns (address);
    function voting_escrow() external view returns (address);
    function future_epoch_time() external view returns (uint256);
    function reward_tokens(uint256 i) external view returns (address);

    function user_checkpoint(address addr) external returns (bool);
    function claimable_tokens(address addr) external view returns (uint256);
    function claimable_reward(address addr) external view returns (uint256);

    function claim_rewards() external;
    function claim_historic_rewards(address[8] calldata _reward_tokens) external;
    function kick(address addr) external;
    function set_approve_deposit(address addr, bool can_deposit) external;

    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external;

}
