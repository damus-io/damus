import Foundation

protocol VoiceUploading: Sendable {
    func upload(file: URL, server: String, keypair: FullKeypair, lifetime: VoiceAccountLifetime) async throws -> VoiceUploadReceipt
}

/// Photo uploads share the same Blossom authorization and receipt checks as recordings.
protocol VoicePhotoUploading: Sendable {
    func uploadPhoto(file: URL, server: String, keypair: FullKeypair, lifetime: VoiceAccountLifetime) async throws -> String
}

/// nostr.build Blossom uploads with BUD-02 and BUD-11 authorization.
actor VoiceBlossomUploader: VoiceUploading, VoicePhotoUploading {
    static let defaultServer = "https://blossom.band"
    private let files: VoiceAudioFiles
    private let transport: any VoiceHTTPTransport

    init(files: VoiceAudioFiles = .shared, transport: any VoiceHTTPTransport = VoiceURLSessionTransport()) {
        self.files = files
        self.transport = transport
    }
    struct Descriptor: Decodable {
        let url: String
        let sha256: String
        let size: Int
        let type: String?
    }

    /// Use nostr.build's shared service or a paid account's dedicated Blossom subdomain.
    static func origin(_ value: String) throws -> URL {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = input.isEmpty ? defaultServer : input
        guard VoiceMediaReference.isHTTPSURL(server), let components = URLComponents(string: server),
              let host = components.host?.lowercased(),
              host == "blossom.band" || host.hasSuffix(".blossom.band"),
              components.port == nil || components.port == 443,
              components.path.isEmpty || components.path == "/",
              components.query == nil, let url = components.url else {
            throw VoiceFailure("Use https://blossom.band or your paid nostr.build Blossom subdomain, without a path or query.")
        }
        return url
    }

    /// Only locally decoded, audio-only MP4 bytes reach this validation. Servers may label
    /// that container as M4A, MP4 video, or unknown; the exact hash and size still must match.
    /// Canonicalize the outgoing audio tag, preserving the server's URL verbatim.
    private static func validate(_ descriptor: Descriptor, server: String, audio: PreparedVoiceAudio) throws -> VoiceUploadReceipt {
        guard descriptor.sha256 == audio.sha256 else {
            throw VoiceFailure("nostr.build returned a different recording hash. Keep this composer open and try Post again.")
        }
        guard descriptor.size == audio.size else {
            throw VoiceFailure("nostr.build returned a different recording size (\(descriptor.size) instead of \(audio.size) bytes). Keep this composer open and try Post again.")
        }
        // HTTP MIME parameters do not change the already verified container.
        let mime = descriptor.type.map { value in
            VoiceMediaReference.normalizedMIME(String(value.prefix { $0 != ";" }))
        }
        switch mime {
        case nil, "", "audio/mp4", "audio/m4a", "audio/x-m4a", "video/mp4", "application/mp4", "application/octet-stream":
            break
        default:
            throw VoiceFailure("nostr.build returned an incompatible recording type (\(String((mime ?? "unknown").prefix(80)))). Keep this composer open and try Post again.")
        }
        let reference = try VoiceMediaReference(url: descriptor.url, sha256: audio.sha256, mimeType: "audio/mp4", duration: audio.duration)
        return VoiceUploadReceipt(server: server, reference: reference, size: audio.size)
    }

    func upload(file: URL, server: String, keypair: FullKeypair, lifetime: VoiceAccountLifetime) async throws -> VoiceUploadReceipt {
        let origin = try Self.origin(server)
        let audio = try await files.inspect(file)
        let descriptor = try await uploadBytes(file: file, origin: origin, sha256: audio.sha256,
                                               size: audio.size, mime: "audio/mp4", keypair: keypair, lifetime: lifetime)
        return try Self.validate(descriptor, server: origin.absoluteString, audio: audio)
    }

    /// Prepared photos are JPEGs; receipt metadata must describe exactly those bytes.
    func uploadPhoto(file: URL, server: String, keypair: FullKeypair, lifetime: VoiceAccountLifetime) async throws -> String {
        let origin = try Self.origin(server)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20 * 1024 * 1024 else { throw VoiceFailure("The photo exceeds the upload limit.") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: size + 1) ?? Data()
        guard data.count == size, data.starts(with: [0xff, 0xd8, 0xff]) else { throw VoiceFailure("The prepared photo is invalid.") }
        let hash = VoiceAudioFiles.digest(data)
        let descriptor = try await uploadBytes(file: file, origin: origin, sha256: hash, size: size,
                                               mime: "image/jpeg", keypair: keypair, lifetime: lifetime)
        guard descriptor.sha256 == hash, descriptor.size == size,
              descriptor.type.map(VoiceMediaReference.normalizedMIME) == "image/jpeg",
              VoiceMediaReference.isHTTPSURL(descriptor.url) else {
            throw VoiceFailure("The upload receipt does not match the photo's bytes and image type.")
        }
        return descriptor.url
    }

    /// Bounded, nonredirecting BUD-02 upload with BUD-11 authorization for the exact file.
    private func uploadBytes(file: URL, origin: URL, sha256: String, size: Int, mime: String,
                             keypair: FullKeypair, lifetime: VoiceAccountLifetime) async throws -> Descriptor {
        if origin.host?.lowercased() == "blossom.band", size > 20 * 1024 * 1024 {
            throw VoiceFailure("This file exceeds nostr.build's free upload limit of 20 MiB.")
        }
        try Task.checkCancellation()
        guard lifetime.isActive else { throw CancellationError() }
        let now = UInt32(Date().timeIntervalSince1970)
        let tags = [
            ["t", "upload"],
            ["x", sha256],
            ["expiration", String(UInt64(now) + 300)],
            ["server", origin.host!.lowercased()]
        ]
        guard let auth = NostrEvent(content: "Upload media for this voice post", keypair: keypair.to_keypair(),
                                    kind: NostrKind.blossom_auth.rawValue, tags: tags, createdAt: now - 1) else {
            throw VoiceFailure("The upload authorization could not be signed.")
        }
        let authorization = Data(event_to_json(ev: auth).utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var request = URLRequest(url: origin.appendingPathComponent("upload"))
        request.httpMethod = "PUT"
        request.setValue("Nostr " + authorization, forHTTPHeaderField: "Authorization")
        request.setValue(sha256, forHTTPHeaderField: "X-SHA-256")
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        request.httpBody = try handle.read(upToCount: size + 1) ?? Data()
        guard request.httpBody?.count == size, VoiceAudioFiles.digest(request.httpBody!) == sha256 else {
            throw VoiceFailure("The file changed before upload. Please retry.")
        }
        try Task.checkCancellation()
        guard lifetime.isActive else { throw CancellationError() }
        let (data, response) = try await transport.send(request, limit: 64 * 1024, redirects: false)
        try Task.checkCancellation()
        guard lifetime.isActive else { throw CancellationError() }
        guard data.count <= 64 * 1024 else { throw VoiceFailure("The upload receipt exceeds the size limit.") }
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw VoiceFailure("The Blossom server rejected the upload (HTTP \(response.statusCode)). Keep the composer open to retry.")
        }
        return try JSONDecoder().decode(Descriptor.self, from: data)
    }
}
