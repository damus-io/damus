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
    /// Handler to process each request and return a response
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Error to simulate on the next request (takes precedence over requestHandler)
    static var simulatedError: Error?

    /// Number of times a request has been made (useful for testing retries)
    static var requestCount = 0

    /// Delay before returning response (in seconds)
    static var responseDelay: TimeInterval = 0

    /// Reset all mock state
    static func reset() {
        requestHandler = nil
        simulatedError = nil
        requestCount = 0
        responseDelay = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.requestCount += 1

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
    /// Number of times to fail before succeeding
    static var failuresBeforeSuccess = 0

    /// Current request count
    static var requestCount = 0

    /// The error to return for failures
    static var failureError: Error = NSError(
        domain: NSURLErrorDomain,
        code: NSURLErrorTimedOut,
        userInfo: [NSLocalizedDescriptionKey: "Simulated timeout"]
    )

    /// The successful response to return after failures
    static var successResponse: (HTTPURLResponse, Data)?

    /// HTTP response to return immediately (bypasses failure simulation)
    /// Use this to test HTTP error status codes (4xx, 5xx)
    static var httpResponse: (HTTPURLResponse, Data)?

    /// Reset all state
    static func reset() {
        failuresBeforeSuccess = 0
        requestCount = 0
        failureError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "Simulated timeout"]
        )
        successResponse = nil
        httpResponse = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        RetryTestURLProtocol.requestCount += 1

        // If httpResponse is set, always return it (for testing HTTP status codes)
        if let (response, data) = RetryTestURLProtocol.httpResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if RetryTestURLProtocol.requestCount <= RetryTestURLProtocol.failuresBeforeSuccess {
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
