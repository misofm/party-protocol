// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_party::party_tests;

use std::unit_test::{assert_eq, destroy};
use sui::event::events_by_type;
use miso_party::party::{
    Self,
    Party,
    PartyAdminCap,
    PartyCreatedEvent,
    PartyGroupInviteCreatedEvent,
    PartyGroupInviteDeclinedEvent,
    PartyGroupInviteRevokedEvent,
    PartyGroupMembershipAcceptedEvent,
    PartyGroupMembershipLeftEvent,
    PartyGroupMembershipRemovedEvent,
    PartyNameSetEvent,
};
use miso_party::test_helpers;

// Mirror party.move.
const MAX_NAME_LENGTH: u64 = 200;
const MAX_GROUP_MEMBERS: u64 = 200;

/// invite + accept in one step (the common path when one operator holds both caps).
fun join(
    group: &mut Party,
    group_cap: &PartyAdminCap,
    member: &mut Party,
    member_cap: &PartyAdminCap,
) {
    group.invite_party(member, group_cap);
    group.accept_invite(member, member_cap);
}

// === Individual Party ===

#[test]
fun new_individual() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::individual(ctx);
    assert_eq!(party.name(), b"Test Artist".to_string());
    assert!(party.is_individual_kind());
    assert!(!party.is_group_kind());
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    destroy(party);
    destroy(cap);
}

#[test]
fun new_individual_with_max_name() {
    let ctx = &mut tx_context::dummy();
    let name = test_helpers::long_string(MAX_NAME_LENGTH);
    let (party, cap) = test_helpers::individual_named(name, ctx);
    assert_eq!(party.name().length(), MAX_NAME_LENGTH);
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    destroy(party);
    destroy(cap);
}

// === Group Party ===

#[test]
fun new_group() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::group(ctx);
    assert!(party.is_group_kind());
    assert!(!party.is_individual_kind());
    assert!(party.group_members().is_empty());
    assert_eq!(events_by_type<PartyCreatedEvent>().length(), 0);
    destroy(party);
    destroy(cap);
}

// === Invite / Accept ===

#[test]
fun join_group() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut individual, individual_cap) = test_helpers::individual(ctx);

    let party_id = object::id(&individual);
    join(&mut group, &group_cap, &mut individual, &individual_cap);

    // Both sides recorded: the group's set and the member's own membership df.
    assert_eq!(group.group_members().length(), 1);
    assert!(group.group_members().contains(&party_id));
    assert!(party::is_member(&individual, object::id(&group)));
    assert!(!group.has_pending_invite(party_id)); // invite consumed
    // Inbox entry consumed.
    assert!(!party::has_pending_membership(&individual, object::id(&group)));
    assert_eq!(events_by_type<PartyGroupInviteCreatedEvent>().length(), 1);
    assert_eq!(events_by_type<PartyGroupMembershipAcceptedEvent>().length(), 1);

    destroy(group);
    destroy(group_cap);
    destroy(individual);
    destroy(individual_cap);
}

#[test]
fun join_multiple() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut ind1, cap1) = test_helpers::individual_named(b"Artist 1".to_string(), ctx);
    let (mut ind2, cap2) = test_helpers::individual_named(b"Artist 2".to_string(), ctx);
    let (mut ind3, cap3) = test_helpers::individual_named(b"Artist 3".to_string(), ctx);

    join(&mut group, &group_cap, &mut ind1, &cap1);
    join(&mut group, &group_cap, &mut ind2, &cap2);
    join(&mut group, &group_cap, &mut ind3, &cap3);

    assert_eq!(group.group_members().length(), 3);
    assert_eq!(events_by_type<PartyGroupInviteCreatedEvent>().length(), 3);
    assert_eq!(events_by_type<PartyGroupMembershipAcceptedEvent>().length(), 3);

    destroy(group);
    destroy(group_cap);
    destroy(ind1);
    destroy(cap1);
    destroy(ind2);
    destroy(cap2);
    destroy(ind3);
    destroy(cap3);
}

#[test]
fun decline_invite() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut member, member_cap) = test_helpers::individual(ctx);

    group.invite_party(&mut member, &group_cap);
    assert!(group.has_pending_invite(object::id(&member)));
    assert!(party::has_pending_membership(&member, object::id(&group)));

    group.decline_invite(&mut member, &member_cap);
    assert!(!group.has_pending_invite(object::id(&member)));
    assert!(!party::has_pending_membership(&member, object::id(&group)));
    assert_eq!(group.group_members().length(), 0);
    assert_eq!(events_by_type<PartyGroupInviteCreatedEvent>().length(), 1);
    assert_eq!(events_by_type<PartyGroupInviteDeclinedEvent>().length(), 1);

    // A declined invitation can be created again and then accepted.
    group.invite_party(&mut member, &group_cap);
    group.accept_invite(&mut member, &member_cap);
    assert!(party::is_member(&member, object::id(&group)));
    assert_eq!(events_by_type<PartyGroupInviteCreatedEvent>().length(), 2);
    assert_eq!(events_by_type<PartyGroupMembershipAcceptedEvent>().length(), 1);

    destroy(group);
    destroy(group_cap);
    destroy(member);
    destroy(member_cap);
}

