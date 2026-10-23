// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_party::party_tests;

use std::unit_test::{assert_eq, destroy};
use sui::event::events_by_type;
use miso_party::party::{Self, PartyNameSetEvent, PartyCreatedEvent};
use miso_party::test_helpers;

const MAX_NAME_LENGTH: u64 = 200;

#[test]
fun new_party() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::party(ctx);
    assert_eq!(party.name(), b"Test Artist".to_string());
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    destroy(party);
    destroy(cap);
}

#[test]
fun new_party_with_max_name() {
    let ctx = &mut tx_context::dummy();
    let name = test_helpers::long_string(MAX_NAME_LENGTH);
    let (party, cap) = party::new(name, ctx);
    assert_eq!(party.name().length(), MAX_NAME_LENGTH);
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    destroy(party);
    destroy(cap);
}

#[test]
fun set_name() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::party(ctx);
    party.set_name(&cap, b"New Name".to_string());
    party.set_name(&cap, b"New Name".to_string());
    party.set_name(&cap, b"Final Name".to_string());
    assert_eq!(party.name(), b"Final Name".to_string());
    assert_eq!(events_by_type<PartyNameSetEvent>().length(), 2);
    destroy(party);
    destroy(cap);
}

#[test]
fun equal_name_write_preserves_state_without_event() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::party(ctx);
    party.set_name(&cap, b"Test Artist".to_string());
    assert_eq!(party.name(), b"Test Artist".to_string());
    assert_eq!(events_by_type<PartyNameSetEvent>().length(), 0);
    destroy(party);
    destroy(cap);
}

#[test]
fun set_name_at_max_length() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::party(ctx);
    let name = test_helpers::long_string(MAX_NAME_LENGTH);
    party.set_name(&cap, name);
    assert_eq!(party.name().length(), MAX_NAME_LENGTH);
    assert_eq!(events_by_type<PartyNameSetEvent>().length(), 1);
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EEmptyString)]
fun new_empty_name() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = party::new( b"".to_string(), ctx);
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EMaxNameLengthExceeded)]
fun new_name_too_long() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = party::new(
        test_helpers::long_string(MAX_NAME_LENGTH + 1),
        ctx,
    );
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EEmptyString)]
fun set_name_empty() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::party(ctx);
    party.set_name(&cap, b"".to_string());
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EMaxNameLengthExceeded)]
fun set_name_too_long() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::party(ctx);
    party.set_name(&cap, test_helpers::long_string(MAX_NAME_LENGTH + 1));
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun unauthorized_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party1, cap1) = test_helpers::party(ctx);
    let (party2, cap2) = test_helpers::party(ctx);

    party1.set_name(&cap2, b"Hacked".to_string());

    destroy(party1);
    destroy(cap1);
    destroy(party2);
    destroy(cap2);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun unauthorized_equal_name_write() {
    let ctx = &mut tx_context::dummy();
    let (mut party1, cap1) = test_helpers::party(ctx);
    let (party2, cap2) = test_helpers::party(ctx);

    party1.set_name(&cap2, b"Test Artist".to_string());

    destroy(party1);
    destroy(cap1);
    destroy(party2);
    destroy(cap2);
}

#[test]
fun authorize_reads_without_mutating_party() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::party(ctx);
    party.authorize(&cap);
    assert_eq!(party.name(), b"Test Artist".to_string());
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun authorize_rejects_another_partys_cap() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::party(ctx);
    let (other, other_cap) = test_helpers::party(ctx);
    party.authorize(&other_cap);
    destroy(party);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun uid_mut_rejects_another_partys_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::party(ctx);
    let (other, other_cap) = test_helpers::party(ctx);
    let _ = party.uid_mut(&other_cap);
    destroy(party);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}
