// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface ICurveMinter {
    function token() external view returns (address);
    function mint(address gauge_addr) external;
}
