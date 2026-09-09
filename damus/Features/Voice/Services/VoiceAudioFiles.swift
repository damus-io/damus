import Foundation
import AVFoundation
import AudioToolbox
import CryptoKit

/// Application resource bounds, independent of Apple's server recognition limits.
enum VoiceLimits {
    static let recordingDuration: TimeInterval = 300
    static let playbackDuration: TimeInterval = 1800
    static let mediaBytes = 32 * 1024 * 1024
    static let cacheBytes = 96 * 1024 * 1024
    static let recognitionTimeout: TimeInterval = 180
}

/// User-visible media failures never replace or hide the event's signed transcript.
struct VoiceFailure: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// A player is constructed and prepared away from the main actor, then transferred once.
struct PreparedVoiceAudio: @unchecked Sendable {
    let player: AVAudioPlayer
    let duration: TimeInterval
    let sha256: String
    let size: Int
}

/// Refuse redirects for authenticated uploads and HTTPS downgrades for downloads.
final class VoiceHTTPRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let allowsRedirects: Bool
    init(allowsRedirects: Bool) { self.allowsRedirects = allowsRedirects }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard allowsRedirects, let url = request.url,
              VoiceMediaReference.isHTTPSURL(url.absoluteString) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// Injectable HTTP boundary; production still enforces streaming limits and redirect policy.
protocol VoiceHTTPTransport: Sendable {
    func send(_ request: URLRequest, limit: Int, redirects: Bool) async throws -> (Data, HTTPURLResponse)
}

struct VoiceURLSessionTransport: VoiceHTTPTransport {
    func send(_ request: URLRequest, limit: Int, redirects: Bool) async throws -> (Data, HTTPURLResponse) {
        try await VoiceAudioFiles.request(request, limit: limit, redirects: redirects)
    }
}

