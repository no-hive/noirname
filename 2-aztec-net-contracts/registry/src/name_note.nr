use aztec::{macros::notes::note, protocol::traits::{Packable, Serialize, Deserialize}};

/// Private display metadata. Clients MUST verify the decoded ENS namehash against ClaimNote.
/// Three 31-byte field words per chunk keep encrypted notes below the private log limit.
#[derive(Eq, Packable, Serialize, Deserialize)]
#[note]
pub struct NameNote {
    pub claim_key: Field,
    pub part: u32,
    pub byte_length: u32,
    pub words: [Field; 3],
}
