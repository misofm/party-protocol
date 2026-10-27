# Miso Party Protocol

A permissionless identity primitive on Sui, licensed under Apache 2.0.

`miso_party` gives people, bands, labels, and other entities a stable `Party`
identity. Core contains its ID and name, a matching administrative capability,
and the surface needed for optional extensions. It imposes no individual/group
classification or membership representation.

## Identity and Administration

```move
public struct Party has key {
    id: UID,
    name: String,
}
```

`party::new(name, ctx)` returns the Party and its `PartyAdminCap`. A Party is
key-only and must be shared with `party.share(&cap)` in the creating transaction.
Sharing emits `PartyCreatedEvent` with the final name and both object IDs.

Names are nonempty and at most 200 bytes. The administrator can change the name
without changing the identity. Names are unverified claims; applications choose
which identities they trust.

All administration checks the capability's stored `party_id` against the Party.
`party.authorize(&cap)` exposes that check with immutable references, allowing
extensions to authorize their own state without mutating the Party.
`party.uid_mut(&cap)` provides mutable UID access for attaching typed fields.
The capability is a transferable bearer object; possessing it grants authority.

## Optional Features

Data-model extensions live in
[party-protocol-extensions](https://github.com/misofm/party-protocol-extensions).
Group membership belongs to the optional `party_group` extension: its storage,
limits, invitations, consent rules, and membership events are outside core.
A Party remains usable without that extension or with another membership model.

## Events

| Event | Fields |
| --- | --- |
| `PartyCreatedEvent` | `party_id: ID`, `party_admin_cap_id: ID`, `name: String` |
| `PartyNameSetEvent` | `party_id: ID`, `name: String` |

Creation before sharing is silent. Setting the current name is an authorized,
validated no-op and emits no event. Sender and time come from the transaction.

## Errors

| Code | Constant | Meaning |
| --- | --- | --- |
| 0 | `EUnauthorized` | The capability does not match the Party |
| 4 | `EMaxNameLengthExceeded` | Name exceeds 200 bytes |
| 5 | `EEmptyString` | Name is empty |

The existing name-validation error codes are retained.

## Source Generation and Migration

This is a breaking source generation. It removes `PartyKind`, the `kind` field,
kind constructors and views, and all core group and invitation APIs. `new` no
longer takes a kind. `PartyCreatedEvent` no longer contains `is_group`.

Consumers targeting this generation must update constructor calls, generated
bindings, event decoding, and dependency pins. Group consumers use `party_group`
from a compatible extension generation. Existing immutable deployments and
pinned historical packages retain their previous layouts and behavior; no
on-chain migration or publication is performed by this source refactor.
`Published.toml` remains the record of the historical deployed generation.

## Build and Test

```sh
sui move build --lint --warnings-are-errors
sui move test --coverage
```

The tests cover creation, publication events, shared-object reads, name changes,
capability confusion, and extension UID access. Historical security reviews are
archived separately and do not cover this new generation.

## License

[Apache 2.0](LICENSE) © Miso Labs, Inc.
