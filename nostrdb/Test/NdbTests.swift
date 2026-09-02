//
//  NDBIterTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-07-21.
//

import XCTest
@testable import damus

func test_ndb_dir() -> String? {
    do {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        return remove_file_prefix(tempDir.absoluteString)
    } catch {
        return nil
    }
}

/// Signed kind-1 notes from two authors, author A's whole run first, then
/// author B's, with timestamps alternating between them. Used to prove that a
/// multi-author query comes back globally newest-first rather than concatenated
/// per author. Generated with nostrdb's ndb_builder + ndb_note_json.
///
/// The blank line before the closing delimiter is deliberate: ndb_process_events
/// only ingests newline-terminated lines, so an unterminated last line is dropped.
let multi_author_wire_events = """
["EVENT","s",{"id":"8ede1492ace7de2280697e2b6aba4d5928b56ad859ca9ef87001a8d49c52f636","pubkey":"32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8","created_at":1700000000,"kind":1,"tags":[],"content":"author A note 0","sig":"8dba0e3ce194b1bd43a5ace47bb7dec1daab6272d20d31b15757ebad62c6db0aa6c2f66410174f7bad74f1103bb69f8dd00b847e446de9883f041e0efdd17f0a"}]
["EVENT","s",{"id":"598227e5f74ff2be4853b222e2c892a936be91583308065ecbc8b43019b5f339","pubkey":"32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8","created_at":1700000002,"kind":1,"tags":[],"content":"author A note 1","sig":"56d99ab7d2e710c64c16e3c39af4fed0f600f43ca6b350af2f90b7d14115f7d49195d9757cb68f1c34e998a1a9e849de8749d4ae7858abea52d8688d29a7f593"}]
["EVENT","s",{"id":"1cf7a185a4e2b3b8798b30d63409a166d1a63485d73d4f828683c42bf1cc2d65","pubkey":"32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8","created_at":1700000004,"kind":1,"tags":[],"content":"author A note 2","sig":"f1a4be847cb4f8aeee907a570f9fb792a41b6f0fbf7b2f61f3ee9c23a3aa50a391ebdb658941de54a19ac29bedde039b022f0d27bc4e0f4f222b0eb8c7259e9a"}]
["EVENT","s",{"id":"8039257c1af0319d2ba934729fe9153d93f51a4ba060f46612daddeebc669095","pubkey":"32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8","created_at":1700000006,"kind":1,"tags":[],"content":"author A note 3","sig":"21eacd525b8ba2b604a25cdc65e55f8356df0d41a79448e86951882d924142d2278129cfa4225f683bbd6bba3fccb5996aac7d7567b2cac3b5ce1211284af48c"}]
["EVENT","s",{"id":"9c79f16ab1f3d5a2bcadd3a339f2c962f3e829ba2900d22135104de33d27ccc4","pubkey":"32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8","created_at":1700000008,"kind":1,"tags":[],"content":"author A note 4","sig":"8717a2cc0ae8ac08be269b6f7bc88a7e6d30c3f18757be924069de97fc846f24cdd0e8a6a720d08e8b168e751cdf3a4a9090f186bc1444f10f3e14b7a8e7b54b"}]
["EVENT","s",{"id":"ea8e930b61ba0283e76cf57e43f18ab6a38a769f8a0adf604ce8914a86d43699","pubkey":"32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8","created_at":1700000010,"kind":1,"tags":[],"content":"author A note 5","sig":"04504a4c941436e482ec8dbdc9293b2fa0a8694bf2b8a821f20266b75310b89f47bc946436f3b9e56304534db5b8bad58fa1d4a8785b5680fae5d70af43a5b5a"}]
["EVENT","s",{"id":"8862f48a6973b36e24cbf701195e74884c603f32524cc100f69bcb9ebb439f8d","pubkey":"32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8","created_at":1700000012,"kind":1,"tags":[],"content":"author A note 6","sig":"54138e7d89cc2b2e0870a21c5eefd8cc89dee0c8d434b15adfb4528af8424ba1123436006207c5db0236016557897bdf66949152ce846cc8721eac0f9f7d23be"}]
["EVENT","s",{"id":"684dbe1424f49f7a18f9a61e161b8fc90159a035c78de0faf3635f76e9b482d8","pubkey":"32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8","created_at":1700000014,"kind":1,"tags":[],"content":"author A note 7","sig":"0dd0e7a763740c197474f51e9535bbd25d79a405853bafabde20c531a8520b8c1f3a1250cab80417b86900eac3d1144e9a68f4d70a23a6882b74e381c363a45d"}]
["EVENT","s",{"id":"26f030d2eb8c4d822e48cab6894c260c930e167efb90dba623c6805635417a8e","pubkey":"51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3","created_at":1700000001,"kind":1,"tags":[],"content":"author B note 0","sig":"34d2717f81a3d212b48ad8349383bc698a643a4314742ca55019087052d10497ae34e1959cafa94a49a55048f668f6826f3d529796fecffc9f5988b3cecffe23"}]
["EVENT","s",{"id":"0627792fac88b3ea127a041aacbe860c7a9799a5e5aaa93e411d90eabfdb67f0","pubkey":"51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3","created_at":1700000003,"kind":1,"tags":[],"content":"author B note 1","sig":"9b00d0c9fe929c4ef70054b0e25260b8e11a583918cade431e57a6337ab6e9eb3c897fcd684aa5b2c3ebcd6f07f87e71f836f084aacaecb773dd01502998c0ed"}]
["EVENT","s",{"id":"c7033742235e3f7963c56c13f4243ec4c4ed2f4763a6749a9521ab621e64e7ed","pubkey":"51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3","created_at":1700000005,"kind":1,"tags":[],"content":"author B note 2","sig":"d9e917e08980a44d0b184dc1e81cfcd1bc4315b478cb536900a1564ee3a00a7a659df808ca049d592ce592bdadd5ccd608b56e8a486a3b16fc13a56c6af46866"}]
["EVENT","s",{"id":"cc5a81c45dd988d2bca6d50bedfc713081940f90d2cd281341a524c1910dbf6d","pubkey":"51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3","created_at":1700000007,"kind":1,"tags":[],"content":"author B note 3","sig":"f98bb0096cdf33aeae9b8192592bf429755ffa1566b707661ec92f9ec3716f518158c019326c71fb4992038f7de330bffb817fb2dc06e748a66ed10a046b6080"}]
["EVENT","s",{"id":"ec5353f54c3928d9faccf0c83e61e192ff05512d000acaf6dac10dc48f8b0668","pubkey":"51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3","created_at":1700000009,"kind":1,"tags":[],"content":"author B note 4","sig":"0884d4d168e848573382da7c59835c93ec3dbe798d06bfcbc7626784a4096c1213f1d506a07890a2d2236578f23f2ac62a387e4a6df22420a3a761c663656d99"}]
["EVENT","s",{"id":"64704a71e36577007402f6a0dcd975017b20bedb78c70df89291a9122fdeed5d","pubkey":"51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3","created_at":1700000011,"kind":1,"tags":[],"content":"author B note 5","sig":"4ee58f2a7036e0ca895983bef2ab849182c3b5919f7584fe7b9350ae2568f74d0693809f3fa6f31173ca660996ef7e0317a4ac9232c7c139f1de65437fe36bbd"}]
["EVENT","s",{"id":"2e996e4e15040e1edaa906ddb578fb96831a14b2a903f2cdf65e9b801bfcd405","pubkey":"51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3","created_at":1700000013,"kind":1,"tags":[],"content":"author B note 6","sig":"32c329728675c64fb17a100110d4c18730d9cc927c605723cdc3a2282f79020591c693cda0cb3b072e37148ce1baa7d93d77f555d24929e64ec1482879b22140"}]
["EVENT","s",{"id":"24be2bb86066c653ff3334190e0e118829a9b6e38eeae3cf1797c788bb72f3bb","pubkey":"51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3","created_at":1700000015,"kind":1,"tags":[],"content":"author B note 7","sig":"88f4f80d9f1d13cad2d2e802c906905418f74e27d7ffea60f638115696117b229af43b0b142a762d9be4c75615bd3faa33ac3cf5ccbb013e9a67a888b5c203c7"}]

"""

