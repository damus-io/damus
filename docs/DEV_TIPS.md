# Dev tips

A collection of tips when developing or testing Damus.


## Logging

- Info and debug messages must be activated in the macOS Console to become visible, they are not visible by default. To activate, go to Console > Action > Include Info Messages.


## Testing push notifications

- Dev builds (i.e. anything that isn't an official build from TestFlight or AppStore) only work with the development/sandbox APNS environment. If testing push notifications on a local damus build, ensure that:
    - Damus is configured to use the "staging" push notifications environment, under Settings > Developer settings.
    - Ensure that Nostr events are sent to `wss://notify-staging.damus.io`.


## Testing poor network conditions

Testing how Damus handles poor or intermittent network connectivity is important for ensuring a good user experience. There are several approaches:

### Automated testing (unit tests)

The codebase includes `MockURLProtocol` and `RetryTestURLProtocol` in the test target for simulating network failures in unit tests. See `UploadRetryTests.swift` for examples of testing retry logic with simulated:
- Timeouts (`NSURLErrorTimedOut`)
- Connection loss (`NSURLErrorNetworkConnectionLost`)
- DNS failures (`NSURLErrorDNSLookupFailed`)
- Server errors

### Automated testing (UI tests)

For UI tests, use `NetworkConditionSimulator` via launch arguments. This is only available in DEBUG builds.

**Supported conditions:**
- `timeout` - Simulates request timeout after 2 seconds
- `connectionLost` - Simulates connection lost error
- `notConnected` - Simulates no internet connection
- `slowNetwork` - Adds 3 second delay before responding
- `failThenSucceed` - Fails first 2 requests, succeeds on retry
- `serverError` - Returns HTTP 500 error

**Usage in UI tests:**
```swift
// Simulate timeout for all upload requests
app.launchArguments += ["-SimulateNetworkCondition", "timeout", "-SimulateNetworkPattern", "upload"]
app.launch()

// Verify error message appears
XCTAssertTrue(app.staticTexts[AID.post_composer_error_message.rawValue].waitForExistence(timeout: 10))
```

**Testing retry behavior:**
```swift
// Fail first 2 requests, then succeed (tests retry logic)
app.launchArguments += ["-SimulateNetworkCondition", "failThenSucceed", "-SimulateNetworkPattern", "upload"]
```

See `damusUITests.swift` for example tests: `testUploadShowsErrorOnTimeout` and `testUploadSucceedsAfterRetry`.

### Network Link Conditioner (macOS/iOS)

Apple's Network Link Conditioner tool simulates real-world network conditions. This is useful for manual testing of the entire app under degraded network.

**Setup on macOS (for Simulator testing):**
1. Download "Additional Tools for Xcode" from https://developer.apple.com/download/all/
2. Install "Network Link Conditioner.prefPane" from Hardware folder
3. Open System Preferences > Network Link Conditioner
4. Choose a profile:
   - **3G** - High latency, moderate bandwidth
   - **Edge** - Very high latency, low bandwidth
   - **Very Bad Network** - Packet loss and high latency
   - **100% Loss** - Complete network failure
5. Toggle "ON" to activate

**Setup on iOS device:**
1. Go to Settings > Developer
2. Scroll to Network Link Conditioner
3. Enable and choose a profile

**Testing image uploads:**
1. Enable "Very Bad Network" or "Edge" profile
2. Attempt to upload an image/video
3. Verify:
   - Upload retries automatically on transient failures
   - Error messages are user-friendly, not generic
   - Progress indicator behaves correctly
   - App remains responsive

**Testing relay connections:**
1. Enable "100% Loss" profile
2. Verify disconnection is handled gracefully
3. Disable profile
4. Verify automatic reconnection

Remember to disable Network Link Conditioner after testing.


## Thread Sanitizer (TSan)

Thread Sanitizer detects data races at runtime. It's particularly important for code that uses shared mutable state across threads (like `MediaPicker`'s `failedCount` and `orderMap`).

### Running TSan locally

**Using the TSan scheme in Xcode:**
1. Select the `damus-TSan` scheme from the scheme selector
2. Run tests with Cmd+U
3. TSan violations appear as runtime errors in the test log

**Using command line:**
```bash
xcodebuild test \
  -scheme damus-TSan \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  | xcpretty
```

### CI integration

The GitHub Actions workflow at `.github/workflows/tests.yml` runs TSan on every PR automatically. Check the "Thread Sanitizer" job for any race conditions.

### What TSan catches

- Data races: Multiple threads accessing shared memory without synchronization
- Use-after-free in concurrent code
- Thread leaks

### Known limitations

- TSan adds ~5-10x runtime overhead
- Not compatible with Address Sanitizer (ASan)
- Some system frameworks may trigger false positives (suppress with `__tsan_ignore`)

