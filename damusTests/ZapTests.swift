//
//  ZapTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-01-16.
//

import XCTest
@testable import damus

final class ZapTests: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func test_alby_zap() throws {
        let zapjson = "eyJjb250ZW50Ijoi4pqhTm9uLWN1c3RvZGlhbCB6YXAgZnJvbSBteSBBbGJ5IEh1YiIsImNyZWF0ZWRfYXQiOjE3MjQ2ODUwNDcsImlkIjoiNGM3NWFiMWU3MDk4Y2NiN2FlYjhmZjdkNDIwMjM2ZDM1N2U1OGNjZmI3OWZiZTEwMTcwNGNiMzY0OTg3YjY4YSIsImtpbmQiOjk3MzUsInB1YmtleSI6Ijc5ZjAwZDNmNWExOWVjODA2MTg5ZmNhYjAzYzFiZTRmZjgxZDE4ZWU0ZjY1M2M4OGZhYzQxZmUwMzU3MGY0MzIiLCJzaWciOiI3OWM5ZDJjN2ExZWI1NmNhZjMyOTY1ZTRkMDJlYjJiYjFmYTY3NGViMDM4ZWE2MmFjZTg2YzBiMzA2OTJhMjU0YWU0M2JhNmMzNjcyMDJkZjgxNzQ5NGNhNTg4NzRkNWI1OWMxY2VhMDdjZTk5Mjk0MmIyOWYwZmVlZmJlM2FiZCIsInRhZ3MiOltbInAiLCIxNWI1Y2Y2Y2RmNGZkMWMwMmYyOGJjY2UwZjE5N2NhZmFlNGM4YzdjNjZhM2UyZTIzYWY5ZmU2MTA4NzUzMTVlIl0sWyJlIiwiYmNiMmZjZmUxYzQ2N2M1ZWM4Mjg1ZTM4NWMzNmVjMTM4Nzk3MDljZWQ5ZDg4MDBjYjM0MGViZjIxOGMzMjEwZCJdLFsiUCIsIjA1MjFkYjk1MzEwOTZkZmY3MDBkY2Y0MTBiMDFkYjQ3YWI2NTk4ZGU3ZTVlZjJjNWEyYmQ3ZTExNjAzMTViZjYiXSxbImJvbHQxMSIsImxuYmMxMHUxcG52ZXhoM2RwdXUyZDJ6bm4wZGNra3hhdG53M2hrZzZ0cGRzczg1Y3RzeXBuOHltbWR5cGtoamd6cGQzMzhqZ3pndzQzcW5wNHEyMjhhMnp0eGt3emF5cHZ6cnNoODIzcW5nbXY5N2YydjlwdXd2dHNhZGV0eXBtdXR5c2N3cHA1dmxjbGwwMHpwcGhoMzJ3OHV0NWpwcDVhMmZtcWg4c3o3bnUyaDd2MDdyMHU1bHN3ZzVsc3NwNXh2YXFlZnpsY2t6bXYwdzg5bHIwazB5dnI1eGQybmc1MmE1cmNkYXJmbTRmMGEwd2dwdXE5cXl5c2dxY3FwY3hxeXo1dnFlcHMzOXNleDUyc2ZtdHU5Z25tNWRhcGs1bGdsZDRwcDk2dXI1YTRhbTk0MHEyNXd6ZHNycmo1MjN4eWEwcnV4YTVscjk2M2cwMjk2cjZtZGZ5MjR2NjUzZXZjcHh5cjBtbWhnd21zcXh2cmhmZCJdLFsicHJlaW1hZ2UiLCJhZDA0N2MwMmZlNWYwNTljODA4NzdkNzk0YmU4OGU0N2M2NDRlYmVkZmRmZTY2M2IyODljOTMxNmRiNDk1ZjJkIl0sWyJkZXNjcmlwdGlvbiIsIntcImtpbmRcIjo5NzM0LFwiY3JlYXRlZF9hdFwiOjE3MjQ2ODUwMzgsXCJjb250ZW50XCI6XCLimqFOb24tY3VzdG9kaWFsIHphcCBmcm9tIG15IEFsYnkgSHViXCIsXCJ0YWdzXCI6W1tcInBcIixcIjE1YjVjZjZjZGY0ZmQxYzAyZjI4YmNjZTBmMTk3Y2FmYWU0YzhjN2M2NmEzZTJlMjNhZjlmZTYxMDg3NTMxNWVcIl0sW1wicmVsYXlzXCIsXCJ3c3M6Ly9wdXJwbGVwYWcuZXMvXCIsXCJ3c3M6Ly9yZWxheS5nZXRhbGJ5LmNvbS92MVwiLFwid3NzOi8vbm9zdHIubW9tL1wiLFwid3NzOi8vbm9zdHIub3h0ci5kZXYvXCIsXCJ3c3M6Ly9ub3MubG9sL1wiLFwid3NzOi8vbm9zdHIud2luZS9cIixcIndzczovL3JlbGF5LmRhbXVzLmlvL1wiLFwid3NzOi8vcmVsYXkubm90b3NoaS53aW4vXCIsXCJ3c3M6Ly9lZGVuLm5vc3RyLmxhbmQvXCJdLFtcImFtb3VudFwiLFwiMTAwMDAwMFwiXSxbXCJlXCIsXCJiY2IyZmNmZTFjNDY3YzVlYzgyODVlMzg1YzM2ZWMxMzg3OTcwOWNlZDlkODgwMGNiMzQwZWJmMjE4YzMyMTBkXCJdXSxcInB1YmtleVwiOlwiMDUyMWRiOTUzMTA5NmRmZjcwMGRjZjQxMGIwMWRiNDdhYjY1OThkZTdlNWVmMmM1YTJiZDdlMTE2MDMxNWJmNlwiLFwiaWRcIjpcIjU3ZDg2MTIwMDc1MjFjMGI1MzJiOTFhZjI0OTgwOTVhMjUxZTYzZjQyNTE4N2U2Yzk1NzAwZmQwYTZiYWI3ZDRcIixcInNpZ1wiOlwiNzk4ZDczNTExOGJjZDE0MjI4YTEyYjZkNTI0MjNmZjI1YmI0ZWQ4Y2Q1ZGFjZjJmNTk3MWVmNTczZmRjM2ZjMDVmYzc5MzE4NWU2OTY4MmNjYTI0M2Q2NGYxNDdhNDQ5ODk2OGEwYmMyODhhZTgzZTc1YzAzZTk5ZjkzNmE2MDNcIn0iXV19Cg=="