/// All file IO, hashing, full decoding and bounded HTTP reads run on this actor.
/// Cache hits are rehashed and decoded; a filename alone is never proof of integrity.
actor VoiceAudioFiles {
    private let cacheRoot: URL?
    private let transport: any VoiceHTTPTransport
    private var cleanedTemporaryFiles = false
    private var activeDownloads = 0
    private var activeInspections = 0

    init(cacheRoot: URL? = nil, transport: any VoiceHTTPTransport = VoiceURLSessionTransport()) {
        self.cacheRoot = cacheRoot
        self.transport = transport
    }
    static let shared = VoiceAudioFiles()

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Read with a hard byte cap. URLSession's resource timeout also bounds stalled responses.
    static func request(_ request: URLRequest, limit: Int, redirects: Bool) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = nil
        config.httpCookieStorage = nil
        let delegate = VoiceHTTPRedirectPolicy(allowsRedirects: redirects)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw VoiceFailure("The server returned an invalid response.") }
        if response.expectedContentLength > Int64(limit) { throw VoiceFailure("The recording is too large.") }
        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1024))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw VoiceFailure("The server response exceeds the size limit.") }
            data.append(byte)
        }
        return (data, response)
    }

    /// Accept a signed reference without requiring a filename extension or accurate duration tag.
    func remote(_ reference: VoiceMediaReference) async throws -> PreparedVoiceAudio {
        while activeDownloads >= 2 { try await Task.sleep(nanoseconds: 100_000_000) }
        try Task.checkCancellation()
        activeDownloads += 1
        defer { activeDownloads -= 1 }
        _ = try VoiceMediaReference(tags: reference.tags)
        let directory = try cacheDirectory()
        let cached = directory.appendingPathComponent(reference.sha256)
        if FileManager.default.fileExists(atPath: cached.path) {
            do {
                let result = try await inspect(cached, mime: reference.mimeType, expectedHash: reference.sha256)
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cached.path)
                return result
            } catch is CancellationError { throw CancellationError() }
            catch { try? FileManager.default.removeItem(at: cached) }
        }
        guard let url = URL(string: reference.url) else { throw VoiceFailure("The recording URL is invalid.") }
        var request = URLRequest(url: url)
        request.setValue("audio/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(request, limit: VoiceLimits.mediaBytes, redirects: true)
        guard data.count <= VoiceLimits.mediaBytes else { throw VoiceFailure("The recording is too large.") }
        guard response.statusCode == 200 else { throw VoiceFailure("The recording server returned HTTP \(response.statusCode).") }
        guard Self.digest(data) == reference.sha256 else { throw VoiceFailure("The recording hash does not match this post.") }
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        let result = try await inspect(temporary, mime: reference.mimeType, expectedHash: reference.sha256)
        try Task.checkCancellation()
        // Prepared players own their bytes, so cache eviction cannot remove playing media.
        try evictCache(in: directory, reserving: data.count)
        if FileManager.default.fileExists(atPath: cached.path) { try FileManager.default.removeItem(at: cached) }
        try FileManager.default.moveItem(at: temporary, to: cached)
        return result
    }

    /// Verify actual bytes and fully decode the bounded file before constructing a player.
    func inspect(_ url: URL, mime: String = "audio/mp4", expectedHash: String? = nil) async throws -> PreparedVoiceAudio {
        while activeInspections >= 2 { try await Task.sleep(nanoseconds: 100_000_000) }
        try Task.checkCancellation()
        activeInspections += 1
        defer { activeInspections -= 1 }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= VoiceLimits.mediaBytes else { throw VoiceFailure("The recording is empty or exceeds the size limit.") }
        let handle = try FileHandle(forReadingFrom: url)
        let data: Data
        do {
            data = try handle.read(upToCount: VoiceLimits.mediaBytes + 1) ?? Data()
            try handle.close()
        } catch { try? handle.close(); throw error }
        guard data.count == size else { throw VoiceFailure("The recording changed while it was being read.") }
        let hash = Self.digest(data)
        if let expectedHash, hash != expectedHash { throw VoiceFailure("The recording hash does not match this post.") }
        // Decode a private immutable snapshot of the bytes that will be handed to the player.
        // Neither cache replacement during an await nor another file owner can change this input.
        let extensions = ["audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/mpeg": "mp3",
                          "audio/wav": "wav", "audio/wave": "wav", "audio/x-wav": "wav",
                          "audio/aac": "aac", "audio/flac": "flac", "audio/aiff": "aiff"]
        let suffix = extensions[VoiceMediaReference.normalizedMIME(mime)] ?? "audio"
        let snapshot = try cacheDirectory().appendingPathComponent(UUID().uuidString + ".decode." + suffix)
        try data.write(to: snapshot, options: .atomic)
        defer { try? FileManager.default.removeItem(at: snapshot) }
        var audioFile: AudioFileID?
        guard AudioFileOpenURL(snapshot as CFURL, .readPermission, 0, &audioFile) == noErr, let audioFile else {
            throw VoiceFailure("This file is not a supported audio recording.")
        }
        defer { AudioFileClose(audioFile) }
        var type: AudioFileTypeID = 0
        var propertySize = UInt32(MemoryLayout<AudioFileTypeID>.size)
        guard AudioFileGetProperty(audioFile, kAudioFilePropertyFileFormat, &propertySize, &type) == noErr else {
            throw VoiceFailure("The recording format could not be verified.")
        }
        let compatible: Bool
        switch VoiceMediaReference.normalizedMIME(mime) {
        case "audio/mp4", "audio/x-m4a": compatible = type == kAudioFileM4AType || type == kAudioFileMPEG4Type
        case "audio/mpeg": compatible = type == kAudioFileMP3Type
        case "audio/wav", "audio/wave", "audio/x-wav": compatible = type == kAudioFileWAVEType
        case "audio/aac": compatible = type == kAudioFileAAC_ADTSType
        case "audio/flac": compatible = type == kAudioFileFLACType
        case "audio/aiff": compatible = type == kAudioFileAIFFType || type == kAudioFileAIFCType
        default: compatible = false
        }
        guard compatible else { throw VoiceFailure("The recording's real format does not match its audio type.") }
        let asset = AVURLAsset(url: snapshot)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard videoTracks.isEmpty else { throw VoiceFailure("This voice post points to a video file.") }
        let file = try AVAudioFile(forReading: snapshot)
        let format = file.processingFormat
        guard format.sampleRate.isFinite, (8000...192000).contains(format.sampleRate),
              (1...8).contains(Int(format.channelCount)) else { throw VoiceFailure("The recording has an unsupported audio format.") }
        let duration = Double(file.length) / format.sampleRate
        guard duration.isFinite, duration > 0, duration <= VoiceLimits.playbackDuration else {
            throw VoiceFailure("The recording is empty or exceeds the playback duration limit.")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16384) else {
            throw VoiceFailure("The recording could not be decoded.")
        }
        let deadline = Date().addingTimeInterval(30)
        var frames: AVAudioFramePosition = 0
        while frames < file.length {
            try Task.checkCancellation()
            guard Date() < deadline else { throw VoiceFailure("Audio verification timed out.") }
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(16384, file.length - frames)))
            guard buffer.frameLength > 0 else { throw VoiceFailure("The recording is truncated.") }
            frames += AVAudioFramePosition(buffer.frameLength)
        }
        let player = try AVAudioPlayer(data: data)
        guard player.prepareToPlay() else { throw VoiceFailure("The recording cannot be played on this device.") }
        return PreparedVoiceAudio(player: player, duration: Double(frames) / format.sampleRate, sha256: hash, size: size)
    }

    private func cacheDirectory() throws -> URL {
        let directory: URL
        if let cacheRoot { directory = cacheRoot }
        else {
            directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("VerifiedVoice", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !cleanedTemporaryFiles {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "partial" || file.lastPathComponent.contains(".decode.") {
                try? FileManager.default.removeItem(at: file)
            }
            cleanedTemporaryFiles = true
        }
        return directory
    }

    private func evictCache(in directory: URL, reserving bytes: Int) throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            .filter { VoiceMediaReference.isSHA256($0.lastPathComponent) }
            .map { ($0, try $0.resourceValues(forKeys: keys)) }
            .sorted { ($0.1.contentModificationDate ?? .distantPast) < ($1.1.contentModificationDate ?? .distantPast) }
        var total = files.reduce(bytes) { $0 + ($1.1.fileSize ?? 0) }
        for (url, values) in files where total > VoiceLimits.cacheBytes {
            try FileManager.default.removeItem(at: url)
            total -= values.fileSize ?? 0
        }
    }
}
