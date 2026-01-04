//
//  MockURLProtocol.swift
//  damusTests
//
//  Created for testing network conditions and retry logic.
//

import Foundation

/// A mock URL protocol for simulating network conditions in tests.
///
/// Usage:
/// 1. Create a URLSession with a configuration that uses this protocol
/// 2. Set `MockURLProtocol.requestHandler` to define the mock behavior
/// 3. Make requests through that session
///
/// Example:
/// ```swift
/// let config = URLSessionConfiguration.ephemeral
/// config.protocolClasses = [MockURLProtocol.self]
/// let session = URLSession(configuration: config)
///
/// MockURLProtocol.requestHandler = { request in
///     let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
///     return (response, Data())
/// }
/// ```
class MockURLProtocol: URLProtocol {
    // MARK: - Thread-safe static state

    private static let lock = NSLock()
    private static var _requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _simulatedError: Error?
    private static var _requestCount = 0
    private static var _responseDelay: TimeInterval = 0

    /// Handler to process each request and return a response
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.withLock { _requestHandler } }
        set { lock.withLock { _requestHandler = newValue } }
    }

    /// Error to simulate on the next request (takes precedence over requestHandler)
    static var simulatedError: Error? {
        get { lock.withLock { _simulatedError } }
        set { lock.withLock { _simulatedError = newValue } }
    }

    /// Number of times a request has been made (useful for testing retries)
    static var requestCount: Int {
        get { lock.withLock { _requestCount } }
        set { lock.withLock { _requestCount = newValue } }
    }

    /// Delay before returning response (in seconds)
    static var responseDelay: TimeInterval {
        get { lock.withLock { _responseDelay } }
        set { lock.withLock { _responseDelay = newValue } }
    }

    /// Thread-safe increment of request count, returns new value
    static func incrementRequestCount() -> Int {
        lock.withLock {
            _requestCount += 1
            return _requestCount
        }
    }

    /// Reset all mock state
    static func reset() {
        lock.withLock {
            _requestHandler = nil
            _simulatedError = nil
            _requestCount = 0
            _responseDelay = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        _ = MockURLProtocol.incrementRequestCount()

        // Handle delay if configured
        if MockURLProtocol.responseDelay > 0 {
            Thread.sleep(forTimeInterval: MockURLProtocol.responseDelay)
        }

        // Simulate error if configured
        if let error = MockURLProtocol.simulatedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        // Use request handler
        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No request handler configured"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Nothing to do
    }
}

/// A mock URL protocol that can simulate failures for a specific number of requests
/// before succeeding, useful for testing retry logic.
class RetryTestURLProtocol: URLProtocol {
    // MARK: - Thread-safe static state

    private static let lock = NSLock()
    private static var _failuresBeforeSuccess = 0
    private static var _requestCount = 0
    private static var _failureError: Error = NSError(
        domain: NSURLErrorDomain,
        code: NSURLErrorTimedOut,
        userInfo: [NSLocalizedDescriptionKey: "Simulated timeout"]
    )
    private static var _successResponse: (HTTPURLResponse, Data)?
    private static var _httpResponse: (HTTPURLResponse, Data)?

    /// Number of times to fail before succeeding
    static var failuresBeforeSuccess: Int {
        get { lock.withLock { _failuresBeforeSuccess } }
        set { lock.withLock { _failuresBeforeSuccess = newValue } }
    }

    /// Current request count
    static var requestCount: Int {
        get { lock.withLock { _requestCount } }
        set { lock.withLock { _requestCount = newValue } }
    }

    /// The error to return for failures
    static var failureError: Error {
        get { lock.withLock { _failureError } }
        set { lock.withLock { _failureError = newValue } }
    }

    /// The successful response to return after failures
    static var successResponse: (HTTPURLResponse, Data)? {
        get { lock.withLock { _successResponse } }
        set { lock.withLock { _successResponse = newValue } }
    }

    /// HTTP response to return immediately (bypasses failure simulation)
    /// Use this to test HTTP error status codes (4xx, 5xx)
    static var httpResponse: (HTTPURLResponse, Data)? {
        get { lock.withLock { _httpResponse } }
        set { lock.withLock { _httpResponse = newValue } }
    }

    /// Thread-safe increment of request count, returns new value
    static func incrementRequestCount() -> Int {
        lock.withLock {
            _requestCount += 1
            return _requestCount
        }
    }

    /// Reset all state
    static func reset() {
        lock.withLock {
            _failuresBeforeSuccess = 0
            _requestCount = 0
            _failureError = NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorTimedOut,
                userInfo: [NSLocalizedDescriptionKey: "Simulated timeout"]
            )
            _successResponse = nil
            _httpResponse = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        let currentCount = RetryTestURLProtocol.incrementRequestCount()

        // If httpResponse is set, always return it (for testing HTTP status codes)
        if let (response, data) = RetryTestURLProtocol.httpResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if currentCount <= RetryTestURLProtocol.failuresBeforeSuccess {
            // Simulate failure
            client?.urlProtocol(self, didFailWithError: RetryTestURLProtocol.failureError)
        } else if let (response, data) = RetryTestURLProtocol.successResponse {
            // Return success
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            // No success response configured
            let error = NSError(domain: "RetryTestURLProtocol", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No success response configured"])
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Nothing to do
    }
}
