// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_party::test_helpers;

use std::string::String;
use miso_party::party::{Self, Party, PartyAdminCap, PartyKind};

public fun individual(ctx: &mut TxContext): (Party, PartyAdminCap) {
    individual_named(b"Test Artist".to_string(), ctx)
}

public fun individual_named(name: String, ctx: &mut TxContext): (Party, PartyAdminCap) {
    new_party(party::new_individual_kind(), name, ctx)
}

public fun group(ctx: &mut TxContext): (Party, PartyAdminCap) {
    new_party(party::new_group_kind(), b"Test Group".to_string(), ctx)
}

public fun long_string(len: u64): String {
    let mut s = vector<u8>[];
    len.do!(|_| s.push_back(65));
    s.to_string()
}

fun new_party(kind: PartyKind, name: String, ctx: &mut TxContext): (Party, PartyAdminCap) {
    party::new(kind, name, ctx)
}
