// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_party::test_helpers;

use std::string::String;
use miso_party::party::{Self, Party, PartyAdminCap};

public fun party(ctx: &mut TxContext): (Party, PartyAdminCap) {
    party::new(b"Test Artist".to_string(), ctx)
}

public fun long_string(len: u64): String {
    let mut s = vector<u8>[];
    len.do!(|_| s.push_back(65));
    s.to_string()
}
