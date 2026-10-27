// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_party::party_lifecycle_tests;

use miso_party::{party::{Self, Party, PartyCreatedEvent, PartyNameSetEvent}, test_helpers};
use std::unit_test::{assert_eq, destroy};
use sui::{dynamic_field, event::events_by_type, test_scenario};

const OWNER: address = @0xA1;
const READER: address = @0xB2;

#[test]
fun share_emits_final_identity_and_capability() {
    let mut scenario = test_scenario::begin(OWNER);
    let (mut party, cap) = test_helpers::party(scenario.ctx());
    let party_id = object::id(&party);
    party.set_name(&cap, b"Final Name".to_string());
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    party.share(&cap);
    let mut events = events_by_type<PartyCreatedEvent>();
    assert_eq!(events.length(), 1);
    let (event_party_id, event_party_admin_cap_id, event_name) = party::party_created_event_fields(
        &events.pop_back(),
    );
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_party_admin_cap_id, object::id(&cap));
    assert_eq!(event_name, b"Final Name".to_string());

    scenario.next_tx(READER);
    let party = scenario.take_shared<Party>();
    assert_eq!(party.name(), b"Final Name".to_string());
    party.authorize(&cap);
    test_scenario::return_shared(party);
    destroy(cap);
    scenario.end();
}

#[test]
fun set_name_works_on_shared_party() {
    let mut scenario = test_scenario::begin(OWNER);
    let (p, cap) = test_helpers::party(scenario.ctx());
    p.share(&cap);
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 1);

    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<Party>();
    p.set_name(&cap, b"New Stage Name".to_string());
    assert_eq!(p.name(), b"New Stage Name".to_string());
    assert_eq!(events_by_type<PartyNameSetEvent>().length(), 1);
    test_scenario::return_shared(p);

    destroy(cap);
    scenario.end();
}

#[test]
fun uid_mut_attaches_dynamic_fields_on_shared_party() {
    let mut scenario = test_scenario::begin(OWNER);
    let (p, cap) = test_helpers::party(scenario.ctx());
    p.share(&cap);

    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<Party>();
    dynamic_field::add(p.uid_mut(&cap), b"profile", 42u64);
    assert!(dynamic_field::exists(p.uid(), b"profile"));
    assert_eq!(*dynamic_field::borrow<vector<u8>, u64>(p.uid(), b"profile"), 42);
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    assert_eq!(events_by_type<PartyNameSetEvent>().length(), 0);
    test_scenario::return_shared(p);

    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun share_rejects_wrong_cap() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::party(ctx);
    let (other, other_cap) = test_helpers::party(ctx);

    destroy(cap);
    destroy(other);
    party.share(&other_cap);
    destroy(other_cap);
}
