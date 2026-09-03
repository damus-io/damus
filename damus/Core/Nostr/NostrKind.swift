//
//  NostrKind.swift
//  damus
//
//  Created by William Casarin on 2022-04-27.
//

import Foundation


/// A known Nostr event kind, addressable by name, with the actual number assigned by the protocol as the value
enum NostrKind: UInt32, Codable {
    case metadata = 0
    case text = 1
    case contacts = 3
    /// A legacy NIP-04 direct message.
    case dm = 4
    case delete = 5
    case boost = 6
    case like = 7
    /// A NIP-59 seal: the sender-signed, NIP-44 encrypted envelope around a rumor.
    ///
    /// We never read one of these directly — nostrdb's ingester peels the seal and
    /// stores the rumor inside it. The kind is here for filters and completeness.
    case seal = 13
    /// A NIP-17 private direct message, i.e. the rumor sealed inside a ``seal``.
    ///
    /// Notes of this kind only ever reach the database by way of nostrdb unwrapping a
    /// ``giftwrap``, so they are always rumors: unsigned, with the sender's pubkey copied
    /// from the seal and the signature field repurposed (see ``NdbNote/is_rumor``).
    /// They must never be sent to a relay.
    case private_dm = 14
    case chat = 42
    /// A NIP-59 giftwrap: the ephemerally-signed outer wrapper around a ``seal``.
    ///
    /// Its `created_at` is deliberately randomized noise (up to ~2 days off), so order
    /// conversations by the rumor's `created_at`, never the wrap's.
    case giftwrap = 1059
    case live_chat = 1311
    case mute_list = 10000
    case relay_list = 10002
    /// A NIP-17 DM inbox relay list: the relays a user wants their private messages delivered to.
    ///
    /// This is *not* the NIP-65 ``relay_list``. A NIP-17 giftwrap has to reach the relays the
    /// recipient actually reads DMs from, which may be a small, private set they never publish as
    /// write relays — so publishing to our own write relays instead is valid but, for anyone whose
    /// inbox relays we do not happen to be connected to, undeliverable.
    ///
    /// The tags are a flat list of `["relay", "<url>"]`, with no read/write markers: every relay in
    /// the list is an inbox.
    case dm_relay_list = 10050
    case interest_list = 10015
    case list_deprecated = 30000
    case draft = 31234
    case longform = 30023
    case zap = 9735
    case zap_request = 9734
    case highlight = 9802
    case nwc_request = 23194
    case nwc_response = 23195
    case http_auth = 27235
    case live = 30311
    case status = 30315
    case contact_card = 30_382
    case follow_list = 39089
}

extension NostrKind {
    /// How far into the past NIP-59 randomizes a ``giftwrap``'s `created_at`.
    ///
    /// NIP-59 says the wrap's timestamp "SHOULD be tweaked to thwart time-analysis attacks", up to two
    /// days in the past, so a relay operator cannot correlate wraps by send time. Any `since` bound
    /// applied to giftwraps therefore has to be moved back by at least this much, or a freshly
    /// published wrap whose fake timestamp lands behind the bound is filtered out by the relay and
    /// never reaches us.
    static let giftwrapCreatedAtFuzzWindow: UInt32 = 2 * 24 * 60 * 60
}
