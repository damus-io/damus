//
//  TusUploadStore.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-09-05.
//
//  Durable storage for in-flight uploads. One JSON file per upload, written
//  atomically after every confirmed chunk, so an app kill costs at most the
//  chunk that was in flight.
//

import Foundation

enum TusUploadStoreError: Error {
    case invalidIdentifier(TusUploadID)
}

/// A directory of `TusUploadRecord`s.
///
/// Deliberately dumb — no caching, no in-memory index — because the whole point
/// is that what is on disk is the truth after a process death. It is safe to
/// touch from any thread.
final class TusUploadStore: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// The default location: `Application Support/tus-uploads`, readable after
    /// first unlock so background transfers keep working on a locked phone, and
    /// kept out of backups since the payloads are transient.
    static func defaultDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("tus-uploads", isDirectory: true)
    }

    init(directory: URL) throws {
        self.directory = directory
        try Self.createDirectory(at: directory)
    }

    private static func createDirectory(at directory: URL) throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var mutable = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    // MARK: - Record file naming

    /// Upload ids come from a server (Bunny video GUIDs), so they are not
    /// trusted to be safe path components. Base64url of the id is reversible,
    /// collision-free and cannot contain `/` or `..`.
    private func fileName(for id: TusUploadID) throws -> String {
        guard !id.isEmpty else { throw TusUploadStoreError.invalidIdentifier(id) }
        let encoded = Data(id.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return encoded + ".json"
    }

    private func fileURL(for id: TusUploadID) throws -> URL {
        directory.appendingPathComponent(try fileName(for: id), isDirectory: false)
    }

    // MARK: - CRUD

    func save(_ record: TusUploadRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        try Self.createDirectory(at: directory)
        var updated = record
        updated.updatedAt = Date()
        let data = try encoder.encode(updated)
        try data.write(to: try fileURL(for: record.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func load(id: TusUploadID) throws -> TusUploadRecord? {
        lock.lock()
        defer { lock.unlock() }
        let url = try fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try decoder.decode(TusUploadRecord.self, from: data)
    }

    /// Every readable record, newest first. Unreadable files (a truncated write
    /// from a kill mid-`write`, an old schema) are skipped rather than failing
    /// the whole load — one corrupt upload must not block the others.
    func loadAll() -> [TusUploadRecord] {
        lock.lock()
        defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> TusUploadRecord? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(TusUploadRecord.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func delete(id: TusUploadID) throws {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: try fileURL(for: id))
    }
}
