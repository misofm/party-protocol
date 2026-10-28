// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module miso_party::party;

use sui::{derived_object::claim, event::emit};

// === Errors ===

const EUnauthorized: u64 = 0;

// === Structs ===

public struct Party has key {
    id: UID,
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
}

// === Public Functions ===

public fun new(ctx: &mut TxContext): (Party, PartyAdminCap) {
    let mut party = Party { id: object::new(ctx) };
    let cap = PartyAdminCap {
        id: claim(&mut party.id, PartyAdminCapKey()),
        party_id: object::id(&party),
    };
    (party, cap)
}

// === View Functions ===

public fun uid(self: &Party): &UID {
    &self.id
}

// === Admin Functions ===

public fun share(self: Party, cap: &PartyAdminCap) {
    self.authorize(cap);
    emit(PartyCreatedEvent {
        party_id: object::id(&self),
        party_admin_cap_id: object::id(cap),
    });
    transfer::share_object(self);
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
public fun party_created_event_fields(event: &PartyCreatedEvent): (ID, ID) {
    let PartyCreatedEvent { party_id, party_admin_cap_id } = event;
    (*party_id, *party_admin_cap_id)
}