final class NdbTests: XCTestCase {
    var db_dir: String = ""

    /// Saves and clears thread-local transaction state for deterministic transaction tests, then returns a restoration closure.
    @discardableResult
    private func resetThreadLocalTransactionState() -> () -> Void {
        let threadDictionary = Thread.current.threadDictionary
        let originalTxn = threadDictionary["ndb_txn"]
        let originalRefCount = threadDictionary["ndb_txn_ref_count"]
        let originalGeneration = threadDictionary["txn_generation"]
        threadDictionary.removeObject(forKey: "ndb_txn")
        threadDictionary.removeObject(forKey: "ndb_txn_ref_count")
        threadDictionary.removeObject(forKey: "txn_generation")

        return {
            if let originalTxn {
                threadDictionary["ndb_txn"] = originalTxn
            } else {
                threadDictionary.removeObject(forKey: "ndb_txn")
            }
            if let originalRefCount {
                threadDictionary["ndb_txn_ref_count"] = originalRefCount
            } else {
                threadDictionary.removeObject(forKey: "ndb_txn_ref_count")
            }
            if let originalGeneration {
                threadDictionary["txn_generation"] = originalGeneration
            } else {
                threadDictionary.removeObject(forKey: "txn_generation")
            }
        }
    }

    override func setUpWithError() throws {
        guard let db = test_ndb_dir() else {
            XCTFail("Could not create temp directory")
            return
        }
        db_dir = db
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_decode_eose() throws {
        let json = "[\"EOSE\",\"DC268DBD-55DA-458A-B967-540925AF3497\"]"
        let resp = decode_nostr_event(txt: json)
        XCTAssertNotNil(resp)
    }

    func test_decode_command_result() throws {
        let json = "[\"OK\",\"b1d8f68d39c07ce5c5ea10c235100d529b2ed2250140b36a35d940b712dc6eff\",true,\"\"]"
        let resp = decode_nostr_event(txt: json)
        XCTAssertNotNil(resp)

    }

    func test_profile_creation() {
        let profile = make_test_profile()
        XCTAssertEqual(profile.name, "jb55")
    }

    func test_ndb_init() {

        do {
            let ndb = Ndb(path: db_dir)!
            let ok = ndb.process_events(test_wire_events)
            XCTAssertTrue(ok)
        }

        do {
            let ndb = Ndb(path: db_dir)!
            let id = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!
            let note = try? ndb.lookup_note_and_copy(id)
            XCTAssertNotNil(note)
            guard let note else { return }
            let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
            XCTAssertEqual(note.pubkey, pk)

            let profile = try? ndb.lookup_profile_and_copy(pk)
            let lnurl = try? ndb.lookup_profile_lnurl(pk)
            XCTAssertNotNil(profile)
            guard let profile else { return }

            XCTAssertEqual(profile.name, "jb55")
            XCTAssertEqual(lnurl, nil)
        }


    }

    func test_ndb_search() throws {
        do {
            let ndb = Ndb(path: db_dir)!
            let ok = ndb.process_events(test_wire_events)
            XCTAssertTrue(ok)
        }
        
        do {
            let ndb = Ndb(path: db_dir)!
            let note_ids = (try? ndb.text_search(query: "barked")) ?? []
            XCTAssertEqual(note_ids.count, 1)
            let expected_note_id = NoteId(hex: "b17a540710fe8495b16bfbaf31c6962c4ba8387f3284a7973ad523988095417e")!
            guard note_ids.count > 0 else {
                XCTFail("Expected at least one note to be found")
                return
            }
            let note_id = try? ndb.lookup_note_by_key(note_ids[0], borrow: { maybeUnownedNote -> NoteId? in
                switch maybeUnownedNote {
                case .none: return nil
                case .some(let unownedNote): return unownedNote.id
                }
            })
            XCTAssertEqual(note_id, .some(expected_note_id))
        }
    }

    // MARK: - Filtered text search (ndb_text_search_with)

    /// The three kind-1 notes from `test_wire_events` that reach the fulltext index.
    ///
    /// All three are of the form "a quick brown fox <verb phrase> the lazy
    /// {dog,cat}", by three different authors. ``jumped`` and ``barked`` are ten
    /// seconds apart; ``jumped_at_cat`` is a little over twelve minutes later, so
    /// it sorts newest.
    private enum SearchFixture {
        /// "a quick brown fox jumped over the lazy dog"
        static let jumped = (
            id: NoteId(hex: "8f68cdc0c72dcf5c37868428cb477f28b13b1561e717f92053921b3b3c4ab712")!,
            author: Pubkey(hex: "ba4b26df771a0839d5a26550ada6ac19547e164136994951d2d5c5815993a28e")!,
            created_at: UInt32(1701187327)
        )
        /// "a quick brown fox barked at the lazy dog"
        static let barked = (
            id: NoteId(hex: "b17a540710fe8495b16bfbaf31c6962c4ba8387f3284a7973ad523988095417e")!,
            author: Pubkey(hex: "df51637b1a19115d6c532081461a3e24f19b02f15815771dd26de2617fe2ea90")!,
            created_at: UInt32(1701187337)
        )
        /// "a quick brown fox jumped over the lazy cat"
        static let jumped_at_cat = (
            id: NoteId(hex: "35c717f1d905b05e16868107f78ec013399b01e9dcdd40fcaf8112b3d1f63ad4")!,
            author: Pubkey(hex: "381eac026b7d3053236eef30c1a3cd0674809d050b1ba9f05c694efb5ea002d4")!,
            created_at: UInt32(1701188103)
        )
    }

    /// Ingests `test_wire_events` and hands back a freshly opened Ndb to search.
    private func ndb_with_search_fixture() throws -> Ndb {
        do {
            let ndb = try XCTUnwrap(Ndb(path: db_dir))
            XCTAssertTrue(ndb.process_events(test_wire_events))
        }
        return try XCTUnwrap(Ndb(path: db_dir))
    }

    private func note_ids(_ ndb: Ndb, _ results: [Ndb.TextSearchResult]) throws -> [NoteId] {
        return try results.map { result in
            try XCTUnwrap(ndb.lookup_note_by_key(result.noteKey, borrow: { maybeNote -> NoteId? in
                switch maybeNote {
                case .none: return nil
                case .some(let note): return note.id
                }
            }))
        }
    }

    /// An `authors` filter narrows a text search to that author's notes. Both
    /// fixture notes match "quick brown fox"; only one is by this author.
    func test_ndb_search_with_author_filter() throws {
        let ndb = try ndb_with_search_fixture()

        let unfiltered = try ndb.text_search(query: "quick brown fox", filter: nil)
        XCTAssertEqual(try note_ids(ndb, unfiltered),
                       [SearchFixture.jumped_at_cat.id, SearchFixture.barked.id, SearchFixture.jumped.id],
                       "every fixture note contains 'quick brown fox'")

        let filter = try NdbFilter(from: NostrFilter(authors: [SearchFixture.jumped.author]))
        let filtered = try ndb.text_search(query: "quick brown fox", filter: filter)
        XCTAssertEqual(try note_ids(ndb, filtered), [SearchFixture.jumped.id])

        // and an author with nothing indexed matches nothing, rather than falling
        // back to the unfiltered result set
        let stranger = try NdbFilter(from: NostrFilter(authors: [test_pubkey]))
        XCTAssertEqual(try ndb.text_search(query: "quick brown fox", filter: stranger).count, 0)
    }

    /// `since`/`until` on the filter bracket the results. nostrdb treats `since` as
    /// inclusive and `until` as exclusive (`created_at < until`).
    func test_ndb_search_with_date_range_filter() throws {
        let ndb = try ndb_with_search_fixture()

        func search(_ filter: NostrFilter) throws -> [NoteId] {
            return try note_ids(ndb, try ndb.text_search(query: "quick brown fox", filter: try NdbFilter(from: filter)))
        }

        // `since` alone drops everything older than it.
        XCTAssertEqual(try search(NostrFilter(since: SearchFixture.barked.created_at)),
                       [SearchFixture.jumped_at_cat.id, SearchFixture.barked.id])
        // `until` alone drops everything at or newer than it.
        XCTAssertEqual(try search(NostrFilter(until: SearchFixture.barked.created_at)),
                       [SearchFixture.jumped.id])
        // a window containing exactly two of the three
        XCTAssertEqual(try search(NostrFilter(since: SearchFixture.jumped.created_at,
                                              until: SearchFixture.barked.created_at + 1)),
                       [SearchFixture.barked.id, SearchFixture.jumped.id])
        // a window containing none of them
        XCTAssertEqual(try search(NostrFilter(since: SearchFixture.jumped_at_cat.created_at + 1)), [])
    }

    /// Each hit carries the matched note's `created_at`, so a caller can page on it
    /// without looking the note up.
    func test_ndb_search_results_carry_timestamps() throws {
        let ndb = try ndb_with_search_fixture()

        let results = try ndb.text_search(query: "quick brown fox", filter: nil)
        XCTAssertEqual(results.count, 3)

        for result in results {
            let created_at = try XCTUnwrap(ndb.lookup_note_by_key(result.noteKey, borrow: { maybeNote -> UInt32? in
                switch maybeNote {
                case .none: return nil
                case .some(let note): return note.createdAt
                }
            }))
            XCTAssertEqual(result.timestamp, UInt64(created_at),
                           "the hit's timestamp must be the note's created_at")
        }

        XCTAssertEqual(results.map(\.timestamp),
                       [UInt64(SearchFixture.jumped_at_cat.created_at),
                        UInt64(SearchFixture.barked.created_at),
                        UInt64(SearchFixture.jumped.created_at)],
                       "newest-first by default")

        let ascending = try ndb.text_search(query: "quick brown fox", filter: nil, order: .oldest_first)
        XCTAssertEqual(ascending.map(\.timestamp),
                       [UInt64(SearchFixture.jumped.created_at),
                        UInt64(SearchFixture.barked.created_at),
                        UInt64(SearchFixture.jumped_at_cat.created_at)])
    }

    /// nostrdb parses at most `Ndb.max_text_search_words` words from a query and
    /// silently drops the rest, so an over-long query is matched on its first N
    /// words only — which widens the result set rather than narrowing it, since
    /// matching is an AND over the parsed words.
    func test_ndb_search_drops_words_past_the_cap() throws {
        let ndb = try ndb_with_search_fixture()
        XCTAssertEqual(Ndb.max_text_search_words, 8)

        // Exactly at the cap: all eight words are honoured, and the note matches.
        let eight = "quick brown fox jumped over the lazy dog"
        XCTAssertEqual(eight.split(separator: " ").count, 8)
        XCTAssertEqual(try note_ids(ndb, try ndb.text_search(query: eight, filter: nil)),
                       [SearchFixture.jumped.id])

        // Control: swapping the 8th word for one no note contains does narrow to
        // nothing, so the cap really is 8 rather than "trailing words are ignored".
        XCTAssertEqual(try ndb.text_search(query: "quick brown fox jumped over the lazy badger", filter: nil).count, 0)

        // One past the cap: the 9th word would have excluded the note, but it is
        // dropped, so the results are the 8-word results unchanged.
        XCTAssertEqual(try note_ids(ndb, try ndb.text_search(query: eight + " cat", filter: nil)),
                       [SearchFixture.jumped.id],
                       "the 9th query word must be dropped, not matched")
    }

    /// `limit` is clamped to the fixed size of nostrdb's result struct, so an
    /// oversized limit is harmless rather than a buffer overrun.
    func test_ndb_search_clamps_limit() throws {
        let ndb = try ndb_with_search_fixture()

        XCTAssertEqual(Ndb.max_text_search_results, 128)
        XCTAssertEqual(try ndb.text_search(query: "quick brown fox", filter: nil, limit: 10_000).count, 3)
        XCTAssertEqual(try ndb.text_search(query: "quick brown fox", filter: nil, limit: 1).count, 1)

        // a `limit` on the filter narrows it further
        let filter = try NdbFilter(from: NostrFilter(limit: 1))
        XCTAssertEqual(try ndb.text_search(query: "quick brown fox", filter: filter).count, 1)
    }

    /// A `search` field on a `NostrFilter` survives conversion to an `ndb_filter`,
    /// which is what routes `ndb_query` onto its SEARCH plan.
    func test_nostr_filter_carries_search() throws {
        let filter = NostrFilter(kinds: [.text], search: "quick brown fox")
        XCTAssertNoThrow(try NdbFilter(from: filter))

        let encoded = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(NostrFilter.self, from: encoded)
        XCTAssertEqual(decoded.search, "quick brown fox")

        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains("\"search\""), "NIP-50 coding key must be `search`, got \(json)")
    }

