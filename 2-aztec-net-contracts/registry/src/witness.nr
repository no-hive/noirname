use crate::hashes::TREE_DEPTH;
use aztec::protocol::traits::{Deserialize, Serialize};

/// Local wallet input, never returned to the calling dApp contract.
#[derive(Serialize, Deserialize)]
pub struct ClaimWitness {
    pub claim_key: Field,
    pub leaf_index: u32,
    pub siblings: [Field; TREE_DEPTH],
}
