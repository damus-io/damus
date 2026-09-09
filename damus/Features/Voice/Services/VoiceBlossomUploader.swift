import Foundation

protocol VoiceUploading: Sendable {
    func upload(file: URL, server: String, keypair: FullKeypair, lifetime: VoiceAccountLifetime) async throws -> VoiceUploadReceipt
}

/// nostr.build Blossom uploads with BUD-02 and BUD-11 authorization.
actor VoiceBlossomUploader: VoiceUploading {
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

    /// Receipts must describe these exact bytes. Never replace an opaque URL with a hash-derived URL.
    static func validate(_ descriptor: Descriptor, server: String, sha256: String, size: Int, duration: TimeInterval) throws -> VoiceUploadReceipt {
        guard descriptor.sha256 == sha256, descriptor.size == size,
              descriptor.type.map(VoiceMediaReference.normalizedMIME) == "audio/mp4" else {
            throw VoiceFailure("The upload receipt does not match the recording's bytes and audio type.")
        }
        let reference = try VoiceMediaReference(url: descriptor.url, sha256: sha256, mimeType: "audio/mp4", duration: duration)
        return VoiceUploadReceipt(server: server, reference: reference, size: size)
    }

    func upload(file: URL, server: String, keypair: FullKeypair, lifetime: VoiceAccountLifetime) async throws -> VoiceUploadReceipt {
        let origin = try Self.origin(server)
        let audio = try await files.inspect(file)
        if origin.host?.lowercased() == "blossom.band", audio.size > 20 * 1024 * 1024 {
            throw VoiceFailure("The recording exceeds nostr.build's free upload limit of 20 MiB. Your recording is saved.")
        }
        try Task.checkCancellation()
        guard lifetime.isActive else { throw CancellationError() }
        let now = UInt32(Date().timeIntervalSince1970)
        let tags = [
            ["t", "upload"],
            ["x", audio.sha256],
            ["expiration", String(UInt64(now) + 300)],
            ["server", origin.host!.lowercased()]
        ]
        guard let auth = NostrEvent(content: "Upload this voice recording", keypair: keypair.to_keypair(),
                                    kind: NostrKind.blossom_auth.rawValue, tags: tags, createdAt: now - 1) else {
            throw VoiceFailure("The upload authorization could not be signed.")
        }
        let authorization = Data(event_to_json(ev: auth).utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var request = URLRequest(url: origin.appendingPathComponent("upload"))
        request.httpMethod = "PUT"
        request.setValue("Nostr " + authorization, forHTTPHeaderField: "Authorization")
        request.setValue(audio.sha256, forHTTPHeaderField: "X-SHA-256")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        request.httpBody = try handle.read(upToCount: audio.size + 1) ?? Data()
        // Bound the second read and reject changes since media verification.
        guard request.httpBody?.count == audio.size, VoiceAudioFiles.digest(request.httpBody!) == audio.sha256 else {
            throw VoiceFailure("The recording changed before upload. Please retry.")
        }
        try Task.checkCancellation()
        guard lifetime.isActive else { throw CancellationError() }
        let (data, response) = try await transport.send(request, limit: 64 * 1024, redirects: false)
        guard data.count <= 64 * 1024 else { throw VoiceFailure("The upload receipt exceeds the size limit. Your recording is saved.") }
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw VoiceFailure("The Blossom server rejected the upload (HTTP \(response.statusCode)). Your recording is saved.")
        }
        let descriptor = try JSONDecoder().decode(Descriptor.self, from: data)
        return try Self.validate(descriptor, server: origin.absoluteString, sha256: audio.sha256, size: audio.size, duration: audio.duration)
    }
}