    /// Phase 0 regression guard: a `{kinds:[1], authors:[a, b]}` query must be
    /// served by nostrdb's AUTHOR_KINDS plan, whose index merger interleaves the
    /// per-author runs and yields strictly newest-first. Before the upstream sync
    /// the plan was gated to a single author and concatenated author A's whole run
    /// ahead of author B's, so a multi-author result list was not globally ordered.
    /// The fixture deliberately ingests A's entire run before B's, and their
    /// timestamps alternate, so a concatenating plan would come back out of order.
    func test_multi_author_query_is_newest_first() throws {
        let author_a = try XCTUnwrap(Pubkey(hex: "32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8"))
        let author_b = try XCTUnwrap(Pubkey(hex: "51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3"))

        do {
            let ndb = try XCTUnwrap(Ndb(path: db_dir))
            XCTAssertTrue(ndb.process_events(multi_author_wire_events))
        }

        let ndb = try XCTUnwrap(Ndb(path: db_dir))
        let filter = NostrFilter(kinds: [.text], authors: [author_a, author_b])
        let keys = try ndb.query(filters: [try NdbFilter(from: filter)], maxResults: 64)

        XCTAssertEqual(keys.count, 16, "expected every note from both authors")

        var seen: [(created_at: UInt32, pubkey: Pubkey)] = []
        for key in keys {
            let row = try ndb.lookup_note_by_key(key, borrow: { maybeNote -> (UInt32, Pubkey)? in
                switch maybeNote {
                case .none: return nil
                case .some(let note): return (note.createdAt, note.pubkey)
                }
            })
            seen.append(try XCTUnwrap(row))
        }

        // strictly newest-first
        for (earlier, later) in zip(seen, seen.dropFirst()) {
            XCTAssertGreaterThan(earlier.created_at, later.created_at,
                                 "results must be strictly descending by created_at")
        }

        // interleaved rather than concatenated: with alternating timestamps every
        // adjacent pair should switch author. A concatenating plan switches once.
        let switches = zip(seen, seen.dropFirst()).filter { $0.0.pubkey != $0.1.pubkey }.count
        XCTAssertEqual(switches, 15,
                       "results must interleave across authors, not concatenate per author")
    }

