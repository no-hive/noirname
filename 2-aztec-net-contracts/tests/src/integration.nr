use aztec::{
    protocol::address::{AztecAddress, EthAddress},
    test::helpers::{authwit::add_private_authwit_from_call, test_environment::TestEnvironment},
};
use noirname_example::ExampleApp;
use noirname_registry::{hashes, NoirNameRegistry};

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, EthAddress, Field) {
    setup_for(false)
}

unconstrained fn setup_for(
    authwits: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, EthAddress, Field) {
    let mut env = TestEnvironment::new();
    let owner = if authwits {
        env.create_contract_account()
    } else {
        env.create_light_account()
    };
    let portal = EthAddress::from_field(0x1234);
    let registry = env.deploy("@noirname_registry/NoirNameRegistry").with_public_initializer(
        owner,
        NoirNameRegistry::interface().constructor(portal),
    );
    let index = env.send_l1_to_l2_message(hashes::portal_content(1, 2), 99, portal, registry);
    env.call_private(owner, NoirNameRegistry::at(registry).claim(1, 2, 99, index, [0; 9], 0));
    (env, owner, registry, portal, index)
}

unconstrained fn prepare(
    env: TestEnvironment,
    registry: AztecAddress,
    owner: AztecAddress,
    app: AztecAddress,
    scope: Field,
    nonce: Field,
    key: Field,
) {
    env.execute_utility(NoirNameRegistry::at(registry).prepare_witness(
        owner,
        app,
        scope,
        nonce,
        key,
        0,
        [0; 8],
    ));
}

#[test]
unconstrained fn claim_note_discovered_and_reusable() {
    let (env, owner, registry, _, index) = setup();
    let key = hashes::claim_key(99, index, 1, 2);
    let (keys, count) =
        env.execute_utility(NoirNameRegistry::at(registry).list_claim_keys(owner, 0));
    assert_eq(count, 1);
    assert_eq(keys[0], key);
    prepare(env, registry, owner, owner, 7, 0, key);
    env.call_private(owner, NoirNameRegistry::at(registry).assert_has_claim(owner, 7, 0));
    env.call_private(owner, NoirNameRegistry::at(registry).assert_has_claim(owner, 7, 0));
}

#[test(should_fail)]
unconstrained fn rejects_same_message_twice() {
    let (env, owner, registry, _, index) = setup();
    env.call_private(owner, NoirNameRegistry::at(registry).claim(1, 2, 99, index, [0; 9], 0));
}

#[test(should_fail)]
unconstrained fn rejects_wrong_secret() {
    let (env, owner, registry, portal, _) = setup();
    let index = env.send_l1_to_l2_message(hashes::portal_content(3, 4), 100, portal, registry);
    env.call_private(owner, NoirNameRegistry::at(registry).claim(3, 4, 101, index, [0; 9], 0));
}

#[test(should_fail)]
unconstrained fn rejects_wrong_portal() {
    let (env, owner, registry, _, _) = setup();
    let index = env.send_l1_to_l2_message(
        hashes::portal_content(3, 4),
        100,
        EthAddress::from_field(0x4321),
        registry,
    );
    env.call_private(owner, NoirNameRegistry::at(registry).claim(3, 4, 100, index, [0; 9], 0));
}

#[test(should_fail)]
unconstrained fn rejects_wrong_namehash() {
    let (env, owner, registry, portal, _) = setup();
    let index = env.send_l1_to_l2_message(hashes::portal_content(3, 4), 100, portal, registry);
    env.call_private(owner, NoirNameRegistry::at(registry).claim(3, 5, 100, index, [0; 9], 0));
}

#[test(should_fail_with = "claim not found for owner")]
unconstrained fn witness_cannot_forge_a_note() {
    let (env, owner, registry, _, _) = setup();
    prepare(env, registry, owner, owner, 7, 0, 123456);
    env.call_private(owner, NoirNameRegistry::at(registry).assert_has_claim(owner, 7, 0));
}

#[test(should_fail_with = "claim not found for owner")]
unconstrained fn another_account_cannot_use_owners_claim() {
    let (mut env, _, registry, _, index) = setup();
    let stranger = env.create_contract_account();
    prepare(
        env,
        registry,
        stranger,
        stranger,
        7,
        0,
        hashes::claim_key(99, index, 1, 2),
    );
    env.call_private(stranger, NoirNameRegistry::at(registry).assert_has_claim(stranger, 7, 0));
}

#[test]
unconstrained fn allowlist_accepts_member() {
    let (env, owner, registry, _, index) = setup();
    prepare(
        env,
        registry,
        owner,
        owner,
        7,
        0,
        hashes::claim_key(99, index, 1, 2),
    );
    let root = hashes::membership_root(1, 2, 0, [0; 8]);
    env.call_private(owner, NoirNameRegistry::at(registry).assert_in_set(owner, root, 7, 0));
}

#[test(should_fail_with = "claim is not in allowed set")]
unconstrained fn allowlist_rejects_nonmember() {
    let (env, owner, registry, _, index) = setup();
    prepare(
        env,
        registry,
        owner,
        owner,
        7,
        0,
        hashes::claim_key(99, index, 1, 2),
    );
    let other_root = hashes::membership_root(3, 4, 0, [0; 8]);
    env.call_private(owner, NoirNameRegistry::at(registry).assert_in_set(owner, other_root, 7, 0));
}

