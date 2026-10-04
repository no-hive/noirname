// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.27;

// -----------------------------
// IMPORTS
// -----------------------------

import {IRegistry} from "@aztec/governance/interfaces/IRegistry.sol";
import {IInbox} from "@aztec/core/interfaces/messagebridge/IInbox.sol";
import {IRollup} from "@aztec/core/interfaces/IRollup.sol";
import {DataStructures} from "@aztec/core/libraries/DataStructures.sol";
import {Hash} from "@aztec/core/libraries/crypto/Hash.sol";

// -----------------------------
// INTERFACES
// -----------------------------

/// @notice Minimal ENS registry interface (only what the portal needs).
interface IENSRegistry {
    /// @notice Returns the owner of an ENS node as recorded in the registry.
    /// @param node The namehash of the ENS name.
    /// @return The registry owner (for wrapped names this is the NameWrapper contract).
    function owner(bytes32 node) external view returns (address);
}

/// @notice Minimal ENS NameWrapper interface (ERC-1155 style ownership of wrapped names).
interface INameWrapper {
    /// @notice Returns the real owner of a wrapped name.
    /// @param id The token id of the wrapped name (equals uint256(namehash)).
    /// @return The address that owns the wrapped name.
    function ownerOf(uint256 id) external view returns (address);
}

// -----------------------------
// CONTRACT
// -----------------------------

