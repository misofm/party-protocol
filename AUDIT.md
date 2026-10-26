> Historical audit record: the group-extension refactor removes PartyKind,
> group state, and membership operations from core and adds public read-only
> capability authorization. The audit below predates that refactor and must not
> be treated as an audit of this source generation. See README.md for the new
> boundary and migration notes.

# Security Audit — `miso_party`

Audited at `7e2f64f604e21e2662d6b4aaaa0446de27bfd58f` (2026-10-21). Scope: package `miso_party`, module `party` (`sources/party.move`, 313 lines); framework pinned at `719fb2960ccfbf9f4d33041f8ea5146d30671696` (`Move.lock`), no other dependencies.

## What it does

`Party` is a shared, `key`-only identity object (individual or group) with a name, administered through a `PartyAdminCap` that is a derived object of the party. Group membership is a two-sided invite/accept protocol kept in module-private dynamic fields on both parties; `is_member` is the authorization primitive extensions read. See [README](README.md).

## Trust model

- **Cap holder** (`PartyAdminCap`, `key + store`, transferable, no burn or rotation): `share`, `set_name`, `uid_mut`; as a group admin `invite_party`, `revoke_invite`, `remove_member`; as a member `accept_invite`, `decline_invite`, `leave`. Through `uid_mut` the holder can attach any dynamic field or derived object and can `transfer::receive` objects sent to the party's address, so the party address is a cap-controlled account.
- **Anyone**: `new` (returns party and cap; the party must be shared in the same transaction because `Party` has no `store` or `drop`), all view functions, `uid` (read-only `&UID`).
- **Nobody**: delete, transfer, wrap or freeze a `Party`; change its kind; construct `PartyKind::Group` with members (only `new_group_kind` builds an empty one); construct `PartyAdminCapKey`, `PendingInviteKey`, `PendingMembershipKey` or `MembershipKey` outside the module, so no `uid_mut` holder can forge or scrub invite or membership state or re-claim the cap; make a party a member without its own cap (`accept_invite`, `party.move:212-213`).

## Findings

- **F1 (Info, Accepted) `invite_party` writes to the invited party without its cap.** `df::add(&mut member.id, PendingMembershipKey(group_id), true)` (`party.move:208`) uses the module's field privilege. The value is a unit marker the member can remove at will via `decline_invite`, the inviter pays the storage, and the storage rebate on removal goes to whoever removes it. No funds or state of the member are affected.
- **F2 (Info, Accepted) Pending invites are unbounded.** `MAX_GROUP_MEMBERS` bounds members at invite (`party.move:204`) and again at accept (`party.move:220`) but not pending invites, so a group admin can grow both parties' dynamic-field stores at their own expense, and many groups can target one member. Lookups are O(1) and nothing iterates pending fields; over-inviting degrades to `EMaxGroupMembersExceeded` at accept.
- **F3 (Info, Open) No cap recovery.** `PartyAdminCap` (`party.move:40-43`) has no burn, rotation or re-issue path, and `claim` under `PartyAdminCapKey(party_id)` (`party.move:121`) can run only once per party. A lost or stuck cap permanently freezes the party's name, extension writes and its side of membership; counterparties keep their own exits (`leave`, `remove_member`, `decline_invite`), but a lost group cap leaves its pending invites revocable only by the invitees.
- **F4 (Info, Open) Events for a party can precede its `PartyCreatedEvent`.** `set_name`, `invite_party` and `accept_invite` may run on an unshared party and emit (`party.move:194, 209, 223`) before `share` emits `PartyCreatedEvent` (`party.move:129-134`) in the same transaction. Indexers that apply events strictly in order must tolerate a `party_id` they have not yet seen, or process a transaction's events as a batch. The README's "delta applied in order" model is otherwise exact.

No Critical, High, Medium or Low findings.

## Checked, no finding

- **Cap binding.** Every mutator calls `authorize`, which compares `cap.party_id` to the object ID (`party.move:269-271`). Group operations check the group's cap, member operations the member's cap (`party.move:198, 213, 227, 236, 245, 254, 263`). Wrong-cap probes on all eight cap-gated entry points abort `EUnauthorized`.
- **Two-sided consistency.** Pending markers are written together (`party.move:207-208`) and removed together only in `consume_invite` (`party.move:283-285`); the group-side `exists` check guards both removes because no other writer exists. Membership is inserted on both sides (`party.move:221-222`) and removed on both only in `remove_membership` (`party.move:292-294`) after a `contains` check. Probed: decline then revoke, revoke then re-invite, leave then re-invite, remove then re-invite.
- **Role and kind confusion.** Members must be `Individual` (`party.move:202`) and the inviter a group (`party.move:201`); `PartyKind` is set once in `new`. An individual passed as `group` to `revoke_invite`, `decline_invite`, `leave` or `remove_member` aborts (`ENoPendingInvite` or `ENotGroupKind`) because individuals never hold `PendingInviteKey` or a member set. Duplicate membership is pre-checked (`party.move:203`) and `VecSet::insert` would abort anyway. Self-invite is impossible: one object cannot be passed twice as `&mut`.
- **Key unforgeability.** The four key types are positional structs with private fields (`party.move:45-51`); construction from another module fails to compile (`restricted visibility`), as does `PartyKind::Group(...)`. A same-shape key type in another module hashes to a different field and a different derived address (probed). Framework `Claimed` and `DerivedObjectKey` are likewise private, so the derived-object marker cannot be removed through `uid_mut`.
- **Object lifecycle.** `Party` is `key`-only, never deleted, and its only consumer is `share` (`party.move:127-136`); so the cap's derived address can never be re-claimed and `claim` cannot collide (one key per party).
- **Validation and abort order.** Name 1–200 bytes in `new` and `set_name` (`party.move:111-112, 190-191`); equal-name write is a silent no-op after authorization (`party.move:192`). Abort order in `invite_party`: `EUnauthorized`, `ENotGroupKind`, `ENotIndividualKind`, `EDuplicateParty`, `EMaxGroupMembersExceeded`, `EAlreadyInvited`; in `accept_invite`: `EUnauthorized`, `ENotGroupKind`, `ENoPendingInvite`, `EMaxGroupMembersExceeded`. All ten codes are reachable and tested; the README table matches.
- **Events.** Each state change emits exactly one event with the fields the README lists; sizes match BCS (`PartyCreatedEvent` 267 B, `PartyNameSetEvent` 234 B, membership events 64 B). `party_admin_cap_id` equals `derive_address(party_id, PartyAdminCapKey(party_id))` (tested).
- **Limits.** Member set ≤ 200 IDs (6.4 KB in-object); all operations are O(1) or O(200); no loops over dynamic fields; no arithmetic.
- **Money.** None held or moved by the module.

## Operational requirements

- Share every party returned by `new` in the same programmable transaction; otherwise the transaction fails.
- Every membership operation mutates two shared objects; expect consensus sequencing on both.
- Indexers: process a transaction's events as a batch (F4) and treat the cap holder, not the transaction sender, as the party's authority.
- Keep the `PartyAdminCap` safe; there is no recovery (F3).

## Verification

- `sui move test --coverage`: 37/37 passed, 0 warnings; `sui move coverage summary`: 100.00 % of `party`.
- `sui move build -e mainnet` and `-e testnet`: both succeed (sui 1.82.1).
- Throwaway probes (not committed): 12 tests covering wrong caps on every entry point, role confusion, invite/leave/remove cycles, event ordering before `share`, receiving objects through `uid_mut`, and foreign same-shape key types; plus two compile-fail probes for key and `PartyKind::Group` construction.