    func test_ndb_note() throws {
        let note = NdbNote.owned_from_json(json: test_contact_list_json)
        XCTAssertNotNil(note)
        guard let note else { return }

        let id = NoteId(hex: "20d0ff27d6fcb13de8366328c5b1a7af26bcac07f2e558fbebd5e9242e608c09")!
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        XCTAssertEqual(note.id, id)
        XCTAssertEqual(note.pubkey, pubkey)

        XCTAssertEqual(note.count, 34328)
        XCTAssertEqual(note.kind, 3)
        XCTAssertEqual(note.created_at, 1689904312)

        let expected_count: UInt16 = 786
        XCTAssertEqual(note.tags.count, expected_count)
        XCTAssertEqual(note.tags.reduce(0, { sum, _ in sum + 1 }), expected_count)

        var tags = 0
        var total_count_stored = 0
        var total_count_iter = 0
        //let tags = note.tags()
        for tag in note.tags {
            total_count_stored += Int(tag.count)

            if tags == 0 || tags == 1 || tags == 2 {
                XCTAssertEqual(tag.count, 3)
            }

            if tags == 6 {
                XCTAssertEqual(tag.count, 2)
            }

            if tags == 7 {
                XCTAssertEqual(tag[2].string(), "wss://nostr-pub.wellorder.net")
            }

            for elem in tag {
                //print("tag[\(tags)][\(elem.index)]")
                total_count_iter += 1
            }

            tags += 1
        }

        XCTAssertEqual(tags, 786)
        XCTAssertEqual(total_count_stored, total_count_iter)
    }
    