/// @title NamePortal
/// @notice L1 entry point of the NoirName bridge: lets the owner of an ENS name
///         send a message to Aztec so that the L2 bridge mints a private
///         "proof of ownership" for that name.
/// @dev NoirBridge is the first part of the NoirName private-proofs system for
///      ENS and GWEI names. This contract is supposed to live on Ethereum Mainnet:
///      its dependencies (ENS registry, NameWrapper) only make sense there.
///      Flow: owner calls `enter_noirname` -> ownership is verified on L1 ->
///      message is pushed into the Aztec Inbox -> L2 bridge consumes it with
///      the secret and mints the name privately to the secret holder.
///      Wired to the canonical Aztec rollup once, via `initialize`.
///      STATUS: ENS is implemented, GWEI is on the roadmap.
contract NamePortal {
    // -----------------------------
    // ERRORS
    // -----------------------------

    /// @notice Thrown when the caller is not the owner of the given ENS name.
    error NotNameOwner();
    /// @notice Thrown when `initialize` is called a second time.
    error AlreadyInitialized();
    /// @notice Thrown when `initialize` is called by anyone except the deployer.
    error NotDeployer();

    // -----------------------------
    // DATA STORAGE
    // -----------------------------

    /// @notice ENS registry (mainnet address).
    IENSRegistry public constant REGISTRY = IENSRegistry(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);

    /// @notice ENS NameWrapper (mainnet address); owns the registry record of wrapped names.
    INameWrapper public constant WRAPPER = INameWrapper(0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401);

    /// @notice Address allowed to call `initialize`.
    address public immutable deployer;

    /// @notice True once `initialize` has been executed.
    bool public isInitialized;

    /// @notice Aztec governance registry, used to find the canonical rollup.
    IRegistry public registry;

    /// @notice Address of the L2 bridge contract on Aztec (the recipient of our messages).
    bytes32 public l2Bridge;

    /// @notice Canonical Aztec rollup resolved at initialization time.
    IRollup public rollup;

    /// @notice Rollup's Inbox, where L1 -> L2 messages are sent.
    IInbox public inbox;

    /// @notice Rollup version; part of the L2 actor identity the message is addressed to.
    uint256 public rollupVersion;

    // -----------------------------
    // INITIALIZATION
    // -----------------------------

    /// @notice Records the deployer, who is the only one allowed to call `initialize`.
    constructor() {
        deployer = msg.sender;
    }

    /// @notice One-time setup: links the portal to the Aztec rollup and the L2 bridge.
    /// @dev Done outside the constructor because the L2 bridge address is only known
    ///      after the L2 contract is deployed, which itself needs this portal's address.
    /// @param _registry Address of the Aztec governance registry.
    /// @param _l2Bridge Address of the L2 bridge contract on Aztec.
    function initialize(address _registry, bytes32 _l2Bridge) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (isInitialized) revert AlreadyInitialized();
        // Set the flag first so the function can never be re-run.
        isInitialized = true;

        registry = IRegistry(_registry);
        l2Bridge = _l2Bridge;

        // Resolve everything else from the canonical rollup so we don't trust extra inputs.
        rollup = IRollup(address(registry.getCanonicalRollup()));
        inbox = rollup.getInbox();
        rollupVersion = rollup.getVersion();
    }

    // -----------------------------
    // 0 - ENTRY POINT
    // -----------------------------

    /// @notice Proves ENS name ownership on L1 and requests a private mint of that name on Aztec.
    /// @dev Only the current owner (resolved through `check_owner`) can enter a name.
    ///      The L2 bridge later claims the message with the preimage of `_secretHash`.
    /// @param _nameHash ENS namehash of the name being bridged.
    /// @param _secretHash Hash of a secret chosen by the caller; whoever knows the secret
    ///        can claim the minted name privately on L2, so the L1 address is not linked to it.
    /// @return True if the message was sent (reverts otherwise).
    function enter_noirname(bytes32 _nameHash, bytes32 _secretHash) external returns (bool) {
        // Ownership check: caller must really own the name (wrapped or not).
        if (msg.sender != check_owner(_nameHash)) revert NotNameOwner();
        // Ownership confirmed -> notify L2.
        depositToAztecPrivate(_nameHash, _secretHash);
        return true;
    }

    // -----------------------------
    // 1.1 - ENS FUNCTIONS
    // -----------------------------

    /// @notice Resolves the real owner of an ENS name, handling NameWrapper-wrapped names.
    /// @dev For wrapped names the registry owner is the NameWrapper contract itself,
    ///      so the actual owner has to be read from the wrapper (token id = namehash).
    /// @param node ENS namehash of the name.
    /// @return owner The effective owner of the name.
    function check_owner(bytes32 node) internal view returns (address owner) {
        owner = REGISTRY.owner(node);
        // Wrapped name: registry points to the wrapper, ask the wrapper for the real owner.
        if (owner == address(WRAPPER)) {
            owner = WRAPPER.ownerOf(uint256(node));
        }
    }

    // -----------------------------
    // 1.2 - GWEI FUNCTIONS
    // -----------------------------

    // TODO: GWEI ownership checks (coming soon).

    // -----------------------------
    // 2 - BRIDGE TO AZTEC
    // -----------------------------

    /// @notice Sends the "mint to private" message to the L2 bridge through the Aztec Inbox.
    /// @dev The content hash must match exactly what the L2 bridge expects when it consumes
    ///      the message (same function signature and argument), otherwise the claim fails.
    /// @param _nameHash ENS namehash that will be minted on L2.
    /// @param _secretHash Hash of the claim secret (keeps the recipient private on L2).
    /// @return The message hash (leaf) in the Inbox tree.
    /// @return The index of the message in the Inbox tree.
    function depositToAztecPrivate(bytes32 _nameHash, bytes32 _secretHash) internal returns (bytes32, uint256) {
        // Recipient on L2: the bridge contract, on this specific rollup version.
        DataStructures.L2Actor memory actor = DataStructures.L2Actor(l2Bridge, rollupVersion);

        // Message content = hash of the L2 call we want performed. sha256ToField truncates
        // the digest so it fits into Aztec's field element.
        bytes32 contentHash = Hash.sha256ToField(abi.encodeWithSignature("mint_to_private(bytes32)", _nameHash));

        // Push the message into the Inbox; the secret hash gates who can consume it on L2.
        return inbox.sendL2Message(actor, contentHash, _secretHash);
    }
}
