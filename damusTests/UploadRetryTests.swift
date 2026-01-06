//
//  UploadRetryTests.swift
//  damusTests
//
//  Tests for upload retry logic with simulated network conditions.
//

import XCTest
@testable import damus

final class UploadRetryTests: XCTestCase {

    var testMediaURL: URL!
    var mockUploader: TestMediaUploader!
    var mockSession: URLSession!

    override func setUp() {
        super.setUp()

        // Create a test image file
        let testImage = UIImage(systemName: "photo")!
        let imageData = testImage.pngData()!
        testMediaURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_upload.png")
        try? imageData.write(to: testMediaURL)

        mockUploader = TestMediaUploader()

        // Create session with mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RetryTestURLProtocol.self]
        mockSession = URLSession(configuration: config)

        // Reset mock state
        RetryTestURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testMediaURL)
        RetryTestURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Retry Logic Tests

    @MainActor
    func testUploadSucceedsOnFirstTry() async {
        // Setup: Configure mock to succeed immediately
        RetryTestURLProtocol.failuresBeforeSuccess = 0
        RetryTestURLProtocol.successResponse = makeSuccessResponse()

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: .default,
            session: mockSession
        )

        // Verify success
        if case .success(let url) = result {
            XCTAssertEqual(url, "https://example.com/uploaded.jpg")
        } else {
            XCTFail("Expected success, got \(result)")
        }

