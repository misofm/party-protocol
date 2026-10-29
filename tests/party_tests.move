// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_party::party_tests;

use miso_party::party::{Self, PartyCreatedEvent};
use std::unit_test::{assert_eq, destroy};
use sui::event::events_by_type;

#[test]
fun new_party() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = party::new(ctx);
    assert_eq!(cap.party_id(), object::id(&party));
    let mut events = events_by_type<PartyCreatedEvent>();
    assert_eq!(events.length(), 1);
    let (event_party_id, event_party_admin_cap_id) = party::party_created_fields_for_testing(
        &events.pop_back(),
    );
    assert_eq!(event_party_id, object::id(&party));
    assert_eq!(event_party_admin_cap_id, object::id(&cap));
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun uid_mut_rejects_another_partys_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    let _ = party.uid_mut(&other_cap);
    destroy(party);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}