#[test]
fun revoke_invite() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut member, member_cap) = test_helpers::individual(ctx);

    let member_id = object::id(&member);
    group.invite_party(&mut member, &group_cap);
    assert!(group.has_pending_invite(member_id));
    assert!(party::has_pending_membership(&member, object::id(&group)));

    group.revoke_invite(&mut member, &group_cap);
    assert!(!group.has_pending_invite(member_id));
    assert!(!party::has_pending_membership(&member, object::id(&group)));
    assert_eq!(events_by_type<PartyGroupInviteCreatedEvent>().length(), 1);
    assert_eq!(events_by_type<PartyGroupInviteRevokedEvent>().length(), 1);

    // Revocation also leaves the invitation reusable.
    group.invite_party(&mut member, &group_cap);
    group.decline_invite(&mut member, &member_cap);
    assert_eq!(events_by_type<PartyGroupInviteCreatedEvent>().length(), 2);
    assert_eq!(events_by_type<PartyGroupInviteDeclinedEvent>().length(), 1);

    destroy(group);
    destroy(group_cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = party::ENoPendingInvite)]
fun accept_without_invite() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut member, member_cap) = test_helpers::individual(ctx);

    group.accept_invite(&mut member, &member_cap); // no pending invite

    destroy(group);
    destroy(group_cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun accept_with_wrong_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut member, member_cap) = test_helpers::individual(ctx);
    let (other, other_cap) = test_helpers::individual(ctx);

    group.invite_party(&mut member, &group_cap);
    group.accept_invite(&mut member, &other_cap); // not the member's cap

    destroy(group);
    destroy(group_cap);
    destroy(member);
    destroy(member_cap);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = party::ENotGroupKind)]
fun accept_on_individual() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    let (mut member, member_cap) = test_helpers::individual(ctx);

    party.accept_invite(&mut member, &member_cap); // `party` is not a group

    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

// === Remove / Evict ===

#[test]
fun remove_member() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut individual, individual_cap) = test_helpers::individual(ctx);

    join(&mut group, &group_cap, &mut individual, &individual_cap);
    assert_eq!(group.group_members().length(), 1);

    // Admin evict — scrubs both the set and the member's own record, no member cap.
    group.remove_member(&group_cap, &mut individual);
    assert_eq!(group.group_members().length(), 0);
    assert!(!party::is_member(&individual, object::id(&group)));
    assert_eq!(events_by_type<PartyGroupMembershipRemovedEvent>().length(), 1);

    destroy(group);
    destroy(group_cap);
    destroy(individual);
    destroy(individual_cap);
}

// === Set Name ===

#[test]
fun set_name() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
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
    let (mut party, cap) = test_helpers::individual(ctx);
    party.set_name(&cap, b"Test Artist".to_string());
    assert_eq!(party.name(), b"Test Artist".to_string());
    assert_eq!(events_by_type<PartyNameSetEvent>().length(), 0);
    destroy(party);
    destroy(cap);
}

#[test]
fun set_name_at_max_length() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    let name = test_helpers::long_string(MAX_NAME_LENGTH);
    party.set_name(&cap, name);
    assert_eq!(party.name().length(), MAX_NAME_LENGTH);
    assert_eq!(events_by_type<PartyNameSetEvent>().length(), 1);
    destroy(party);
    destroy(cap);
}

// === Boundary Tests ===

#[test, expected_failure(abort_code = party::EMaxGroupMembersExceeded)]
fun invite_exceeds_max_group_members() {
    let ctx = &mut tx_context::dummy();
    // Create a group pre-filled with MAX_GROUP_MEMBERS members.
    let (mut group, group_cap) = party::new_group_with_n_members_for_testing(
        MAX_GROUP_MEMBERS,
        ctx,
    );

    // Inviting one more should fail (the group is already full).
    let (mut individual, individual_cap) = test_helpers::individual(ctx);
    group.invite_party(&mut individual, &group_cap);

    destroy(individual);
    destroy(individual_cap);
    destroy(group);
    destroy(group_cap);
}

/// Capacity is enforced again at accept: a second pending invite cannot join
/// once the first fills the group.
#[test, expected_failure(abort_code = party::EMaxGroupMembersExceeded)]
fun accept_exceeds_max_group_members() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = party::new_group_with_n_members_for_testing(
        MAX_GROUP_MEMBERS - 1,
        ctx,
    );
    let (mut first, first_cap) = test_helpers::individual(ctx);
    let (mut second, second_cap) = test_helpers::individual(ctx);
    group.invite_party(&mut first, &group_cap);
    group.invite_party(&mut second, &group_cap);
    group.accept_invite(&mut first, &first_cap);
    group.accept_invite(&mut second, &second_cap);

    destroy(group);
    destroy(group_cap);
    destroy(first);
    destroy(first_cap);
    destroy(second);
    destroy(second_cap);
}

// === Error Conditions ===

