// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Parties (individuals or groups) that participate in on-chain activities.
///
/// A `Party` is a named, shared identity. Every mutation is gated by its
/// `PartyAdminCap`; `uid_mut` is the extension surface through which other
/// packages attach data as dynamic fields.
///
/// Group membership is consent-based: the group's cap invites, the member's
/// own cap accepts. Pending invites and memberships are dynamic fields on both
/// parties under module-private keys, so no extension can forge or scrub them.
module miso_party::party;

// === Imports ===

use std::string::String;
use sui::derived_object::claim;
use sui::dynamic_field as df;
use sui::event::emit;
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EUnauthorized: u64 = 0;
const ENotIndividualKind: u64 = 1;
const ENotGroupKind: u64 = 2;
const EMaxGroupMembersExceeded: u64 = 3;
const EMaxNameLengthExceeded: u64 = 4;
const EEmptyString: u64 = 5;
const EDuplicateParty: u64 = 6;
const EAlreadyInvited: u64 = 7;
const ENotGroupMember: u64 = 8;
const ENoPendingInvite: u64 = 9;

// === Constants ===

const MAX_GROUP_MEMBERS: u64 = 200;
/// In bytes.
const MAX_NAME_LENGTH: u64 = 200;

// === Structs ===

public struct Party has key {
    id: UID,
    kind: PartyKind,
    /// Human-readable and unverified; verification is an application concern.
    name: String,
}

public struct PartyAdminCap has key, store {
    id: UID,
    party_id: ID,
}

public struct PartyAdminCapKey(ID) has copy, drop, store;

/// On the GROUP: a pending invite to the member with this ID.
public struct PendingInviteKey(ID) has copy, drop, store;

/// On the MEMBER: a pending invite from the group with this ID — the
/// member-facing inbox, discoverable without scanning groups.
public struct PendingMembershipKey(ID) has copy, drop, store;

/// On the MEMBER: membership of the group with this ID. Mirrors the group's
/// member set; the two are always written together.
public struct MembershipKey(ID) has copy, drop, store;

// === Enums ===

/// Group members are individual parties.
public enum PartyKind has drop, store {
    Individual,
    Group(VecSet<ID>),
}

// === Events ===

/// Emitted once, when a new party is shared, with its admin cap and final
/// same-transaction name and kind. Members joined before sharing appear as
/// `PartyGroupMembershipAcceptedEvent`s in the same transaction.
public struct PartyCreatedEvent has copy, drop {
    party_id: ID,
    admin_cap_id: ID,
    name: String,
    is_group: bool,
}

public struct PartyNameSetEvent has copy, drop {
    party_id: ID,
    name: String,
}

public struct PartyGroupInviteCreatedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct PartyGroupMembershipAcceptedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct PartyGroupInviteDeclinedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct PartyGroupInviteRevokedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct PartyGroupMembershipLeftEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct PartyGroupMembershipRemovedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

// === Public Functions ===

/// `Party` is `key`-only, so it must be shared in the same transaction.
public fun new(
    kind: PartyKind,
    name: String,
    ctx: &mut TxContext,
): (Party, PartyAdminCap) {
    assert!(!name.is_empty(), EEmptyString);
    assert!(name.length() <= MAX_NAME_LENGTH, EMaxNameLengthExceeded);

    let mut party = Party {
        id: object::new(ctx),
        kind,
        name,
    };
    let party_id = object::id(&party);
    let cap = PartyAdminCap {
        id: claim(&mut party.id, PartyAdminCapKey(party_id)),
        party_id,
    };
    (party, cap)
}

public fun share(self: Party, cap: &PartyAdminCap) {
    self.authorize(cap);
    emit(PartyCreatedEvent {
        party_id: object::id(&self),
        admin_cap_id: object::id(cap),
        name: self.name,
        is_group: self.is_group_kind(),
    });
    transfer::share_object(self);
}

public fun new_individual_kind(): PartyKind {
    PartyKind::Individual
}

public fun new_group_kind(): PartyKind {
    PartyKind::Group(vec_set::empty())
}

// === View Functions ===

public fun name(self: &Party): String {
    self.name
}

public fun is_individual_kind(self: &Party): bool {
    !self.is_group_kind()
}

public fun is_group_kind(self: &Party): bool {
    match (&self.kind) {
        PartyKind::Group(_) => true,
        _ => false,
    }
}

public fun group_members(self: &Party): &VecSet<ID> {
    match (&self.kind) {
        PartyKind::Group(members) => members,
        _ => abort ENotGroupKind,
    }
}

/// Whether this party holds a membership record for `group_id`. Reads the
/// member side only, so it is the member-gated authorization primitive for
/// extensions.
public fun is_member(self: &Party, group_id: ID): bool {
    df::exists(&self.id, MembershipKey(group_id))
}

public fun has_pending_invite(self: &Party, member_id: ID): bool {
    df::exists(&self.id, PendingInviteKey(member_id))
}

public fun has_pending_membership(self: &Party, group_id: ID): bool {
    df::exists(&self.id, PendingMembershipKey(group_id))
}

public fun uid(self: &Party): &UID {
    &self.id
}

// === Admin Functions ===

