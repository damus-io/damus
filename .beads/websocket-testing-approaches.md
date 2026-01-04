# WebSocket/Relay Poor Network Testing Approaches

> **Purpose:** Document approaches for simulating poor network conditions across all WebSocket-dependent features in Damus iOS app.
> **Related Issues:** damus-02i, damus-czv
> **Last Updated:** 2026-01-03

---

## Why This Matters

WebSocket connectivity affects **nearly every feature** in Damus:

| Feature | WebSocket Dependency | User Impact on Failure |
|---------|---------------------|------------------------|
| Timeline loading | All events come via relays | Empty feed, stale content |
| Posting notes | Events published to relays | "Failed to post" errors |
| DMs (NIP-04/44) | Encrypted messages via relays | Messages not sent/received |
| Zaps | Lightning invoices via relays | Payment failures |
| Profile updates | Metadata events | Profile not saved |
| Following/muting | Contact list events | Actions not persisted |
| Notifications | Mentions, replies via relays | Missed notifications |
| Search | Query relays for content | No results |

**Current gap:** We have HTTP upload retry testing but no WebSocket failure testing.

---

## Architecture Summary

**Key Files:**
- `WebSocket.swift` - Low-level URLSessionWebSocketTask wrapper
- `RelayConnection.swift` - Connection state, reconnect logic, backoff
- `RelayPool.swift` - Actor managing multiple relays, request queuing

**Stack:** URLSessionWebSocketTask → Combine PassthroughSubject → Callbacks

**Critical Insight:** `URLProtocol` (used for HTTP mocking) **cannot intercept WebSocket traffic**. This is an iOS limitation - WebSocket uses a different code path in URLSession.

