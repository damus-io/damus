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
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

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
        
        guard let zap = Zap.from_zap_event(zap_ev: ev, zapper: "9630f464cca6a5147aa8a35f0bcdd3ce485324e732fd39e09233b1d848238f31") else {
            XCTAssert(false)
            return
        }
        
        XCTAssertEqual(zap.zapper, "9630f464cca6a5147aa8a35f0bcdd3ce485324e732fd39e09233b1d848238f31")
        XCTAssertEqual(zap.target, ZapTarget.profile("32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"))
    }

}
