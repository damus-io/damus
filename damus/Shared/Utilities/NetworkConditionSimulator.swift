//
//  NetworkConditionSimulator.swift
//  damus
//
//  Debug-only network condition simulator for UI testing.
//  Activated via launch arguments to simulate poor network conditions.
//

import Foundation

#if DEBUG

/// Simulates various network conditions for testing purposes.
/// Only available in DEBUG builds.
///
/// Usage in UI tests:
/// ```swift
/// app.launchArguments += ["-SimulateNetworkCondition", "timeout"]
/// app.launch()
/// ```
///
/// Supported conditions:
/// - `timeout`: Simulates request timeout after 2 seconds
/// - `connectionLost`: Simulates connection lost error
/// - `notConnected`: Simulates no internet connection
/// - `slowNetwork`: Adds 3 second delay before responding
/// - `failThenSucceed`: Fails first request, succeeds on retry
///
/// To apply only to specific URL patterns:
/// ```swift
/// app.launchArguments += ["-SimulateNetworkCondition", "timeout", "-SimulateNetworkPattern", "upload"]
/// ```
enum NetworkConditionSimulator {

    /// Call this early in app launch (e.g., in AppDelegate or @main)
    static func configureFromLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments

        guard let conditionIndex = args.firstIndex(of: "-SimulateNetworkCondition"),
              conditionIndex + 1 < args.count else {
            return
        }

        let condition = args[conditionIndex + 1]

        // Check for optional URL pattern filter
        var urlPattern: String? = nil
        if let patternIndex = args.firstIndex(of: "-SimulateNetworkPattern"),
           patternIndex + 1 < args.count {
            urlPattern = args[patternIndex + 1]
        }

        Log.info("NetworkConditionSimulator: Activating condition '%{public}@' for pattern '%{public}@'",
                 for: .image_uploading, condition, urlPattern ?? "*")

        SimulatedNetworkProtocol.condition = NetworkCondition(rawValue: condition) ?? .timeout
        SimulatedNetworkProtocol.urlPattern = urlPattern
        SimulatedNetworkProtocol.requestCount = 0

        // Register the protocol to intercept all requests
        URLProtocol.registerClass(SimulatedNetworkProtocol.self)
    }

    /// Network conditions that can be simulated
    enum NetworkCondition: String {
        case timeout
        case connectionLost
        case notConnected
        case slowNetwork
        case failThenSucceed
        case serverError
    }
}

/// URLProtocol subclass that simulates network conditions
private class SimulatedNetworkProtocol: URLProtocol {
    static var condition: NetworkConditionSimulator.NetworkCondition = .timeout
    static var urlPattern: String? = nil
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        // Only intercept if URL matches pattern (or no pattern specified)
        if let pattern = urlPattern,
           let url = request.url?.absoluteString,
           !url.contains(pattern) {
            return false
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        SimulatedNetworkProtocol.requestCount += 1
        let currentCount = SimulatedNetworkProtocol.requestCount

        Log.debug("NetworkConditionSimulator: Intercepted request #%{public}d to %{public}@",
                  for: .image_uploading, currentCount, request.url?.absoluteString ?? "unknown")

        switch SimulatedNetworkProtocol.condition {
        case .timeout:
            // Simulate timeout after delay
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [
                    NSLocalizedDescriptionKey: "Simulated timeout"
                ])
                self.client?.urlProtocol(self, didFailWithError: error)
            }

        case .connectionLost:
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: [
                NSLocalizedDescriptionKey: "Simulated connection lost"
            ])
            client?.urlProtocol(self, didFailWithError: error)

        case .notConnected:
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [
                NSLocalizedDescriptionKey: "Simulated no internet connection"
            ])
            client?.urlProtocol(self, didFailWithError: error)

        case .slowNetwork:
            // Add delay then forward to real network
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.forwardToRealNetwork()
            }

        case .failThenSucceed:
            // Fail first 2 requests, then succeed
            if currentCount <= 2 {
                let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [
                    NSLocalizedDescriptionKey: "Simulated timeout (attempt \(currentCount))"
                ])
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                forwardToRealNetwork()
            }

        case .serverError:
            // Return a 500 server error
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let errorData = """
            {"status": "error", "message": "Simulated server error"}
            """.data(using: .utf8)!

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: errorData)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        // Nothing to do
    }

    /// Forward request to the real network (for slowNetwork condition)
    private func forwardToRealNetwork() {
        // Unregister ourselves temporarily to avoid infinite loop
        URLProtocol.unregisterClass(SimulatedNetworkProtocol.self)

        let session = URLSession.shared
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Re-register for future requests
            URLProtocol.registerClass(SimulatedNetworkProtocol.self)

            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            if let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }

            if let data = data {
                self.client?.urlProtocol(self, didLoad: data)
            }

            self.client?.urlProtocolDidFinishLoading(self)
        }
        task.resume()
    }
}

#endif