    /// Based on https://github.com/damus-io/damus/issues/1468
    /// Tests whether a JSON with optional escaped slash characters is correctly unescaped (In accordance to https://datatracker.ietf.org/doc/html/rfc8259#section-7)
    func test_decode_json_with_escaped_slashes() {
        let testJSONWithEscapedSlashes = "{\"tags\":[],\"pubkey\":\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\",\"content\":\"https:\\/\\/cdn.nostr.build\\/i\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg\",\"created_at\":1691864981,\"kind\":1,\"sig\":\"fc0033aa3d4df50b692a5b346fa816fdded698de2045e36e0642a021391468c44ca69c2471adc7e92088131872d4aaa1e90ea6e1ad97f3cc748f4aed96dfae18\",\"id\":\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\"}"
        let testNote = NdbNote.owned_from_json(json: testJSONWithEscapedSlashes)!
        XCTAssertEqual(testNote.content, "https://cdn.nostr.build/i/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg")
    }
    
    func test_inherited_transactions() throws {
        let ndb = Ndb(path: db_dir)!
        do {
            guard let txn1 = NdbTxn(ndb: ndb) else { return XCTAssert(false) }

            let ntxn = (Thread.current.threadDictionary.value(forKey: "ndb_txn") as? ndb_txn)!
            XCTAssertEqual(txn1.txn.lmdb, ntxn.lmdb)
            XCTAssertEqual(txn1.txn.mdb_txn, ntxn.mdb_txn)

            guard let txn2 = NdbTxn(ndb: ndb) else { return XCTAssert(false) }

            XCTAssertEqual(txn1.inherited, false)
            XCTAssertEqual(txn2.inherited, true)
        }

        let ndb_txn = Thread.current.threadDictionary.value(forKey: "ndb_txn")
        XCTAssertNil(ndb_txn)
    }
    