#[test(should_fail)]
unconstrained fn rejects_repeated_action() {
    let (env, owner, registry, _, index) = setup();
    prepare(
        env,
        registry,
        owner,
        owner,
        7,
        0,
        hashes::claim_key(99, index, 1, 2),
    );
    env.call_private(owner, NoirNameRegistry::at(registry).use_claim_once(owner, 7, 0));
    env.call_private(owner, NoirNameRegistry::at(registry).use_claim_once(owner, 7, 0));
}

#[test]
unconstrained fn permits_new_action_scope() {
    let (env, owner, registry, _, index) = setup();
    let key = hashes::claim_key(99, index, 1, 2);
    prepare(env, registry, owner, owner, 7, 0, key);
    prepare(env, registry, owner, owner, 8, 0, key);
    env.call_private(owner, NoirNameRegistry::at(registry).use_claim_once(owner, 7, 0));
    env.call_private(owner, NoirNameRegistry::at(registry).use_claim_once(owner, 8, 0));
}

#[test]
unconstrained fn pseudonym_stable_with_fresh_authorizations() {
    let (mut env, owner, registry, _, index) = setup_for(true);
    let root = hashes::membership_root(1, 2, 0, [0; 8]);
    let app = env.deploy("@noirname_example/ExampleApp").with_public_initializer(
        owner,
        ExampleApp::interface().constructor(registry, root),
    );
    let key = hashes::claim_key(99, index, 1, 2);
    prepare(env, registry, owner, app, 0, 1, key);
    prepare(env, registry, owner, app, 0, 2, key);
    add_private_authwit_from_call(
        env,
        owner,
        app,
        NoirNameRegistry::at(registry).get_app_pseudonym(owner, 1),
    );
    add_private_authwit_from_call(
        env,
        owner,
        app,
        NoirNameRegistry::at(registry).get_app_pseudonym(owner, 2),
    );
    let first = env.call_private(owner, ExampleApp::at(app).pseudonym(1));
    let second = env.call_private(owner, ExampleApp::at(app).pseudonym(2));
    assert_eq(first, second);
}

#[test(should_fail)]
unconstrained fn app_requires_holder_authwit() {
    let (mut env, owner, registry, _, index) = setup_for(true);
    let app = env.deploy("@noirname_example/ExampleApp").with_public_initializer(
        owner,
        ExampleApp::interface().constructor(registry, 0),
    );
    prepare(
        env,
        registry,
        owner,
        app,
        7,
        1,
        hashes::claim_key(99, index, 1, 2),
    );
    env.call_private(owner, ExampleApp::at(app).enter(7, 1));
}

#[test]
unconstrained fn authorized_app_can_check_claim() {
    let (mut env, owner, registry, _, index) = setup_for(true);
    let app = env.deploy("@noirname_example/ExampleApp").with_public_initializer(
        owner,
        ExampleApp::interface().constructor(registry, 0),
    );
    prepare(
        env,
        registry,
        owner,
        app,
        7,
        1,
        hashes::claim_key(99, index, 1, 2),
    );
    add_private_authwit_from_call(
        env,
        owner,
        app,
        NoirNameRegistry::at(registry).assert_has_claim(owner, 7, 1),
    );
    env.call_private(owner, ExampleApp::at(app).enter(7, 1));
}

#[test(should_fail)]
unconstrained fn fresh_authwit_does_not_bypass_one_use_rule() {
    let (mut env, owner, registry, _, index) = setup_for(true);
    let root = hashes::membership_root(1, 2, 0, [0; 8]);
    let app = env.deploy("@noirname_example/ExampleApp").with_public_initializer(
        owner,
        ExampleApp::interface().constructor(registry, root),
    );
    let key = hashes::claim_key(99, index, 1, 2);
    prepare(env, registry, owner, app, 7, 1, key);
    prepare(env, registry, owner, app, 7, 2, key);
    add_private_authwit_from_call(
        env,
        owner,
        app,
        NoirNameRegistry::at(registry).use_claim_in_set_once(owner, root, 7, 1),
    );
    env.call_private(owner, ExampleApp::at(app).vote(7, 0, 1));
    add_private_authwit_from_call(
        env,
        owner,
        app,
        NoirNameRegistry::at(registry).use_claim_in_set_once(owner, root, 7, 2),
    );
    env.call_private(owner, ExampleApp::at(app).vote(7, 1, 2));
}

#[test]
unconstrained fn private_name_chunks_belong_to_the_same_claim() {
    let (env, owner, registry, portal, _) = setup();
    let index = env.send_l1_to_l2_message(hashes::portal_content(3, 4), 100, portal, registry);
    env.call_private(owner, NoirNameRegistry::at(registry).claim(3, 4, 100, index, [1, 2, 3, 4, 5, 6, 7, 8, 9], 255));
    let (names, count) = env.execute_utility(NoirNameRegistry::at(registry).list_name_chunks(owner, 0));
    assert_eq(count, 3);
    for i in 0..3 {
        assert_eq(names[i].claim_key, hashes::claim_key(100, index, 3, 4));
        assert_eq(names[i].byte_length, 255);
    }
    let (_, claims) = env.execute_utility(NoirNameRegistry::at(registry).list_claims(owner, 0));
    assert_eq(claims, 2);
}

#[test(should_fail_with = "name is too long")]
unconstrained fn rejects_oversized_name_metadata() {
    let (env, owner, registry, portal, _) = setup();
    let index = env.send_l1_to_l2_message(hashes::portal_content(3, 4), 100, portal, registry);
    env.call_private(owner, NoirNameRegistry::at(registry).claim(3, 4, 100, index, [0; 9], 256));
}