        guard let json_data = Data(base64Encoded: zapjson) else {
            XCTAssert(false)
            return
        }

        let json_str = String(decoding: json_data, as: UTF8.self)

        guard let ev = decode_nostr_event_json(json: json_str) else {
            XCTAssert(false)
            return
        }

        let zapper = Pubkey(hex: "79f00d3f5a19ec806189fcab03c1be4ff81d18ee4f653c88fac41fe03570f432")!
        guard let zap = Zap.from_zap_event(zap_ev: ev, zapper: zapper, our_privkey: nil) else {
            XCTAssert(false)
            return
        }

        let note_id = NoteId(hex: "bcb2fcfe1c467c5ec8285e385c36ec13879709ced9d8800cb340ebf218c3210d")!
        let author = Pubkey(hex: "15b5cf6cdf4fd1c02f28bcce0f197cafae4c8c7c66a3e2e23af9fe610875315e")!
        XCTAssertEqual(zap.zapper, zapper)
        XCTAssertEqual(zap.target, ZapTarget.note(id: note_id, author: author))

        XCTAssertEqual(NotificationFormatter.zap_notification_title(zap), "Zap")
        XCTAssertEqual(NotificationFormatter.zap_notification_body(profiles: Profiles(ndb: test_damus_state.ndb), zap: zap), "You received 1k sats from 1q5sah9f:mqzxky65: \"⚡Non-custodial zap from my Alby Hub\"")


    }

    func test_private_zap() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let target = ZapTarget.profile(bob.pubkey)
        
        let message = "hey bob!"
        let mzapreq = make_zap_request_event(keypair: alice, content: message, relays: [], target: target, zap_type: .priv)
        
        XCTAssertNotNil(mzapreq)
        guard let mzapreq else {
            return
        }
        
        let zapreq = mzapreq.potentially_anon_outer_request.ev
        let decrypted = decrypt_private_zap(our_privkey: bob.privkey, zapreq: zapreq, target: target)
        
        XCTAssertNotNil(decrypted)
        guard let decrypted else {
            return
        }
        
        XCTAssertEqual(zapreq.content, "")
        XCTAssertEqual(decrypted.pubkey, alice.pubkey)
        XCTAssertEqual(message, decrypted.content)
    }
    
    @MainActor
    func testZap() throws {
        let zapjson = "eyJpZCI6IjUzNmJlZTllODNjODE4ZTNiODJjMTAxOTM1MTI4YWUyN2EwZDQyOTAwMzlhYWYyNTNlZmU1ZjA5MjMyYzE5NjIiLCJwdWJrZXkiOiI5NjMwZjQ2NGNjYTZhNTE0N2FhOGEzNWYwYmNkZDNjZTQ4NTMyNGU3MzJmZDM5ZTA5MjMzYjFkODQ4MjM4ZjMxIiwiY3JlYXRlZF9hdCI6MTY3NDIwNDUzNSwia2luZCI6OTczNSwidGFncyI6W1sicCIsIjMyZTE4Mjc2MzU0NTBlYmIzYzVhN2QxMmMxZjhlN2IyYjUxNDQzOWFjMTBhNjdlZWYzZDlmZDljNWM2OGUyNDUiXSxbImJvbHQxMSIsImxuYmMxMHUxcDN1NTR0bnNwNTcyOXF2eG5renRqamtkNTg1eW4wbDg2MzBzMm01eDZsNTZ3eXk0ZWMybnU4eHV6NjI5eHFwcDV2MnE3aHVjNGpwamgwM2Z4OHVqZXQ1Nms3OWd4cXg3bWUycGV2ejZqMms4dDhtNGxnNXZxaHA1eWc1MDU3OGNtdWoyNG1mdDNxcnNybWd3ZjMwa2U3YXY3ZDc3Z2FtZmxkazlrNHNmMzltcXhxeWp3NXFjcXBqcnpqcTJoeWVoNXEzNmx3eDZ6dHd5cmw2dm1tcnZ6NnJ1ZndqZnI4N3lremZuYXR1a200dWRzNHl6YWszc3FxOW1jcXFxcXFxcWxncXFxcTg2cXF5ZzlxeHBxeXNncWFkeWVjdmR6ZjI3MHBkMzZyc2FmbDA3azQ1ZmNqMnN5OGU1djJ0ZW5kNTB2OTU3NnV4cDNkdmp6amV1aHJlODl5cGdjbTkwZDZsbTAwNGszMHlqNGF2NW1jc3M1bnl4NHU5bmVyOWdwcHY2eXF3Il0sWyJkZXNjcmlwdGlvbiIsIntcImlkXCI6XCJiMDkyMTYzNGIxYmI4ZWUzNTg0YmJiZjJlOGQ3OTBhZDk4NTk5ZDhlMDhmODFjNzAwZGRiZTQ4MjAxNTY4Yjk3XCIsXCJwdWJrZXlcIjpcIjdmYTU2ZjVkNjk2MmFiMWUzY2Q0MjRlNzU4YzMwMDJiODY2NWY3YjBkOGRjZWU5ZmU5ZTI4OGQ3NzUxYWMxOTRcIixcImNyZWF0ZWRfYXRcIjoxNjc0MjA0NTMxLFwia2luZFwiOjk3MzQsXCJ0YWdzXCI6W1tcInBcIixcIjMyZTE4Mjc2MzU0NTBlYmIzYzVhN2QxMmMxZjhlN2IyYjUxNDQzOWFjMTBhNjdlZWYzZDlmZDljNWM2OGUyNDVcIl0sW1wicmVsYXlzXCIsXCJ3c3M6Ly9yZWxheS5zbm9ydC5zb2NpYWxcIixcIndzczovL3JlbGF5LmRhbXVzLmlvXCIsXCJ3c3M6Ly9ub3N0ci1wdWIud2VsbG9yZGVyLm5ldFwiLFwid3NzOi8vbm9zdHIudjBsLmlvXCIsXCJ3c3M6Ly9wcml2YXRlLW5vc3RyLnYwbC5pb1wiLFwid3NzOi8vbm9zdHIuemViZWRlZS5jbG91ZFwiLFwid3NzOi8vcmVsYXkubm9zdHIuaW5mby9cIl1dLFwiY29udGVudFwiOlwiXCIsXCJzaWdcIjpcImQwODQwNGU2MjVmOWM1NjMzYWZhZGQxMWMxMTBiYTg4ZmNkYjRiOWUwOTJiOTg0MGU3NDgyYThkNTM3YjFmYzExODY5MmNmZDEzMWRkODMzNTM2NDc2OWE2NzE3NTRhZDdhYTk3MzEzNjgzYTRhZDdlZmI3NjQ3NmMwNGU1ZjE3XCJ9Il0sWyJwcmVpbWFnZSIsIjNlMDJhM2FmOGM4YmNmMmEzNzUzYzg3ZjMxMTJjNjU2YTIwMTE0ZWUwZTk4ZDgyMTliYzU2ZjVlOGE3MjM1YjMiXV0sImNvbnRlbnQiOiIiLCJzaWciOiIzYWI0NGQwZTIyMjhiYmQ0ZDIzNDFjM2ZhNzQwOTZjZmY2ZjU1Y2ZkYTk5YTVkYWRjY2Y0NWM2NjQ2MzdlMjExNTFiMmY5ZGQwMDQwZjFhMjRlOWY4Njg2NzM4YjE2YmY4MTM0YmRiZTQxYTIxOGM5MTFmN2JiMzFlNTk1NzhkMSJ9Cg=="
        
        guard let json_data = Data(base64Encoded: zapjson) else {
            XCTAssert(false)
            return
        }
        
        let json_str = String(decoding: json_data, as: UTF8.self)
        
        guard let ev = decode_nostr_event_json(json: json_str) else {
            XCTAssert(false)
            return
        }
        
        let zapper = Pubkey(hex: "9630f464cca6a5147aa8a35f0bcdd3ce485324e732fd39e09233b1d848238f31")!
        guard let zap = Zap.from_zap_event(zap_ev: ev, zapper: zapper, our_privkey: nil) else {
            XCTAssert(false)
            return
        }

        let profile = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        XCTAssertEqual(zap.zapper, zapper)
        XCTAssertEqual(zap.target, ZapTarget.profile(profile))

        XCTAssertEqual(NotificationFormatter.zap_notification_title(zap), "Zap")
        XCTAssertEqual(NotificationFormatter.zap_notification_body(profiles: Profiles(ndb: test_damus_state.ndb), zap: zap), "You received 1k sats from 107jk7ht:2quqncxg")
    }

}
