use aztec::protocol::{address::AztecAddress, traits::FromField};
use noirname_registry::hashes;
mod integration;

#[test]
fn domain_separation() {
    let app = AztecAddress::from_field(10);
    let other = AztecAddress::from_field(11);
    let key = hashes::claim_key(7, 8, 9, 10);
    assert(
        hashes::action_nullifier(key, 1, 1, app, 1) != hashes::action_nullifier(key, 1, 1, app, 2),
    );
    assert(
        hashes::action_nullifier(key, 1, 1, app, 1)
            != hashes::action_nullifier(key, 1, 1, other, 1),
    );
    assert(
        hashes::action_nullifier(key, 1, 1, app, 1) != hashes::action_nullifier(key, 2, 1, app, 1),
    );
    assert(hashes::app_pseudonym(key, 1, 1, app) != hashes::app_pseudonym(key, 1, 1, other));
    assert(hashes::app_pseudonym(key, 1, 1, app) != hashes::action_nullifier(key, 1, 1, app, 0));
}

#[test]
fn full_namehash_is_committed() {
    // Independently generated using viem ABI encoding and SHA-256, then digest >> 8.
    assert_eq(
        hashes::portal_content(1, 2),
        0x007cfca024f07b2d95f7eec4c82c3e5bf498b31a7936346eb2ab64611ae921d0,
    );
    assert(hashes::portal_content(1, 2) != hashes::portal_content(2, 2));
    assert(hashes::portal_content(1, 2) != hashes::portal_content(1, 3));
    // A high bit beyond one BN254 Field is preserved.
    assert(hashes::portal_content(1 << 127, 0) != hashes::portal_content(0, 0));
}

#[test]
fn ordered_membership_tree() {
    let siblings = [0; 8];
    assert(
        hashes::membership_root(1, 2, 0, siblings) != hashes::membership_root(1, 2, 1, siblings),
    );
    assert(
        hashes::membership_root(1, 2, 0, siblings) != hashes::membership_root(1, 3, 0, siblings),
    );
}

#[test(should_fail_with = "allowlist index out of range")]
fn rejects_truncated_leaf_index() {
    let _ = hashes::membership_root(1, 2, 256, [0; 8]);
}
