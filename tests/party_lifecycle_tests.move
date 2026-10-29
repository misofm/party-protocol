// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_party::party_lifecycle_tests;

use miso_party::party::{Self, Party, PartyCreatedEvent};
use std::unit_test::{assert_eq, destroy};
use sui::{dynamic_field, event::events_by_type, test_scenario};

const OWNER: address = @0xA1;
const READER: address = @0xB2;

#[test]
fun share_is_silent() {
    let mut scenario = test_scenario::begin(OWNER);
    let (party, cap) = party::new(scenario.ctx());
    let party_id = object::id(&party);
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 1);
    party.share();
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 1);
    scenario.next_tx(READER);
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    let party = scenario.take_shared<Party>();
    assert_eq!(cap.party_id(), object::id(&party));
    assert_eq!(object::id(&party), party_id);
    test_scenario::return_shared(party);
    destroy(cap);
    scenario.end();
}

#[test]
fun uid_mut_attaches_dynamic_fields_on_shared_party() {
    let mut scenario = test_scenario::begin(OWNER);
    let (p, cap) = party::new(scenario.ctx());
    p.share();
    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<Party>();
    dynamic_field::add(p.uid_mut(&cap), b"profile", 42u64);
    assert_eq!(*dynamic_field::borrow<vector<u8>, u64>(p.uid(), b"profile"), 42);
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    test_scenario::return_shared(p);
    destroy(cap);
    scenario.end();
}