#[test, expected_failure(abort_code = party::EEmptyString)]
fun new_empty_name() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = party::new(party::new_individual_kind(), b"".to_string(), ctx);
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EMaxNameLengthExceeded)]
fun new_name_too_long() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = party::new(
        party::new_individual_kind(),
        test_helpers::long_string(MAX_NAME_LENGTH + 1),
        ctx,
    );
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EEmptyString)]
fun set_name_empty() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    party.set_name(&cap, b"".to_string());
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EMaxNameLengthExceeded)]
fun set_name_too_long() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    party.set_name(&cap, test_helpers::long_string(MAX_NAME_LENGTH + 1));
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EDuplicateParty)]
fun invite_already_member() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut individual, individual_cap) = test_helpers::individual(ctx);

    join(&mut group, &group_cap, &mut individual, &individual_cap);
    group.invite_party(&mut individual, &group_cap); // already a member

    destroy(group);
    destroy(group_cap);
    destroy(individual);
    destroy(individual_cap);
}

#[test, expected_failure(abort_code = party::EAlreadyInvited)]
fun invite_duplicate_pending() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut individual, individual_cap) = test_helpers::individual(ctx);

    group.invite_party(&mut individual, &group_cap);
    group.invite_party(&mut individual, &group_cap); // already invited (pending)

    destroy(group);
    destroy(group_cap);
    destroy(individual);
    destroy(individual_cap);
}

#[test, expected_failure(abort_code = party::ENotGroupKind)]
fun invite_on_individual() {
    let ctx = &mut tx_context::dummy();
    let (mut party1, cap1) = test_helpers::individual(ctx);
    let (mut party2, cap2) = test_helpers::individual(ctx);

    party1.invite_party(&mut party2, &cap1);

    destroy(party1);
    destroy(cap1);
    destroy(party2);
    destroy(cap2);
}

#[test, expected_failure(abort_code = party::ENotIndividualKind)]
fun invite_group_as_member() {
    let ctx = &mut tx_context::dummy();
    let (mut group1, cap1) = test_helpers::group(ctx);
    let (mut group2, cap2) = test_helpers::group(ctx);

    group1.invite_party(&mut group2, &cap1);

    destroy(group1);
    destroy(cap1);
    destroy(group2);
    destroy(cap2);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun unauthorized_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party1, cap1) = test_helpers::individual(ctx);
    let (party2, cap2) = test_helpers::individual(ctx);

    // Try to use party2's cap on party1.
    party1.set_name(&cap2, b"Hacked".to_string());

    destroy(party1);
    destroy(cap1);
    destroy(party2);
    destroy(cap2);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun unauthorized_equal_name_write() {
    let ctx = &mut tx_context::dummy();
    let (mut party1, cap1) = test_helpers::individual(ctx);
    let (party2, cap2) = test_helpers::individual(ctx);

    // Authorization remains mandatory even when the requested name is equal.
    party1.set_name(&cap2, b"Test Artist".to_string());

    destroy(party1);
    destroy(cap1);
    destroy(party2);
    destroy(cap2);
}

#[test, expected_failure(abort_code = party::ENotGroupKind)]
fun remove_member_on_individual() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    let (mut member, member_cap) = test_helpers::individual(ctx);

    party.remove_member(&cap, &mut member); // `party` is not a group

    destroy(party);
    destroy(cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = party::ENotGroupKind)]
fun group_members_on_individual() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::individual(ctx);

    party.group_members(); // should abort

    destroy(party);
    destroy(cap);
}

// === Leave Group ===

#[test]
fun leave_group() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut member, member_cap) = test_helpers::individual(ctx);

    join(&mut group, &group_cap, &mut member, &member_cap);
    assert_eq!(group.group_members().length(), 1);

    // The member's own cap authorizes the exit — no group admin involved.
    group.leave(&mut member, &member_cap);
    assert_eq!(group.group_members().length(), 0);
    assert!(!party::is_member(&member, object::id(&group)));
    assert_eq!(events_by_type<PartyGroupMembershipLeftEvent>().length(), 1);
    assert_eq!(events_by_type<PartyGroupMembershipRemovedEvent>().length(), 0);

    destroy(group);
    destroy(group_cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = party::ENotGroupMember)]
fun leave_not_a_member() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut outsider, outsider_cap) = test_helpers::individual(ctx);

    group.leave(&mut outsider, &outsider_cap); // never joined

    destroy(group);
    destroy(group_cap);
    destroy(outsider);
    destroy(outsider_cap);
}

#[test, expected_failure(abort_code = party::ENotGroupKind)]
fun leave_on_individual() {
    let ctx = &mut tx_context::dummy();
    let (mut individual, individual_cap) = test_helpers::individual(ctx);
    let (mut member, member_cap) = test_helpers::individual(ctx);

    individual.leave(&mut member, &member_cap); // `individual` is not a group

    destroy(individual);
    destroy(individual_cap);
    destroy(member);
    destroy(member_cap);
}

#[test, expected_failure(abort_code = party::ENotGroupMember)]
fun remove_member_not_a_member() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (mut outsider, outsider_cap) = test_helpers::individual(ctx);

    group.remove_member(&group_cap, &mut outsider); // never joined

    destroy(group);
    destroy(group_cap);
    destroy(outsider);
    destroy(outsider_cap);
}