        // Verify only one request was made
        XCTAssertEqual(RetryTestURLProtocol.requestCount, 1)
    }

    @MainActor
    func testUploadSucceedsAfterOneRetry() async {
        // Setup: Fail once, then succeed
        RetryTestURLProtocol.failuresBeforeSuccess = 1
        RetryTestURLProtocol.failureError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: nil
        )
        RetryTestURLProtocol.successResponse = makeSuccessResponse()

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: UploadRetryConfig(maxRetries: 2, baseDelaySeconds: 0.01), // Fast retries for testing
            session: mockSession
        )

        // Verify success
        if case .success(let url) = result {
            XCTAssertEqual(url, "https://example.com/uploaded.jpg")
        } else {
            XCTFail("Expected success after retry, got \(result)")
        }

        // Verify exactly 2 requests were made (1 failure + 1 success)
        XCTAssertEqual(RetryTestURLProtocol.requestCount, 2)
    }

    @MainActor
    func testUploadSucceedsAfterTwoRetries() async {
        // Setup: Fail twice, then succeed
        RetryTestURLProtocol.failuresBeforeSuccess = 2
        RetryTestURLProtocol.failureError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: nil
        )
        RetryTestURLProtocol.successResponse = makeSuccessResponse()

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: UploadRetryConfig(maxRetries: 2, baseDelaySeconds: 0.01),
            session: mockSession
        )

        // Verify success
        if case .success(let url) = result {
            XCTAssertEqual(url, "https://example.com/uploaded.jpg")
        } else {
            XCTFail("Expected success after retries, got \(result)")
        }

        // Verify exactly 3 requests were made (2 failures + 1 success)
        XCTAssertEqual(RetryTestURLProtocol.requestCount, 3)
    }

    @MainActor
    func testUploadFailsAfterMaxRetries() async {
        // Setup: Always fail with timeout
        RetryTestURLProtocol.failuresBeforeSuccess = 100 // Always fail
        RetryTestURLProtocol.failureError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: nil
        )

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: UploadRetryConfig(maxRetries: 2, baseDelaySeconds: 0.01),
            session: mockSession
        )

        // Verify failure
        if case .failed(let error) = result {
            if case .networkError = error {
                // Expected
            } else {
                XCTFail("Expected network error, got \(error)")
            }
        } else {
            XCTFail("Expected failure, got \(result)")
        }

        // Verify exactly 3 requests were made (1 initial + 2 retries)
        XCTAssertEqual(RetryTestURLProtocol.requestCount, 3)
    }

    @MainActor
    func testNonRetryableErrorFailsImmediately() async {
        // Setup: Fail with non-retryable error (certificate error)
        RetryTestURLProtocol.failuresBeforeSuccess = 100
        RetryTestURLProtocol.failureError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorSecureConnectionFailed,
            userInfo: nil
        )

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: UploadRetryConfig(maxRetries: 2, baseDelaySeconds: 0.01),
            session: mockSession
        )

        // Verify failure
        if case .failed(let error) = result {
            if case .networkError = error {
                // Expected
            } else {
                XCTFail("Expected network error, got \(error)")
            }
        } else {
            XCTFail("Expected failure, got \(result)")
        }

        // Verify only 1 request was made (no retries for non-retryable errors)
        XCTAssertEqual(RetryTestURLProtocol.requestCount, 1)
    }

    @MainActor
    func testNoRetriesWhenConfigured() async {
        // Setup: Fail with retryable error, but retries disabled
        RetryTestURLProtocol.failuresBeforeSuccess = 100
        RetryTestURLProtocol.failureError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: nil
        )

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: .none, // No retries
            session: mockSession
        )

        // Verify failure
        if case .failed = result {
            // Expected
        } else {
            XCTFail("Expected failure, got \(result)")
        }

        // Verify only 1 request was made
        XCTAssertEqual(RetryTestURLProtocol.requestCount, 1)
    }

    @MainActor
    func testConnectionLostIsRetryable() async {
        // Setup: Fail once with connection lost, then succeed
        RetryTestURLProtocol.failuresBeforeSuccess = 1
        RetryTestURLProtocol.failureError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: nil
        )
        RetryTestURLProtocol.successResponse = makeSuccessResponse()

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: UploadRetryConfig(maxRetries: 1, baseDelaySeconds: 0.01),
            session: mockSession
        )

        // Verify success after retry
        if case .success = result {
            // Expected
        } else {
            XCTFail("Expected success after retry, got \(result)")
        }

        XCTAssertEqual(RetryTestURLProtocol.requestCount, 2)
    }

    @MainActor
    func testDNSFailureIsRetryable() async {
        // Setup: Fail once with DNS failure, then succeed
        RetryTestURLProtocol.failuresBeforeSuccess = 1
        RetryTestURLProtocol.failureError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorDNSLookupFailed,
            userInfo: nil
        )
        RetryTestURLProtocol.successResponse = makeSuccessResponse()

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: UploadRetryConfig(maxRetries: 1, baseDelaySeconds: 0.01),
            session: mockSession
        )

        // Verify success after retry
        if case .success = result {
            // Expected
        } else {
            XCTFail("Expected success after retry, got \(result)")
        }

        XCTAssertEqual(RetryTestURLProtocol.requestCount, 2)
    }

    // MARK: - UploadError.isRetryable Tests

    func testTimeoutErrorIsRetryable() {
        let error = UploadError.networkError(underlying: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: nil
        ))
        XCTAssertTrue(error.isRetryable)
    }

    func testConnectionLostErrorIsRetryable() {
        let error = UploadError.networkError(underlying: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: nil
        ))
        XCTAssertTrue(error.isRetryable)
    }

    func testNotConnectedErrorIsRetryable() {
        let error = UploadError.networkError(underlying: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: nil
        ))
        XCTAssertTrue(error.isRetryable)
    }

    func testDNSErrorIsRetryable() {
        let error = UploadError.networkError(underlying: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorDNSLookupFailed,
            userInfo: nil
        ))
        XCTAssertTrue(error.isRetryable)
    }

    func testCannotConnectErrorIsRetryable() {
        let error = UploadError.networkError(underlying: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: nil
        ))
        XCTAssertTrue(error.isRetryable)
    }

    func testServerErrorIsNotRetryable() {
        let error = UploadError.serverError(message: "File too large")
        XCTAssertFalse(error.isRetryable)
    }

    func testFileReadErrorIsNotRetryable() {
        let error = UploadError.fileReadError(underlying: NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoSuchFileError,
            userInfo: nil
        ))
        XCTAssertFalse(error.isRetryable)
    }

    func testInvalidAPIURLIsNotRetryable() {
        let error = UploadError.invalidAPIURL
        XCTAssertFalse(error.isRetryable)
    }

    func testNoMediaDataIsNotRetryable() {
        let error = UploadError.noMediaData
        XCTAssertFalse(error.isRetryable)
    }

    func testCertificateErrorIsNotRetryable() {
        let error = UploadError.networkError(underlying: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorSecureConnectionFailed,
            userInfo: nil
        ))
        XCTAssertFalse(error.isRetryable)
    }

    func testHttpError4xxIsNotRetryable() {
        let error = UploadError.httpError(statusCode: 400, message: "Bad Request")
        XCTAssertFalse(error.isRetryable)

        let error413 = UploadError.httpError(statusCode: 413, message: "Payload Too Large")
        XCTAssertFalse(error413.isRetryable)

        let error401 = UploadError.httpError(statusCode: 401, message: "Unauthorized")
        XCTAssertFalse(error401.isRetryable)
    }

    func testHttpError5xxIsRetryable() {
        let error = UploadError.httpError(statusCode: 500, message: "Internal Server Error")
        XCTAssertTrue(error.isRetryable)

        let error502 = UploadError.httpError(statusCode: 502, message: "Bad Gateway")
        XCTAssertTrue(error502.isRetryable)

        let error503 = UploadError.httpError(statusCode: 503, message: "Service Unavailable")
        XCTAssertTrue(error503.isRetryable)
    }

    // MARK: - HTTP Status Code Integration Tests

    @MainActor
    func testHttp400DoesNotRetry() async {
        // Setup: Return 400 Bad Request
        RetryTestURLProtocol.httpResponse = make400Response()

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: UploadRetryConfig(maxRetries: 2, baseDelaySeconds: 0.01),
            session: mockSession
        )

        // Verify failure with HTTP error
        if case .failed(let error) = result {
            if case .httpError(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 400)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } else {
            XCTFail("Expected failure, got \(result)")
        }

        // Verify only 1 request was made (no retries for 4xx)
        XCTAssertEqual(RetryTestURLProtocol.requestCount, 1)
    }

    @MainActor
    func testHttp413DoesNotRetry() async {
        // Setup: Return 413 Payload Too Large
        RetryTestURLProtocol.httpResponse = make413Response()

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: UploadRetryConfig(maxRetries: 2, baseDelaySeconds: 0.01),
            session: mockSession
        )

        // Verify failure with HTTP error
        if case .failed(let error) = result {
            if case .httpError(let statusCode, let message) = error {
                XCTAssertEqual(statusCode, 413)
                XCTAssertTrue(message.contains("too large") || message.contains("25MB"),
                              "Error message should mention size limit")
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } else {
            XCTFail("Expected failure, got \(result)")
        }

        // Verify only 1 request was made (no retries for 4xx)
        XCTAssertEqual(RetryTestURLProtocol.requestCount, 1)
    }

    @MainActor
    func testHttp500DoesRetry() async {
        // Setup: Always return 500 Internal Server Error
        RetryTestURLProtocol.httpResponse = make500Response()

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(testMediaURL),
            mediaUploader: mockUploader,
            mediaType: .normal,
            progress: MockProgressDelegate(),
            keypair: nil,
            retryConfig: UploadRetryConfig(maxRetries: 2, baseDelaySeconds: 0.01),
            session: mockSession
        )

        // Verify failure with HTTP error
        if case .failed(let error) = result {
            if case .httpError(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } else {
            XCTFail("Expected failure, got \(result)")
        }

        // Verify 3 requests were made (1 initial + 2 retries for 5xx)
        XCTAssertEqual(RetryTestURLProtocol.requestCount, 3)
    }

    // MARK: - Helpers

    private func makeSuccessResponse() -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/upload")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let responseData = """
        {
            "status": "success",
            "nip94_event": {
                "tags": [["url", "https://example.com/uploaded.jpg"]]
            }
        }
        """.data(using: .utf8)!

        return (response, responseData)
    }

    private func make400Response() -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/upload")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        let responseData = """
        {
            "status": "error",
            "message": "Bad request: invalid file format"
        }
        """.data(using: .utf8)!

        return (response, responseData)
    }

    private func make413Response() -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/upload")!,
            statusCode: 413,
            httpVersion: nil,
            headerFields: nil
        )!

        let responseData = """
        {
            "status": "error",
            "message": "File too large. Maximum size is 25MB."
        }
        """.data(using: .utf8)!

        return (response, responseData)
    }

    private func make500Response() -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/upload")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!

        let responseData = """
        {
            "status": "error",
            "message": "Internal server error"
        }
        """.data(using: .utf8)!

        return (response, responseData)
    }
}

// MARK: - Test Helpers

class TestMediaUploader: MediaUploaderProtocol {
    var id: String { "test" }
    var nameParam: String { "file" }
    var mediaTypeParam: String { "media_type" }
    var supportsVideo: Bool { true }
    var requiresNip98: Bool { false }
    var postAPI: String { "https://api.example.com/upload" }

    func getMediaURL(from data: Data) -> Result<String, UploadError> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            return .failure(.jsonParsingFailed)
        }

        if status == "success",
           let nip94 = json["nip94_event"] as? [String: Any],
           let tags = nip94["tags"] as? [[String]],
           let urlTag = tags.first(where: { $0.first == "url" }),
           urlTag.count > 1 {
            return .success(urlTag[1])
        } else if status == "error", let message = json["message"] as? String {
            return .failure(.serverError(message: message))
        } else {
            return .failure(.missingURL)
        }
    }

    func mediaTypeValue(for mediaType: ImageUploadMediaType) -> String? {
        return nil
    }
}

class MockProgressDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        // No-op for tests
    }
}
