# miso_party

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Move](https://img.shields.io/badge/Move-2024-black.svg)](https://docs.sui.io/concepts/sui-move-concepts)

> On-chain party identity for [Sui](https://sui.io).

`miso_party` provides a reusable identity primitive for protocols that need to
represent people, groups, and organizations:

- **`Party`** — a named, capability-authorized identity that can represent an **individual** or a **group** of parties. Parties are extensible (other packages can attach data via dynamic fields) and own their lifecycle through a `PartyAdminCap`.

## Concepts

### Party

```move
let (party, cap) = party::new(party::new_individual_kind(), b"Ada".to_string(), ctx);
party.share(&cap); // make it a shared object
```

- Creation and sharing complete in one transaction. `new()` is silent; `share()` emits one `PartyCreatedEvent` from the final pre-share state.
- Individual or group (`new_individual_kind()` / `new_group_kind()`); groups hold member party IDs.
- All mutations, including naming and consent-based group membership, require the appropriate `PartyAdminCap`. Setting the name to its current value is a silent no-op.
- Extensible: holders of the cap can reach the party's `&mut UID` (`uid_mut`) to attach domain data.

### Events

An indexer can build and maintain a party's name, kind, member set and pending
invites from these events and the transaction envelope alone, with no object
reads:

| Event | Fields | Max size |
|---|---|---|
| `PartyCreatedEvent` | `party_id: ID`, `admin_cap_id: ID`, `name: String`, `is_group: bool` | 267 B |
| `PartyNameSetEvent` | `party_id: ID`, `name: String` | 234 B |
| `PartyGroupInviteCreatedEvent`, `…InviteDeclinedEvent`, `…InviteRevokedEvent` | `group_id: ID`, `member_id: ID` | 64 B |
| `PartyGroupMembershipAcceptedEvent`, `…MembershipLeftEvent`, `…MembershipRemovedEvent` | `group_id: ID`, `member_id: ID` | 64 B |

Names are at most 200 bytes. Each membership event is a delta applied in order:
an invite adds a pending invite; accepting removes it and adds the member;
declining or revoking removes it; leaving or removal drops the member. A group
is created empty, and members that join before `share()` appear as
`PartyGroupMembershipAcceptedEvent`s in the same transaction. Setting the
current name emits nothing.

`PartyCreatedEvent` carries the admin cap's ID, which is also
`sui::derived_object::derive_address(party_id, PartyAdminCapKey(party_id))`.
Sender and time come from the transaction.

### Errors

| Code | Constant | Meaning |
|---|---|---|
| 0 | `EUnauthorized` | The admin cap does not match the party |
| 1 | `ENotIndividualKind` | Operation requires an individual party |
| 2 | `ENotGroupKind` | Operation requires a group party |
| 3 | `EMaxGroupMembersExceeded` | Group already has 200 members |
| 4 | `EMaxNameLengthExceeded` | Name is longer than 200 bytes |
| 5 | `EEmptyString` | Name is empty |
| 6 | `EDuplicateParty` | Party is already a member |
| 7 | `EAlreadyInvited` | Party already has a pending invite to the group |
| 8 | `ENotGroupMember` | Party is not a member of the group |
| 9 | `ENoPendingInvite` | No pending invite for the party in the group |

## Install

```toml
[dependencies]
miso_party = { git = "https://github.com/misofm/party-protocol.git", rev = "<commit-sha>" }
```

Pin `rev` to the exact commit reviewed by your application. Party profile and
presentation slices live in
[misofm/party-protocol-extensions](https://github.com/misofm/party-protocol-extensions).

## TypeScript SDK

Party bindings, reads, and composable transaction builders are included in
[`@misofm/protocol`](https://github.com/misofm/sdks) and are exposed through
`client.miso.party`.

## Build & test

```sh
sui move build
sui move test
```

## Contributing

Issues and pull requests are welcome. By contributing you agree that your contributions are licensed under the project's Apache 2.0 license.

## License

[Apache 2.0](LICENSE) © Miso Labs, Inc.
