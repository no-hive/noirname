// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.27;

import {IRegistry} from "@aztec/governance/interfaces/IRegistry.sol";
import {IInbox} from "@aztec/core/interfaces/messagebridge/IInbox.sol";
import {IRollup} from "@aztec/core/interfaces/IRollup.sol";
import {DataStructures} from "@aztec/core/libraries/DataStructures.sol";
import {Hash} from "@aztec/core/libraries/crypto/Hash.sol";

interface IENSRegistry {
    function owner(bytes32 node) external view returns (address);
}

interface INameWrapper {
    function ownerOf(uint256 id) external view returns (address);
}

contract NamePortal {
    error NotNameOwner();
    error AlreadyInitialized();
    error NotDeployer();

    IENSRegistry public constant REGISTRY = IENSRegistry(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
    INameWrapper public constant WRAPPER = INameWrapper(0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401);

    address public immutable deployer;
    bool public isInitialized;

    IRegistry public registry;
    bytes32 public l2Bridge;

    IRollup public rollup;
    IInbox public inbox;
    uint256 public rollupVersion;

    constructor() {
        deployer = msg.sender;
    }

    function initialize(address _registry, bytes32 _l2Bridge) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (isInitialized) revert AlreadyInitialized();
        isInitialized = true;

        registry = IRegistry(_registry);
        l2Bridge = _l2Bridge;

        rollup = IRollup(address(registry.getCanonicalRollup()));
        inbox = rollup.getInbox();
        rollupVersion = rollup.getVersion();
    }

    function enter_noirname(bytes32 _nameHash, bytes32 _secretHash) external returns (bool) {
        if (msg.sender != check_owner(_nameHash)) revert NotNameOwner();
        depositToAztecPrivate(_nameHash, _secretHash);
        return true;
    }

    function depositToAztecPrivate(bytes32 _nameHash, bytes32 _secretHash) internal returns (bytes32, uint256) {
        DataStructures.L2Actor memory actor = DataStructures.L2Actor(l2Bridge, rollupVersion);

        bytes32 contentHash = Hash.sha256ToField(abi.encodeWithSignature("mint_to_private(bytes32)", _nameHash));

        return inbox.sendL2Message(actor, contentHash, _secretHash);
    }

    function check_owner(bytes32 node) internal view returns (address owner) {
        owner = REGISTRY.owner(node);
        if (owner == address(WRAPPER)) {
            owner = WRAPPER.ownerOf(uint256(node));
        }
    }
}
