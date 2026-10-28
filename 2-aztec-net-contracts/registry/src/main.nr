pub mod claim_note;
pub mod name_note;
pub mod hashes;
pub mod witness;
use aztec::macros::aztec;

#[aztec]
pub contract NoirNameRegistry {
    use crate::{claim_note::ClaimNote, name_note::NameNote, hashes, witness::ClaimWitness};
    use aztec::{
        macros::{functions::{authorize_once, external, initializer, internal}, storage::storage},
        messages::delivery::MessageDelivery,
        note::{
            note_getter_options::NoteGetterOptions, note_interface::NoteProperties,
            note_viewer_options::NoteViewerOptions,
        },
        oracle::capsules,
        protocol::{address::{AztecAddress, EthAddress}, traits::ToField},
        state_vars::{Owned, PrivateSet, PublicImmutable},
        utils::comparison::Comparator,
    };

    #[storage]
    struct Storage<Context> {
        portal: PublicImmutable<EthAddress, Context>,
        claims: Owned<PrivateSet<ClaimNote, Context>, Context>,
        names: Owned<PrivateSet<NameNote, Context>, Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(portal: EthAddress) {
        assert(portal.to_field() != 0, "zero portal");
        self.storage.portal.initialize(portal);
    }

    /// Consumes one authenticated L1 message and creates a private, non-transferable claim.
    /// Whoever knows the message secret can claim it first. Never share that secret.
    #[external("private")]
    fn claim(namehash_hi: u128, namehash_lo: u128, secret: Field, message_index: Field, name_words: [Field; 9], name_length: u32) {
        assert(name_length <= 255, "name is too long");
        assert(secret != 0, "zero secret");
        let content = hashes::portal_content(namehash_hi, namehash_lo);
        self.context.consume_l1_to_l2_message(
            content,
            [secret],
            self.storage.portal.read(),
            message_index,
        );
        let note = ClaimNote {
            namehash_hi,
            namehash_lo,
            claim_key: hashes::claim_key(secret, message_index, namehash_hi, namehash_lo),
        };
        self.storage.claims.at(self.msg_sender()).insert(note).deliver(
            MessageDelivery::onchain_constrained(),
        );
        for part in 0..3 {
            if name_length > part * 93 {
                self.storage.names.at(self.msg_sender()).insert(NameNote {
                    claim_key: note.claim_key,
                    part,
                    byte_length: name_length,
                    words: [name_words[part * 3], name_words[part * 3 + 1], name_words[part * 3 + 2]],
                }).deliver(MessageDelivery::onchain_constrained());
            }
        }
    }

    /// Checks existence and holder authorization; exposes neither ENS namehash nor claim identifier.
    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn assert_has_claim(from: AztecAddress, action_scope: Field, authwit_nonce: Field) {
        let _ = self.internal._selected_claim(from, action_scope, authwit_nonce);
    }

    /// The caller MUST obtain allowed_root from its own trusted policy, not user input.
    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn assert_in_set(
        from: AztecAddress,
        allowed_root: Field,
        action_scope: Field,
        authwit_nonce: Field,
    ) {
        let (note, witness) = self.internal._selected_claim(from, action_scope, authwit_nonce);
        assert(
            hashes::membership_root(
                note.namehash_hi,
                note.namehash_lo,
                witness.leaf_index,
                witness.siblings,
            )
                == allowed_root,
            "claim is not in allowed set",
        );
    }

    /// Emits a registry-siloed nullifier; replays fail even with a fresh authwit nonce.
    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn use_claim_once(from: AztecAddress, action_scope: Field, authwit_nonce: Field) {
        let (note, _) = self.internal._selected_claim(from, action_scope, authwit_nonce);
        let nullifier = hashes::action_nullifier(
            note.claim_key,
            self.context.chain_id(),
            self.context.version(),
            self.msg_sender(),
            action_scope,
        );
        // This is an action nullifier, NOT a note nullifier; domain-separated and siloed by this registry.
        self.context.push_nullifier_unsafe(nullifier);
    }

    /// Atomic allowlist + one-use check on the SAME claim. Avoid mixing two independent claim selections.
    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn use_claim_in_set_once(
        from: AztecAddress,
        allowed_root: Field,
        action_scope: Field,
        authwit_nonce: Field,
    ) {
        let (note, witness) = self.internal._selected_claim(from, action_scope, authwit_nonce);
        assert(
            hashes::membership_root(
                note.namehash_hi,
                note.namehash_lo,
                witness.leaf_index,
                witness.siblings,
            )
                == allowed_root,
            "claim is not in allowed set",
        );
        self.context.push_nullifier_unsafe(hashes::action_nullifier(
            note.claim_key,
            self.context.chain_id(),
            self.context.version(),
            self.msg_sender(),
            action_scope,
        ));
    }

    /// Returns only a stable, app-specific pseudonym. Does not publish it automatically.
    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn get_app_pseudonym(from: AztecAddress, authwit_nonce: Field) -> Field {
        let (note, _) = self.internal._selected_claim(from, 0, authwit_nonce);
        hashes::app_pseudonym(
            note.claim_key,
            self.context.chain_id(),
            self.context.version(),
            self.msg_sender(),
        )
    }

    /// Reads private local capsule data, then CONSTRAINS membership in the registry's immutable note set.
    /// Historical reads suffice only because there is no transfer, burn, mutation, or revocation entrypoint.
    #[internal("private")]
    fn _selected_claim(
        from: AztecAddress,
        scope: Field,
        nonce: Field,
    ) -> (ClaimNote, ClaimWitness) {
        let registry = self.context.this_address();
        let slot = hashes::witness_slot(self.msg_sender(), scope, nonce);
        // Safety: the oracle only selects a candidate; note existence, owner, key and Merkle root are constrained.
        let witness: ClaimWitness = unsafe {
            capsules::load(registry, slot, from).expect(f"prepare claim witness in wallet first")
        };
        let notes = self.storage.claims.at(from).get_notes(NoteGetterOptions::new()
            .select(ClaimNote::properties().claim_key, Comparator.EQ, witness.claim_key)
            .set_limit(1));
        assert(notes.len() == 1, "claim not found for owner");
        (notes.get(0).note, witness)
    }

    /// Wallet-only preparation. No transaction and NO proof: consumers must call a constrained entrypoint above.
    #[external("utility")]
    unconstrained fn prepare_witness(
        owner: AztecAddress,
        app: AztecAddress,
        action_scope: Field,
        authwit_nonce: Field,
        claim_key: Field,
        leaf_index: u32,
        siblings: [Field; 8],
    ) {
        let witness = ClaimWitness { claim_key, leaf_index, siblings };
        capsules::store(
            self.context.this_address(),
            hashes::witness_slot(app, action_scope, authwit_nonce),
            witness,
            owner,
        );
    }

    /// One page of 10 claim selectors for a local wallet UI. Keep these off servers and dApp calldata.
    #[external("utility")]
    unconstrained fn list_claim_keys(owner: AztecAddress, page: u32) -> ([Field; 10], u32) {
        let notes = self.storage.claims.at(owner).view_notes(NoteViewerOptions::new()
            .set_offset(page * 10)
            .set_limit(10));
        let mut keys = [0; 10];
        for i in 0..10 {
            if i < notes.len() {
                keys[i] = notes.get(i).claim_key;
            }
        }
        (keys, notes.len())
    }
    /// Private wallet-only display data. Neither utility is an ownership proof.
    #[external("utility")]
    unconstrained fn list_claims(owner: AztecAddress, page: u32) -> ([ClaimNote; 10], u32) {
        let notes = self.storage.claims.at(owner).view_notes(NoteViewerOptions::new().set_offset(page * 10).set_limit(10));
        let mut items = [ClaimNote { namehash_hi: 0, namehash_lo: 0, claim_key: 0 }; 10];
        for i in 0..10 { if i < notes.len() { items[i] = notes.get(i); } }
        (items, notes.len())
    }

    #[external("utility")]
    unconstrained fn list_name_chunks(owner: AztecAddress, page: u32) -> ([NameNote; 10], u32) {
        let notes = self.storage.names.at(owner).view_notes(NoteViewerOptions::new().set_offset(page * 10).set_limit(10));
        let mut items = [NameNote { claim_key: 0, part: 0, byte_length: 0, words: [0; 3] }; 10];
        for i in 0..10 { if i < notes.len() { items[i] = notes.get(i); } }
        (items, notes.len())
    }

}