    /// Verifies that a failed top-level SafeNdbTxn creation fully cleans up thread-local transaction state.
    func testSafeNdbTxnFailure_cleansUpTopLevelThreadLocalTransactionState() throws {
        let restoreThreadLocalTransactionState = resetThreadLocalTransactionState()
        defer { restoreThreadLocalTransactionState() }

        let ndb = try XCTUnwrap(Ndb(path: db_dir))

        let txn = SafeNdbTxn<Int>.new(on: ndb, with: { _ in nil }, name: "failing_top_level_txn")

        XCTAssertNil(txn)
        XCTAssertNil(Thread.current.threadDictionary["ndb_txn"], "Top-level SafeNdbTxn failure should clear the thread-local transaction")
        XCTAssertNil(Thread.current.threadDictionary["ndb_txn_ref_count"], "Top-level SafeNdbTxn failure should clear the thread-local reference count")
        XCTAssertNil(Thread.current.threadDictionary["txn_generation"], "Top-level SafeNdbTxn failure should clear the thread-local generation")
    }
    
    /// Verifies that a failed inherited SafeNdbTxn creation decrements the ref-count without clearing the parent transaction.
    func testSafeNdbTxnFailure_onInheritedTransactionRestoresParentThreadLocalState() throws {
        let restoreThreadLocalTransactionState = resetThreadLocalTransactionState()
        defer { restoreThreadLocalTransactionState() }

        let ndb = try XCTUnwrap(Ndb(path: db_dir))

        let parent = try XCTUnwrap(SafeNdbTxn<Int>.new(on: ndb, with: { _ in 1 }, name: "parent_txn"))
        let parentThreadTxn = Thread.current.threadDictionary["ndb_txn"] as? ndb_txn
        XCTAssertNotNil(parentThreadTxn)
        XCTAssertEqual(Thread.current.threadDictionary["ndb_txn_ref_count"] as? Int, 1)

        let child = SafeNdbTxn<Int>.new(on: ndb, with: { _ in nil }, name: "failing_child_txn")

        XCTAssertNil(child)
        let restoredThreadTxn = Thread.current.threadDictionary["ndb_txn"] as? ndb_txn
        XCTAssertNotNil(restoredThreadTxn, "Inherited SafeNdbTxn failure should keep the parent transaction installed")
        XCTAssertEqual(restoredThreadTxn?.lmdb, parentThreadTxn?.lmdb)
        XCTAssertEqual(restoredThreadTxn?.mdb_txn, parentThreadTxn?.mdb_txn)
        XCTAssertEqual(Thread.current.threadDictionary["ndb_txn_ref_count"] as? Int, 1, "Inherited SafeNdbTxn failure should restore the parent ref-count")
        XCTAssertEqual(Thread.current.threadDictionary["txn_generation"] as? Int, ndb.generation)

        _ = parent
    }