/// Setting the current name is a no-op: nothing is written and nothing is
/// emitted.
public fun set_name(self: &mut Party, cap: &PartyAdminCap, name: String) {
    self.authorize(cap);
    assert!(!name.is_empty(), EEmptyString);
    assert!(name.length() <= MAX_NAME_LENGTH, EMaxNameLengthExceeded);
    if (self.name == name) return;
    self.name = name;
    emit(PartyNameSetEvent { party_id: object::id(self), name });
}

/// The member joins only through `accept_invite` with its own cap, so no party
/// becomes a member without consent.
public fun invite_party(group: &mut Party, group_cap: &PartyAdminCap, member: &mut Party) {
    group.authorize(group_cap);
    let group_id = object::id(group);
    let member_id = object::id(member);
    let members = group.group_members();
    assert!(member.is_individual_kind(), ENotIndividualKind);
    assert!(!members.contains(&member_id), EDuplicateParty);
    assert!(members.length() < MAX_GROUP_MEMBERS, EMaxGroupMembersExceeded);
    assert!(!df::exists(&group.id, PendingInviteKey(member_id)), EAlreadyInvited);

    df::add(&mut group.id, PendingInviteKey(member_id), true);
    df::add(&mut member.id, PendingMembershipKey(group_id), true);
    emit(PartyGroupInviteCreatedEvent { group_id, member_id });
}

public fun accept_invite(member: &mut Party, member_cap: &PartyAdminCap, group: &mut Party) {
    member.authorize(member_cap);
    assert!(group.is_group_kind(), ENotGroupKind);
    let group_id = object::id(group);
    let member_id = object::id(member);
    consume_invite(group, member);

    let members = group.members_mut();
    assert!(members.length() < MAX_GROUP_MEMBERS, EMaxGroupMembersExceeded);
    members.insert(member_id);
    df::add(&mut member.id, MembershipKey(group_id), true);
    emit(PartyGroupMembershipAcceptedEvent { group_id, member_id });
}

public fun decline_invite(member: &mut Party, member_cap: &PartyAdminCap, group: &mut Party) {
    member.authorize(member_cap);
    consume_invite(group, member);
    emit(PartyGroupInviteDeclinedEvent {
        group_id: object::id(group),
        member_id: object::id(member),
    });
}

public fun revoke_invite(group: &mut Party, group_cap: &PartyAdminCap, member: &mut Party) {
    group.authorize(group_cap);
    consume_invite(group, member);
    emit(PartyGroupInviteRevokedEvent {
        group_id: object::id(group),
        member_id: object::id(member),
    });
}

/// The member's unconditional exit.
public fun leave(member: &mut Party, member_cap: &PartyAdminCap, group: &mut Party) {
    member.authorize(member_cap);
    remove_membership(group, member);
    emit(PartyGroupMembershipLeftEvent {
        group_id: object::id(group),
        member_id: object::id(member),
    });
}

/// Scrubs the member's record for this group only; nothing else on the member
/// is reachable without its cap.
public fun remove_member(group: &mut Party, group_cap: &PartyAdminCap, member: &mut Party) {
    group.authorize(group_cap);
    remove_membership(group, member);
    emit(PartyGroupMembershipRemovedEvent {
        group_id: object::id(group),
        member_id: object::id(member),
    });
}

public fun uid_mut(self: &mut Party, cap: &PartyAdminCap): &mut UID {
    self.authorize(cap);
    &mut self.id
}

// === Private Functions ===

fun authorize(self: &Party, cap: &PartyAdminCap) {
    assert!(cap.party_id == object::id(self), EUnauthorized);
}

fun members_mut(self: &mut Party): &mut VecSet<ID> {
    match (&mut self.kind) {
        PartyKind::Group(members) => members,
        _ => abort ENotGroupKind,
    }
}

fun consume_invite(group: &mut Party, member: &mut Party) {
    let group_id = object::id(group);
    let member_id = object::id(member);
    assert!(df::exists(&group.id, PendingInviteKey(member_id)), ENoPendingInvite);
    let _: bool = df::remove(&mut group.id, PendingInviteKey(member_id));
    let _: bool = df::remove(&mut member.id, PendingMembershipKey(group_id));
}

fun remove_membership(group: &mut Party, member: &mut Party) {
    let group_id = object::id(group);
    let member_id = object::id(member);
    let members = group.members_mut();
    assert!(members.contains(&member_id), ENotGroupMember);
    members.remove(&member_id);
    let _: bool = df::remove(&mut member.id, MembershipKey(group_id));
}

// === Test Functions ===

#[test_only]
public fun party_created_event_fields(event: PartyCreatedEvent): (ID, ID, String, bool) {
    let PartyCreatedEvent { party_id, admin_cap_id, name, is_group } = event;
    (party_id, admin_cap_id, name, is_group)
}

#[test_only]
public fun new_group_with_n_members_for_testing(
    n: u64,
    ctx: &mut TxContext,
): (Party, PartyAdminCap) {
    let mut members = vec_set::empty();
    n.do!(|_| members.insert(ctx.fresh_object_address().to_id()));
    new(PartyKind::Group(members), b"Test Group".to_string(), ctx)
}
