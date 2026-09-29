// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IENSRegistry {
    function owner(bytes32 node) external view returns (address);
}

interface INameWrapper {
    function ownerOf(uint256 id) external view returns (address);
}

contract NameBridge {
    error NotNameOwner();

    IENSRegistry public constant REGISTRY = IENSRegistry(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
    INameWrapper public constant WRAPPER = INameWrapper(0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401);

    function enter_noirname(bytes32 node) external view returns (bool) {
        if (msg.sender != check_owner(node)) revert NotNameOwner();
        return true;
    }

    function check_owner(bytes32 node) internal view returns (address owner) {
        owner = REGISTRY.owner(node);
        if (owner == address(WRAPPER)) {
            owner = WRAPPER.ownerOf(uint256(node));
        }
    }
}