    func test_decode_perf() throws {
        // This is an example of a performance test case.
        self.measure {
            _ = NdbNote.owned_from_json(json: test_contact_list_json)
        }
    }

    func test_perf_old_decoding() {
        self.measure {
            let event = decode_nostr_event_json(test_contact_list_json)
            XCTAssertNotNil(event)
        }
    }

    func test_perf_old_iter()  {
        self.measure {
            let event = decode_nostr_event_json(test_contact_list_json)
            XCTAssertNotNil(event)
        }
    }

    func longer_iter(_ n: Int = 1000) -> XCTMeasureOptions {
        let opts = XCTMeasureOptions()
        opts.iterationCount = n
        return opts
    }

    func test_iteration_perf() throws {
        guard let note = NdbNote.owned_from_json(json: test_contact_list_json) else {
            XCTAssert(false)
            return
        }


        self.measure {
            var count = 0
            var char_count = 0

            for tag in note.tags {
                for elem in tag {
                    //print("iter_elem \(elem.string())")
                    for c in elem {
                        if char_count == 0 {
                            let ac = AsciiCharacter(c)
                            XCTAssertEqual(ac, "p")
                        } else if char_count == 0 {
                            XCTAssertEqual(c, 0x6c)
                        }
                        char_count += 1
                    }
                }
                count += 1
            }

            XCTAssertEqual(count, 786)
            XCTAssertEqual(char_count, 24370)
        }

    }

}

