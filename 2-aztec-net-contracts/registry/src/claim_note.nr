use aztec::{macros::notes::note, protocol::traits::{Packable, Serialize, Deserialize}};

/// Historical ENS ownership attestation, immutable and non-transferable in this MVP.
#[derive(Eq, Packable, Serialize, Deserialize)]
#[note]
pub struct ClaimNote {
    pub namehash_hi: u128,
    pub namehash_lo: u128,
    pub claim_key: Field,
}
