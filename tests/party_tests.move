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
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
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
