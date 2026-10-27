// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module miso_party::party;

// === Imports ===

use std::string::String;
use sui::derived_object::claim;
use sui::event::emit;

// === Errors ===

const EUnauthorized: u64 = 0;
const EMaxNameLengthExceeded: u64 = 4;
const EEmptyString: u64 = 5;

// === Constants ===

const MAX_NAME_LENGTH: u64 = 200;

// === Structs ===

public struct Party has key {
    id: UID,
    name: String,
}

public struct PartyAdminCap has key, store {
    id: UID,
    party_id: ID,
}

public struct PartyAdminCapKey() has copy, drop, store;

// === Events ===

public struct PartyCreatedEvent has copy, drop {
    party_id: ID,
    party_admin_cap_id: ID,
    name: String,
}

public struct PartyNameSetEvent has copy, drop {
    party_id: ID,
    name: String,
}

// === Public Functions ===

public fun new(
    name: String,
    ctx: &mut TxContext,
): (Party, PartyAdminCap) {
    assert!(!name.is_empty(), EEmptyString);
    assert!(name.length() <= MAX_NAME_LENGTH, EMaxNameLengthExceeded);

    let mut party = Party {
        id: object::new(ctx),
        name,
    };
    let party_id = object::id(&party);
    let cap = PartyAdminCap {
        id: claim(&mut party.id, PartyAdminCapKey()),
        party_id,
    };
    (party, cap)
}

// === View Functions ===

public fun name(self: &Party): String {
    self.name
}

public fun uid(self: &Party): &UID {
    &self.id
}

// === Admin Functions ===

public fun share(self: Party, cap: &PartyAdminCap) {
    self.authorize(cap);
    emit(PartyCreatedEvent {
        party_id: object::id(&self),
        party_admin_cap_id: object::id(cap),
        name: self.name,
    });
    transfer::share_object(self);
}

public fun set_name(self: &mut Party, cap: &PartyAdminCap, name: String) {
    self.authorize(cap);
    assert!(!name.is_empty(), EEmptyString);
    assert!(name.length() <= MAX_NAME_LENGTH, EMaxNameLengthExceeded);
    if (self.name == name) return;
    self.name = name;
    emit(PartyNameSetEvent { party_id: object::id(self), name });
}

public fun authorize(self: &Party, cap: &PartyAdminCap) {
    assert!(cap.party_id == object::id(self), EUnauthorized);
}

public fun uid_mut(self: &mut Party, cap: &PartyAdminCap): &mut UID {
    self.authorize(cap);
    &mut self.id
}

// === Test Functions ===

#[test_only]
public fun party_created_event_fields(event: &PartyCreatedEvent): (ID, ID, String) {
    let PartyCreatedEvent { party_id, party_admin_cap_id, name } = event;
    (*party_id, *party_admin_cap_id, *name)
}
