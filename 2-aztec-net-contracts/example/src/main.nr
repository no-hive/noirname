use aztec::macros::aztec;

/// Integration examples. The configured registry and allowlist are immutable.
#[aztec]
pub contract ExampleApp {
    use aztec::{
        macros::{functions::{external, initializer, only_self}, storage::storage},
        protocol::address::AztecAddress,
        state_vars::{Map, PublicImmutable, PublicMutable},
    };
    use noirname_registry::NoirNameRegistry;

    #[storage]
    struct Storage<Context> {
        registry: PublicImmutable<AztecAddress, Context>,
        allowed_root: PublicImmutable<Field, Context>,
        votes: Map<Field, Map<Field, PublicMutable<u32, Context>, Context>, Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(registry: AztecAddress, allowed_root: Field) {
        assert(!registry.is_zero(), "zero registry");
        self.storage.registry.initialize(registry);
        self.storage.allowed_root.initialize(allowed_root);
    }

    #[external("private")]
    fn enter(action_scope: Field, authwit_nonce: Field) {
        self.call(NoirNameRegistry::at(self.storage.registry.read()).assert_has_claim(
            self.msg_sender(),
            action_scope,
            authwit_nonce,
        ));
        // Put the protected effect HERE, in the same transaction.
    }

    #[external("private")]
    fn enter_allowlist(action_scope: Field, authwit_nonce: Field) {
        self.call(NoirNameRegistry::at(self.storage.registry.read()).assert_in_set(
            self.msg_sender(),
            self.storage.allowed_root.read(),
            action_scope,
            authwit_nonce,
        ));
    }

    #[external("private")]
    fn use_once(action_scope: Field, authwit_nonce: Field) {
        self.call(NoirNameRegistry::at(self.storage.registry.read()).use_claim_once(
            self.msg_sender(),
            action_scope,
            authwit_nonce,
        ));
    }

    #[external("private")]
    fn pseudonym(authwit_nonce: Field) -> Field {
        self.call(NoirNameRegistry::at(self.storage.registry.read()).get_app_pseudonym(
            self.msg_sender(),
            authwit_nonce,
        ))
    }

    /// election_id is the one-use scope, NOT candidate. A new candidate cannot bypass the nullifier.
    /// Demo elections accept candidates 0 or 1. A production app must also enforce its election lifecycle.
    #[external("private")]
    fn vote(election_id: Field, candidate: Field, authwit_nonce: Field) {
        assert((candidate == 0) | (candidate == 1), "invalid candidate");
        self.call(NoirNameRegistry::at(self.storage.registry.read()).use_claim_in_set_once(
            self.msg_sender(),
            self.storage.allowed_root.read(),
            election_id,
            authwit_nonce,
        ));
        // Public demo tally deliberately reveals election_id and candidate, NOT ENS or owner.
        self.enqueue_self._count_vote(election_id, candidate);
    }

    #[only_self]
    #[external("public")]
    fn _count_vote(election_id: Field, candidate: Field) {
        let tally = self.storage.votes.at(election_id).at(candidate);
        tally.write(tally.read() + 1);
    }
}
