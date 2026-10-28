use aztec::protocol::{
    address::AztecAddress,
    hash::{poseidon2_hash, sha256_to_field},
    traits::ToField,
};

pub global TREE_DEPTH: u32 = 8;
global CLAIM_KEY_DOMAIN: Field = 0x4e4f49524e414d455f434c41494d5f5631;
global LEAF_DOMAIN: Field = 0x4e4f49524e414d455f4c4541465f5631;
global BRANCH_DOMAIN: Field = 0x4e4f49524e414d455f4252414e43485f5631;
global ONCE_DOMAIN: Field = 0x4e4f49524e414d455f4f4e43455f5631;
global PSEUDONYM_DOMAIN: Field = 0x4e4f49524e414d455f50534555445f5631;
global WITNESS_DOMAIN: Field = 0x4e4f49524e414d455f5749544e4553535f5631;

/// Exact content preimage used by NamePortal.sol at repository commit
/// de3341863e1daa47c12276fc29a12037dc3d9ebd:
/// abi.encodeWithSignature("mint_to_private(bytes32)", namehash).
pub fn portal_content(namehash_hi: u128, namehash_lo: u128) -> Field {
    // First four bytes of keccak256("mint_to_private(bytes32)").
    let selector: [u8; 4] = [0xda, 0x0f, 0x86, 0xf1];
    let hi: [u8; 16] = (namehash_hi as Field).to_be_bytes();
    let lo: [u8; 16] = (namehash_lo as Field).to_be_bytes();
    sha256_to_field(selector.concat(hi).concat(lo))
}

pub fn claim_key(secret: Field, leaf_index: Field, hi: u128, lo: u128) -> Field {
    poseidon2_hash(
        [CLAIM_KEY_DOMAIN, secret, leaf_index, hi as Field, lo as Field],
    )
}

pub fn allowlist_leaf(hi: u128, lo: u128) -> Field {
    poseidon2_hash([LEAF_DOMAIN, hi as Field, lo as Field])
}

pub fn branch(left: Field, right: Field) -> Field {
    poseidon2_hash([BRANCH_DOMAIN, left, right])
}

pub fn membership_root(hi: u128, lo: u128, index: u32, siblings: [Field; TREE_DEPTH]) -> Field {
    assert(index < 256, "allowlist index out of range");
    let mut value = allowlist_leaf(hi, lo);
    for level in 0..TREE_DEPTH {
        value = if ((index >> level) & 1) == 0 {
            branch(value, siblings[level])
        } else {
            branch(siblings[level], value)
        };
    }
    value
}

pub fn action_nullifier(
    key: Field,
    chain_id: Field,
    version: Field,
    app: AztecAddress,
    scope: Field,
) -> Field {
    poseidon2_hash([ONCE_DOMAIN, key, chain_id, version, app.to_field(), scope])
}

pub fn app_pseudonym(key: Field, chain_id: Field, version: Field, app: AztecAddress) -> Field {
    poseidon2_hash([PSEUDONYM_DOMAIN, key, chain_id, version, app.to_field()])
}

pub fn witness_slot(app: AztecAddress, scope: Field, nonce: Field) -> Field {
    poseidon2_hash([WITNESS_DOMAIN, app.to_field(), scope, nonce])
}
