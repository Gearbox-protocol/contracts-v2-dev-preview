// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.10;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {AddressProvider} from "../core/AddressProvider.sol";
import {ACL} from "../core/ACL.sol";
import {ACLTrait} from "../core/ACLTrait.sol";
import {NotImplementedException} from "../interfaces/IErrors.sol";

import "hardhat/console.sol";

contract GearboxDegenNFT is ERC721, ACLTrait {
    error GearboxDegenManagersOnlyException();

    // addresses who can mint
    mapping(address => bool) managers;

    modifier managersOnly() {
        if (!managers[msg.sender]) {
            revert GearboxDegenManagersOnlyException();
        }
        _;
    }

    constructor(address _addressProvider)
        ACLTrait(_addressProvider)
        ERC721("Gearbox Degen NFT", "GEAR-DEGEN")
    {
        address root = ACL(AddressProvider(_addressProvider).getACL()).owner();
        managers[root] = true;
    }

    function mint(address to, uint256 tokenId) external managersOnly {
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) external managersOnly {
        _burn(tokenId);
    }

    function addManager(address _manager) external configuratorOnly {
        managers[_manager] = true;
    }

    function removeManager(address _manager) external configuratorOnly {
        managers[_manager] = false;
    }

    function approve(address to, uint256 tokenId) public override {
        revert NotImplementedException();
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override
    {
        revert NotImplementedException();
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        revert NotImplementedException();
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        revert NotImplementedException();
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override {
        revert NotImplementedException();
    }
}