**Current Mockable Seams:**
1. `RelayConnection` callbacks: `handleEvent` and `processUnverifiedWSEvent`
2. `WebSocket` accepts custom `URLSession` (but URLProtocol can't intercept WebSocket)
3. `RelayPool.Delegate` protocol (limited - only relay list changes)

---

## Failure Scenarios to Test

| Scenario | Real-World Cause | Expected Behavior |
|----------|------------------|-------------------|
| Connection timeout | Slow network, overloaded relay | Retry with backoff |
| Connection refused | Relay down, firewall | Try next relay |
| Mid-stream disconnect | Network switch, sleep/wake | Reconnect, resubscribe |
| Slow responses | High latency, congestion | UI remains responsive |
| Partial message | TCP fragmentation | Buffer and reassemble |
| Auth failure (NIP-42) | Invalid credentials | Show auth prompt |
| Rate limiting | Too many requests | Backoff, queue requests |
| DNS failure | No internet, DNS issues | Offline mode |
| TLS handshake failure | Certificate issues | Clear error message |

---

## Approach 1: Mock WebSocket Class (Protocol Extraction)

**Description:** Create `WebSocketProtocol`, make `WebSocket` conform, inject `MockWebSocket` into `RelayConnection` for testing.

**Implementation:**
```swift
protocol WebSocketProtocol {
    var subject: PassthroughSubject<WebSocketEvent, Never> { get }
    func connect()
    func disconnect()
    func send(_ message: URLSessionWebSocketTask.Message)
}

class MockWebSocket: WebSocketProtocol {
    let subject = PassthroughSubject<WebSocketEvent, Never>()
    var sentMessages: [URLSessionWebSocketTask.Message] = []
    var connectCalled = false

    func connect() { connectCalled = true }
    func disconnect() { subject.send(completion: .finished) }
    func send(_ message: URLSessionWebSocketTask.Message) {
        sentMessages.append(message)
    }

    // Test helpers
    func simulateDisconnect() {
        subject.send(.disconnected(.goingAway, nil))
    }
    func simulateNetworkError() {
        subject.send(.error(URLError(.networkConnectionLost)))
    }
    func simulateMessage(_ text: String) {
        subject.send(.message(.string(text)))
    }
}
```

**Requires:** Refactor `WebSocket` to conform to protocol, modify `RelayConnection` to accept protocol.

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **Medium** | ~50 lines protocol + mock, ~10 line changes to RelayConnection |
| Risk | **Low** | Protocol extraction is safe refactor, no behavior change |
| Upside | **High** | Full control over WebSocket events, can simulate any failure |
| Testability | **Excellent** | Unit tests can verify reconnect logic, backoff, state transitions |

### What This CAN Test
- ✅ Connection timeout
- ✅ Connection refused
- ✅ Mid-stream disconnect
- ✅ Auth failure (NIP-42)
- ✅ Reconnect with backoff
- ✅ State transitions (connecting → connected → disconnected)
- ✅ Message sending/receiving
- ✅ Subscription management

### What This CANNOT Test
- ❌ Real TLS handshake
- ❌ Real TCP behavior (fragmentation, ordering)
- ❌ URLSession internals
- ❌ System-level network changes (airplane mode)

### Production Code Changes Required
```
damus/Core/Nostr/WebSocket.swift        +15 lines (protocol conformance)
damus/Core/Nostr/RelayConnection.swift  +5 lines (accept protocol)
```

---

## Approach 2: Mock at RelayConnection Callbacks

**Description:** Test RelayPool behavior by injecting mock `handleEvent` callbacks. Tests event processing without touching network layer.

**Implementation:**
```swift
// Already supported - no code changes needed
let mockConnection = RelayConnection(
    url: testURL,
    handleEvent: { event in
        // Capture events, verify processing
        capturedEvents.append(event)
    },
    processUnverifiedWSEvent: { wsEvent in
        // Simulate relay responses
        return .ok
    }
)

// Trigger events directly for testing
mockConnection.receive(event: .connected)
mockConnection.receive(event: .message(.string(mockNostrEvent)))
```

**Requires:** Nothing - callbacks already injectable. May need `receive(event:)` to be internal.

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **Low** | Zero production code changes |
| Risk | **None** | Uses existing API |
| Upside | **Medium** | Can test RelayPool logic, but not RelayConnection internals |
| Testability | **Good** | Tests higher-level behavior, misses reconnect/backoff logic |

### What This CAN Test
- ✅ Event parsing and routing
- ✅ Subscription management at pool level
- ✅ Request queuing
- ✅ Multi-relay coordination
- ✅ Event deduplication

### What This CANNOT Test
- ❌ RelayConnection state machine
- ❌ Reconnect/backoff logic
- ❌ WebSocket-level failures
- ❌ Connection lifecycle

### Best For
Testing `RelayPool` actor logic in isolation - how it routes events, manages subscriptions across multiple relays, and handles request queuing.

---

## Approach 3: Local Test Relay Server

**Description:** Run a local Nostr relay that can simulate failures on demand. Most realistic testing but highest setup complexity.

**Implementation Options:**

**Option A: Swift NIO WebSocket Server (embedded)**
```swift
// Custom Swift server using SwiftNIO
class TestRelayServer {
    let port: Int
    var mode: FailureMode = .normal

    enum FailureMode {
        case normal
        case dropConnectionAfter(messages: Int)
        case respondSlowly(delay: TimeInterval)
        case rejectAuth
        case returnInvalidJSON
        case closeWithError(code: Int)
    }

    func start() async throws { /* NIO WebSocket server */ }
    func stop() async { /* cleanup */ }
}
```

**Option B: Docker container (strfry/nostream)**
```yaml
# docker-compose.test.yml
services:
  test-relay:
    image: dockurr/strfry:latest
    ports:
      - "8080:7777"
    # Could extend with failure injection via config
```

**Option C: External process**
```swift
// Spawn a lightweight relay binary
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/local/bin/test-relay")
process.arguments = ["--port", "8080", "--fail-after", "5"]
```

**Requires:** Significant setup - either Swift NIO knowledge, Docker in CI, or custom relay binary.

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **High** | 500+ lines for Swift NIO, or Docker CI setup |
| Risk | **Medium** | Port conflicts, CI flakiness, external dependencies |
| Upside | **Very High** | Tests real WebSocket stack end-to-end, most realistic |
| Testability | **Excellent** | Integration tests cover full stack including URLSession |

### What This CAN Test
- ✅ Everything! Full end-to-end WebSocket
- ✅ Real TLS (with self-signed certs)
- ✅ Real TCP behavior
- ✅ URLSession internals
- ✅ Nostr protocol compliance
- ✅ NIP-42 auth flows
- ✅ Subscription filters

### What This CANNOT Test
- ❌ System-level network changes (still needs Network Link Conditioner)
- ❌ Cellular vs WiFi transitions

### CI Considerations
- Docker: Works on GitHub Actions, adds ~30s startup time
- Embedded Swift: No external deps, but significant code
- Port conflicts: Use random ports, proper cleanup

### Best For
Pre-release integration testing, catching protocol-level bugs that mocks miss.

---

## Approach 4: Network Link Conditioner (Manual)

**Description:** Use Apple's Network Link Conditioner for manual exploratory testing. System-wide network degradation.

**Implementation:**
```
1. Download "Additional Tools for Xcode" from Apple Developer
2. Install Network Link Conditioner.prefPane
3. Enable in System Preferences → Network Link Conditioner
4. Choose profile: 3G, Edge, 100% Loss, etc.
```

**Built-in Profiles:**
| Profile | Bandwidth | Latency | Packet Loss |
|---------|-----------|---------|-------------|
| 3G | 780 Kbps | 100ms | 0% |
| Edge | 240 Kbps | 400ms | 0% |
| Very Bad Network | 1 Mbps | 500ms | 10% |
| 100% Loss | 0 | - | 100% |
| WiFi | 40 Mbps | 1ms | 0% |
| DSL | 2 Mbps | 5ms | 0% |

**Custom Profiles:** Can create custom profiles with specific characteristics.

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **None** | Already available on macOS |
| Risk | **None** | Manual testing only |
| Upside | **Medium** | Good for exploratory testing, affects all traffic |
| Testability | **Poor** | Cannot automate, requires human verification |

### What This CAN Test
- ✅ Real network degradation across entire system
- ✅ Both HTTP and WebSocket simultaneously
- ✅ Cellular/WiFi realistic behavior
- ✅ User experience under poor conditions
- ✅ Timeouts, retries in production code

### What This CANNOT Test
- ❌ Cannot automate in CI
- ❌ Cannot target specific connections
- ❌ Cannot script failure sequences
- ❌ Cannot verify programmatically

### Best For
- Pre-release manual QA
- Debugging user-reported network issues
- Exploratory testing of error handling
- Validating UX under degraded conditions

### Alternative: Xcode Network Link Conditioner
In Xcode 14+, you can enable network conditioning directly in the scheme:
```
Product → Scheme → Edit Scheme → Run → Options → Network Link Conditioner
```

---

## Approach 5: Swizzle/Intercept at URLSession Level

**Description:** Use Objective-C method swizzling to intercept `webSocketTask(with:)` and return a mock task. Intercepts at the lowest level without production code changes.

**Implementation:**
```swift
import ObjectiveC

class WebSocketSwizzler {
    static func enableMocking() {
        let originalSelector = #selector(URLSession.webSocketTask(with:) as (URLSession) -> (URL) -> URLSessionWebSocketTask)
        let swizzledSelector = #selector(URLSession.swizzled_webSocketTask(with:))

        guard let originalMethod = class_getInstanceMethod(URLSession.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(URLSession.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension URLSession {
    @objc func swizzled_webSocketTask(with url: URL) -> URLSessionWebSocketTask {
        if TestConfig.simulateFailures {
            // Problem: URLSessionWebSocketTask is not subclassable!
            // This approach hits a dead end here.
            fatalError("Cannot create mock URLSessionWebSocketTask")
        }
        return self.swizzled_webSocketTask(with: url) // calls original
    }
}
```

**Critical Problem:** `URLSessionWebSocketTask` is a concrete class that cannot be subclassed or mocked effectively. Its initializers are not public.

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **High** | Swizzling is fragile, mock task is impossible |
| Risk | **Very High** | iOS updates can break, task is not mockable |
| Upside | **Low** | Blocked by URLSessionWebSocketTask being final-ish |
| Testability | **Poor** | Approach doesn't work in practice |

### What This CAN Test
- ⚠️ Theoretically everything at URLSession level
- ⚠️ But blocked by implementation constraints

### What This CANNOT Test
- ❌ Everything - approach is not viable

### Why This Doesn't Work
1. `URLSessionWebSocketTask` cannot be subclassed
2. No public initializers for creating mock instances
3. Swizzling is fragile across iOS versions
4. Hard to debug when things go wrong
5. May violate App Store guidelines in production code

### Verdict: **AVOID**
This approach looked promising but is blocked by iOS implementation details. Protocol extraction (Approach 1) is the right way to solve this.

---

## Approach 6: Inject Failure via RelayConnection Subclass

**Description:** Create `TestableRelayConnection` subclass that can trigger failures programmatically. Quick win for testing reconnect/backoff without full protocol extraction.

**Implementation:**
```swift
class TestableRelayConnection: RelayConnection {
    var shouldFailNextConnection = false
    var failureSequence: [Error] = []
    var connectionAttempts = 0

    override func connect(force: Bool = false) {
        connectionAttempts += 1

        if shouldFailNextConnection {
            shouldFailNextConnection = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.receive(event: .error(URLError(.networkConnectionLost)))
            }
            return
        }

        if !failureSequence.isEmpty {
            let error = failureSequence.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.receive(event: .error(error))
            }
            return
        }

        super.connect(force: force)
    }

    func simulateDisconnect() {
        receive(event: .disconnected(.goingAway, nil))
    }

    func simulateReconnect() {
        receive(event: .connected)
    }
}
```

**Requires:** Make `receive(event:)` internal (not private). Currently it's private.

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **Low-Medium** | ~50 line subclass, 1 line visibility change |
| Risk | **Low** | Subclassing is standard pattern, minimal prod changes |
| Upside | **Medium-High** | Can test reconnect logic, backoff timing |
| Testability | **Good** | Direct control over failure injection |

### What This CAN Test
- ✅ Reconnect with exponential backoff
- ✅ Connection state transitions
- ✅ Failure sequences (fail 3 times then succeed)
- ✅ Connection attempt counting
- ✅ Force reconnect behavior

### What This CANNOT Test
- ❌ WebSocket message handling (uses real WebSocket)
- ❌ Send/receive at message level
- ❌ Protocol-level details

### Production Code Changes Required
```swift
// In RelayConnection.swift, change:
private func receive(event: WebSocketEvent)
// to:
internal func receive(event: WebSocketEvent)  // or use @testable import
```

### Best For
Quick win to get reconnect/backoff tests running while planning full protocol extraction.

---

## Ranking Summary

| Rank | Approach | Complexity | Risk | Upside | Viable? | Recommendation |
|------|----------|------------|------|--------|---------|----------------|
| 1 | **Mock WebSocket Protocol** | Medium | Low | High | ✅ Yes | Best balance - enables comprehensive unit tests |
| 2 | **RelayConnection Subclass** | Low-Med | Low | Med-High | ✅ Yes | Quick win for testing reconnect logic |
| 3 | **Callback Injection** | Low | None | Medium | ✅ Yes | Already works, good for RelayPool tests |
| 4 | **Local Test Relay** | High | Medium | Very High | ✅ Yes | Best for integration tests, save for later |
| 5 | **Network Link Conditioner** | None | None | Medium | ⚠️ Manual | Keep for manual exploratory testing |
| 6 | **URLSession Swizzling** | High | Very High | Low | ❌ No | Blocked by iOS - URLSessionWebSocketTask not mockable |

---

## Decision Matrix: Which Approach for Which Test?

| Test Scenario | Best Approach | Fallback |
|---------------|---------------|----------|
| Reconnect backoff timing | Mock WebSocket Protocol | RelayConnection Subclass |
| Connection state machine | Mock WebSocket Protocol | RelayConnection Subclass |
| RelayPool request routing | Callback Injection | Mock WebSocket Protocol |
| Multi-relay failover | Mock WebSocket Protocol | Callback Injection |
| NIP-42 auth flow | Mock WebSocket Protocol | Local Test Relay |
| Nostr protocol compliance | Local Test Relay | Mock WebSocket Protocol |
| TLS/certificate errors | Local Test Relay | Network Link Conditioner |
| Real-world UX testing | Network Link Conditioner | Local Test Relay |
| Subscription management | Callback Injection | Mock WebSocket Protocol |
| Message parsing | Callback Injection | Mock WebSocket Protocol |

---

## Recommended Implementation Order

### Phase 1: Quick Wins
1. Add `WebSocketProtocol` and make `WebSocket` conform
2. Create `MockWebSocket` for unit tests
3. Add tests for `RelayConnection` reconnect/backoff logic

**Deliverables:**
- `WebSocketProtocol` with 4 methods
- `MockWebSocket` with test helpers
- 5-10 unit tests for RelayConnection

### Phase 2: Expand Coverage
4. Create `TestableRelayConnection` subclass (if needed)
5. Add `RelayPool` tests with simulated failures
6. Test network recovery scenarios

**Deliverables:**
- Full RelayConnection test coverage
- RelayPool failure handling tests
- Edge case tests (rapid reconnect, multiple failures)

### Phase 3: Integration (Future)
7. Set up local test relay for CI
8. Add integration tests covering real WebSocket stack
9. NIP compliance tests

**Deliverables:**
- Docker or embedded test relay
- CI pipeline integration
- Protocol compliance test suite

---

## Files to Modify

### Phase 1 (Required)
| File | Change | Lines |
|------|--------|-------|
| `damus/Core/Nostr/WebSocket.swift` | Extract protocol | +15 |
| `damus/Core/Nostr/RelayConnection.swift` | Accept protocol | +5 |
| `damusTests/Mocking/MockWebSocket.swift` | New file | +60 |
| `damusTests/RelayConnectionTests.swift` | New file | +150 |

### Phase 2 (Optional)
| File | Change | Lines |
|------|--------|-------|
| `damusTests/Mocking/TestableRelayConnection.swift` | New file | +50 |
| `damusTests/RelayPoolTests.swift` | Expand existing | +100 |

### Phase 3 (Future)
| File | Change | Lines |
|------|--------|-------|
| `damusTests/TestRelay/` | New directory | +500 |
| `.github/workflows/tests.yml` | Add relay service | +20 |

---

## Open Questions

1. **Protocol scope:** Should `WebSocketProtocol` include connection state properties, or just methods?
2. **Backoff verification:** How to test timing without making tests slow? (Use time mocking?)
3. **RelayPool actor:** How to inject mock connections into the actor safely?
4. **Test isolation:** Need to ensure mock state is reset between tests (learned from MockURLProtocol)

---

## Related Documentation

- **HTTP testing:** See `damusTests/Mocking/MockURLProtocol.swift` for pattern
- **Thread safety:** All mock static state must use NSLock (cr-4, cr-6)
- **Current gaps:** damus-02i, damus-czv in `.beads/issues.jsonl`

---

# Part 2: Automated Poor Connectivity Simulation

> **Research Date:** 2026-01-03
> **Goal:** Automate 3G-like network conditions for CI testing

## The Problem

The approaches in Part 1 simulate **failure events** (disconnect, timeout, error), not **degraded connectivity** (latency, jitter, packet loss, bandwidth limits). True poor connectivity testing requires:

- Latency: 100-500ms round trip
- Bandwidth limits: 780 Kbps (3G) or less
- Packet loss: 1-10%
- Jitter: Variable latency

---

## Approach 7: macOS pfctl/dnctl (System-Level)

**Description:** Use macOS packet filter and dummynet to throttle all traffic programmatically. This is what Network Link Conditioner uses under the hood.

**Implementation:**
```bash
#!/bin/bash
# throttle-3g.sh - Simulate 3G connection

# Create dummynet pipe with 3G characteristics
sudo dnctl pipe 1 config bw 780Kbit/s delay 100ms plr 0.01

# Create anchor for our rules
echo "dummynet in quick proto tcp from any to any pipe 1
dummynet out quick proto tcp from any to any pipe 1" | sudo pfctl -a throttle -f -

# Enable packet filter
sudo pfctl -E

# To disable:
# sudo pfctl -a throttle -F all
# sudo dnctl -q flush
```

**CI Integration:**
```yaml
# .github/workflows/tests.yml
- name: Enable 3G throttling
  run: |
    sudo dnctl pipe 1 config bw 780Kbit/s delay 100ms plr 0.01
    echo "dummynet in proto tcp pipe 1" | sudo pfctl -a throttle -f -
    sudo pfctl -E

- name: Run tests
  run: xcodebuild test ...

- name: Disable throttling
  if: always()
  run: |
    sudo pfctl -a throttle -F all
    sudo dnctl -q flush
```

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **Medium** | Shell scripts, needs root |
| Risk | **Medium** | System-wide, must cleanup properly |
| Upside | **Very High** | Real network throttling, affects all traffic |
| Automation | **✅ Yes** | Works in CI with sudo |

### What This CAN Test
- ✅ Real 3G/Edge/LTE bandwidth limits
- ✅ Real latency and jitter
- ✅ Packet loss
- ✅ Both HTTP and WebSocket simultaneously
- ✅ System-level, no app changes

### What This CANNOT Test
- ❌ Per-connection throttling (affects entire system)
- ❌ Simulated relay-specific failures

### Preset Profiles
| Profile | Bandwidth | Latency | Packet Loss |
|---------|-----------|---------|-------------|
| 3G | 780 Kbps | 100ms | 1% |
| Edge | 240 Kbps | 400ms | 1% |
| LTE | 50 Mbps | 50ms | 0% |
| Very Bad | 100 Kbps | 500ms | 10% |

**Sources:**
- [Bandwidth Throttling on macOS](https://blog.leiy.me/post/bw-throttling-on-mac/)
- [sitespeedio/throttle](https://github.com/sitespeedio/throttle)

---

## Approach 8: sitespeedio/throttle (npm wrapper)

**Description:** Ready-made npm package that wraps pfctl (macOS) and tc (Linux) for CI-friendly network throttling.

**Installation:**
```bash
npm install -g @sitespeed.io/throttle
```

**Usage:**
```bash
# Start 3G throttling
throttle --profile 3g

# Custom profile
throttle --up 780 --down 780 --rtt 100

# Stop throttling
throttle --stop
```

**CI Integration:**
```yaml
- name: Install throttle
  run: npm install -g @sitespeed.io/throttle

- name: Enable 3G
  run: sudo throttle --profile 3g

- name: Run tests
  run: xcodebuild test ...

- name: Stop throttle
  if: always()
  run: sudo throttle --stop
```

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **Low** | npm install, simple CLI |
| Risk | **Low** | Well-tested, handles cleanup |
| Upside | **Very High** | Same as pfctl but easier |
| Automation | **✅ Yes** | Built for CI |

### Built-in Profiles
- `3g`, `3gfast`, `3gslow`
- `2g`
- `cable`
- `native` (no throttling)

**Source:** [GitHub - sitespeedio/throttle](https://github.com/sitespeedio/throttle)

---

## Approach 9: Proxy-Based Throttling (Proxyman/Charles)

**Description:** Use HTTP proxy with throttling capabilities. Can target specific hosts/URLs.

**Proxyman:**
- Has Network Condition feature (throttling)
- GUI-based, limited CLI automation
- Free basic features

**Charles Proxy:**
```bash
# Start Charles with throttling enabled
charles -throttling

# Or configure via headless mode (v3.8.3+)
charles -config throttling.xml
```

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **Medium** | Requires proxy setup, cert trust |
| Risk | **Low** | Well-tested tools |
| Upside | **High** | Can target specific hosts |
| Automation | **⚠️ Partial** | Charles has some CLI, Proxyman limited |

### What This CAN Test
- ✅ HTTP/HTTPS with latency and bandwidth limits
- ✅ Per-host throttling
- ⚠️ WebSocket through proxy (requires setup)

### What This CANNOT Test
- ❌ Traffic that bypasses proxy
- ❌ Low-level TCP behavior

**Sources:**
- [Proxyman Network Conditions](https://proxyman.com/posts/2022-06-25-Simulate-slow-network-with-Proxyman-network-conditions-tool)
- [Charles Throttling](https://www.charlesproxy.com/documentation/proxying/throttling/)

---

## Approach 10: Xcode Device Conditions (Semi-Automated)

**Description:** Xcode 11+ has built-in network conditioning via Window > Devices and Simulators.

**Access:**
1. Window → Devices and Simulators (⇧⌘2)
2. Select device
3. Device Conditions → Network Link → Choose profile

**Automation potential:**
- Can be set via `xcrun simctl` with some hacking
- Not officially supported for automation

### Tradeoff Analysis

| Metric | Rating | Notes |
|--------|--------|-------|
| Complexity | **None** | Built into Xcode |
| Risk | **None** | Apple-supported |
| Upside | **Medium** | Easy for manual testing |
| Automation | **❌ No** | GUI only, no CLI |

**Source:** [Network Link Conditioner - NSHipster](https://nshipster.com/network-link-conditioner/)

---

## Comparison: Automated Poor Connectivity Approaches

| Approach | Automates? | Affects WebSocket? | CI-Ready? | Complexity |
|----------|------------|-------------------|-----------|------------|
| **pfctl/dnctl** | ✅ Yes | ✅ Yes | ✅ Yes (sudo) | Medium |
| **sitespeedio/throttle** | ✅ Yes | ✅ Yes | ✅ Yes | Low |
| **Charles Proxy** | ⚠️ Partial | ⚠️ Via proxy | ⚠️ Limited | Medium |
| **Proxyman** | ❌ Limited | ⚠️ Via proxy | ❌ No | Low |
| **Xcode Device Conditions** | ❌ No | ✅ Yes | ❌ No | None |
| **Network Link Conditioner** | ❌ No | ✅ Yes | ❌ No | None |

---

## Recommended Approach for CI

**Use `sitespeedio/throttle`** - it's the easiest path to automated 3G testing:

```yaml
# .github/workflows/network-tests.yml
name: Poor Network Tests

on: [push, pull_request]

jobs:
  test-3g:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Install throttle
        run: npm install -g @sitespeed.io/throttle

      - name: Start 3G simulation
        run: sudo throttle --profile 3g

      - name: Run WebSocket tests
        run: |
          xcodebuild test \
            -scheme damus \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -only-testing:damusTests/RelayConnectionTests

      - name: Stop throttling
        if: always()
        run: sudo throttle --stop
```

---

## Open Questions (Updated)

1. ~~How to automate Network Link Conditioner?~~ → Use pfctl/dnctl or sitespeedio/throttle
2. ~~GitHub Actions macos runners:~~ → Yes, sudo works. Implemented in `.github/workflows/network-tests.yml`
3. **Test isolation:** How to ensure throttling doesn't affect parallel CI jobs?
4. **Metrics collection:** How to measure actual latency in tests to verify throttling works?

---

## Implementation Status

**Date:** 2026-01-03

### Completed

1. **CI Workflow:** `.github/workflows/network-tests.yml`
   - Uses `sitespeedio/throttle` for 3G/Edge simulation
   - Runs `UploadRetryTests` under throttled conditions
   - Matrix build tests multiple profiles on master branch
   - Manual trigger with profile selection

2. **Local Script:** `scripts/throttle-network.sh`
   - Direct pfctl/dnctl wrapper (no npm required)
   - Profiles: 3g, 3gfast, 3gslow, edge, 2g, lte, verybad, lossy
   - Usage: `sudo ./scripts/throttle-network.sh start 3g`

### Pending

1. **WebSocket-specific tests:** Need to create `RelayConnectionTests` and `RelayPoolTests` that verify behavior under poor network (Approach 1: Mock WebSocket Protocol)

2. **Metrics verification:** Add assertions that verify expected latency/timeout behavior
