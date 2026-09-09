import XCTest
import AVFoundation
import UIKit
import ImageIO
@testable import damus

/// Real AAC fixtures exercise the production hash/container/decoder path; HTTP is local and deterministic.
final class VoiceMediaServicesTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeAAC(to url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48000]
        let writer = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: writer.processingFormat, frameCapacity: 16000))
        buffer.frameLength = 16000
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<16000 { channel[index] = 0.1 * sin(Float(index) * 2 * .pi * 440 / 16000) }
        try writer.write(from: buffer)
    }

    func testDownloadVerifiesRealAudioAndRevalidatesTamperedCache() async throws {
        let root = try directory()
        let source = root.appendingPathComponent("source.m4a")
        try writeAAC(to: source)
        let bytes = try Data(contentsOf: source)
        let hash = VoiceAudioFiles.digest(bytes)
        let url = "https://media.example/opaque?token=a%2Fb"
        let transport = VoiceHTTPFixture { request in
            (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let cache = root.appendingPathComponent("cache")
        let files = VoiceAudioFiles(cacheRoot: cache, transport: transport)
        let reference = try VoiceMediaReference(tags: [["url", url], ["blossom", hash, "audio/mp4"], ["duration", "999999"]])
        let first = try await files.remote(reference)
        XCTAssertEqual(first.sha256, hash)
        XCTAssertEqual(first.size, bytes.count)
        XCTAssertGreaterThan(first.duration, 0.5)
        XCTAssertLessThan(first.duration, 2)
        _ = try await files.remote(reference)
        var calls = await transport.history()
        XCTAssertEqual(calls.count, 1, "A verified cache hit should not fetch again")
        try Data("tampered".utf8).write(to: cache.appendingPathComponent(hash))
        let repaired = try await files.remote(reference)
        XCTAssertEqual(repaired.sha256, hash)
        calls = await transport.history()
        XCTAssertEqual(calls.count, 2, "A matching cache filename cannot authorize changed bytes")
        XCTAssertEqual(calls.first?.request.url?.absoluteString, url)
        XCTAssertEqual(try Data(contentsOf: cache.appendingPathComponent(hash)), bytes)
    }

    func testMatchingHashCannotMakeHTMLOrWrongContainerPlayable() async throws {
        let root = try directory()
        let source = root.appendingPathComponent("source.m4a")
        try writeAAC(to: source)
        let bytes = try Data(contentsOf: source)
        for (data, mime) in [(bytes, "audio/mpeg"), (Data("<html>not audio</html>".utf8), "audio/mp4")] {
            let transport = VoiceHTTPFixture { request in
                (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let files = VoiceAudioFiles(cacheRoot: root.appendingPathComponent(UUID().uuidString), transport: transport)
            let reference = try VoiceMediaReference(url: "https://media.example/file", sha256: VoiceAudioFiles.digest(data), mimeType: mime, duration: 1)
            do { _ = try await files.remote(reference); XCTFail("Unverified media became playable") }
            catch { XCTAssertFalse(error is CancellationError) }
        }
    }

    func testWrongHashIsRejectedBeforeCacheAdmission() async throws {
        let root = try directory()
        let transport = VoiceHTTPFixture { request in
            (Data("wrong bytes".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let files = VoiceAudioFiles(cacheRoot: root, transport: transport)
        let reference = try VoiceMediaReference(url: "https://media.example/file", sha256: String(repeating: "a", count: 64), mimeType: "audio/mp4", duration: 1)
        do { _ = try await files.remote(reference); XCTFail("Wrong bytes were accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("hash")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(reference.sha256).path))
    }

    func testUploadUsesNostrBuildAndSignedBUD11AuthorizationForExactBytes() async throws {
        let root = try directory()
        let source = root.appendingPathComponent("source.m4a")
        try writeAAC(to: source)
        let exactURL = "https://blossom.band/opaque?receipt=a%2Fb"
        let transport = VoiceHTTPFixture { request in
            let bytes = request.httpBody!
            let object: [String: Any] = ["url": exactURL, "sha256": VoiceAudioFiles.digest(bytes), "size": bytes.count, "type": "audio/mp4"]
            return (try JSONSerialization.data(withJSONObject: object),
                    HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }
        let files = VoiceAudioFiles(cacheRoot: root.appendingPathComponent("cache"))
        let uploader = VoiceBlossomUploader(files: files, transport: transport)
        let keys = generate_new_keypair()
        let receipt = try await uploader.upload(file: source, server: "", keypair: keys, lifetime: VoiceAccountLifetime())
        let calls = await transport.history()
        let sent = try XCTUnwrap(calls.first)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(sent.request.url?.absoluteString, "https://blossom.band/upload")
        XCTAssertEqual(sent.request.httpMethod, "PUT")
        XCTAssertEqual(sent.request.httpBody, try Data(contentsOf: source))
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
        XCTAssertFalse(sent.redirects)
        XCTAssertEqual(receipt.reference.url, exactURL)
        XCTAssertEqual(receipt.reference.sha256, VoiceAudioFiles.digest(try Data(contentsOf: source)))
        let authorization = try XCTUnwrap(sent.request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authorization.hasPrefix("Nostr "))
        let token = String(authorization.dropFirst(6))
        XCTAssertFalse(token.contains("="))
        XCTAssertFalse(token.contains("+"))
        XCTAssertFalse(token.contains("/"))
        var base64 = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        let auth = try JSONDecoder().decode(NostrEvent.self, from: XCTUnwrap(Data(base64Encoded: base64)))
        XCTAssertTrue(auth.verify())
        XCTAssertEqual(auth.known_kind, .blossom_auth)
        XCTAssertEqual(auth.pubkey, keys.pubkey)
        XCTAssertTrue(auth.tags.strings().contains(["server", "blossom.band"]))
        XCTAssertTrue(auth.tags.strings().contains(["x", receipt.reference.sha256]))
        XCTAssertTrue(auth.tags.strings().contains(["t", "upload"]))
    }

    func testServerRejectionAndForgedReceiptsKeepLocalRecording() async throws {
        let root = try directory()
        let source = root.appendingPathComponent("source.m4a")
        try writeAAC(to: source)
        let original = try Data(contentsOf: source)
        let files = VoiceAudioFiles(cacheRoot: root.appendingPathComponent("cache"))
        for variant in 0..<5 {
            let transport = VoiceHTTPFixture { request in
                let bytes = request.httpBody!
                var object: [String: Any] = ["url": "https://blossom.band/audio", "sha256": VoiceAudioFiles.digest(bytes),
                                             "size": bytes.count, "type": "audio/mp4"]
                if variant == 0 { object["sha256"] = String(repeating: "b", count: 64) }
                if variant == 1 { object["size"] = bytes.count + 1 }
                if variant == 2 { object["type"] = "video/mp4" }
                if variant == 3 { object["url"] = "http://blossom.band/audio" }
                return (try JSONSerialization.data(withJSONObject: object),
                        HTTPURLResponse(url: request.url!, statusCode: variant == 4 ? 403 : 200, httpVersion: nil, headerFields: nil)!)
            }
            let uploader = VoiceBlossomUploader(files: files, transport: transport)
            do {
                _ = try await uploader.upload(file: source, server: "https://blossom.band", keypair: generate_new_keypair(), lifetime: VoiceAccountLifetime())
                XCTFail("Invalid upload response was accepted: \(variant)")
            } catch { XCTAssertEqual(try Data(contentsOf: source), original) }
        }
    }

    func testRedirectPolicyRejectsAuthenticatedRedirectAndHTTPSDowngrade() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://blossom.band/upload")!
        let task = session.dataTask(with: original)
        let response = HTTPURLResponse(url: original, statusCode: 307, httpVersion: nil, headerFields: nil)!
        let upload = VoiceHTTPRedirectPolicy(allowsRedirects: false)
        upload.urlSession(session, task: task, willPerformHTTPRedirection: response,
                          newRequest: URLRequest(url: URL(string: "https://elsewhere.example/upload")!)) { XCTAssertNil($0) }
        let download = VoiceHTTPRedirectPolicy(allowsRedirects: true)
        download.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "http://media.example/audio")!)) { XCTAssertNil($0) }
        download.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "https://media.example/audio")!)) { XCTAssertNotNil($0) }
    }

    @MainActor
    func testPreparedPhotoUploadValidatesExactJPEGReceiptAndKeepsLocalFileOnFailure() async throws {
        let root = try directory()
        let file = root.appendingPathComponent("photo.jpg")
        let input = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
        let prepared = try await VoicePhotoFiles.shared.prepare(input, to: file)
        let bytes = try Data(contentsOf: file)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(metadata[kCGImagePropertyPixelWidth] as? NSNumber)
        let height = try XCTUnwrap(metadata[kCGImagePropertyPixelHeight] as? NSNumber)
        XCTAssertEqual(prepared.dim, "\(width.intValue)x\(height.intValue)")
        XCTAssertNil(metadata[kCGImagePropertyGPSDictionary])
        for variant in 0..<6 {
            let lifetime = VoiceAccountLifetime()
            let transport = VoiceHTTPFixture { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
                XCTAssertEqual(request.httpBody, bytes)
                XCTAssertEqual(request.url?.absoluteString, "https://blossom.band/upload")
                var object: [String: Any] = ["url": "https://blossom.band/opaque?image=exact",
                    "sha256": VoiceAudioFiles.digest(bytes), "size": bytes.count, "type": "image/jpeg"]
                if variant == 1 { object["sha256"] = String(repeating: "b", count: 64) }
                if variant == 2 { object["size"] = bytes.count + 1 }
                if variant == 3 { object["type"] = "audio/mp4" }
                if variant == 4 { object["url"] = "http://blossom.band/photo" }
                if variant == 5 { lifetime.invalidate() } // Response arrives after account cancellation.
                return (try JSONSerialization.data(withJSONObject: object),
                        HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
            }
            let uploader = VoiceBlossomUploader(transport: transport)
            do {
                let url = try await uploader.uploadPhoto(file: file, server: "", keypair: generate_new_keypair(), lifetime: lifetime)
                XCTAssertEqual(variant, 0)
                XCTAssertEqual(url, "https://blossom.band/opaque?image=exact")
            } catch {
                XCTAssertNotEqual(variant, 0, "\(error)")
                if variant == 5 { XCTAssertTrue(error is CancellationError) }
            }
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            let attempts = await transport.history()
            XCTAssertFalse(try XCTUnwrap(attempts.first).redirects)
        }
    }
}

private actor VoiceHTTPFixture: VoiceHTTPTransport {
    struct Attempt: Sendable {
        let request: URLRequest
        let limit: Int
        let redirects: Bool
    }
    private var attempts: [Attempt] = []
    private let response: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    init(response: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) { self.response = response }
    func send(_ request: URLRequest, limit: Int, redirects: Bool) async throws -> (Data, HTTPURLResponse) {
        attempts.append(Attempt(request: request, limit: limit, redirects: redirects))
        return try response(request)
    }
    func history() -> [Attempt] { attempts }
}
