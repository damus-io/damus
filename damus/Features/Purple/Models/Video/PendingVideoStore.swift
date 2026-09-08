//
//  PendingVideoStore.swift
//  damus
//
//  Durable storage for authorized-but-unpublished videos. One atomic JSON file
//  per record, modelled directly on `TusUploadStore` because it is the same
//  problem with the same lifetime: what is on disk has to be the truth after
//  the process dies.
//

import Foundation

enum PendingVideoStoreError: Error {
    case invalidIdentifier(PurpleVideoID)
}

/// A directory of `PendingVideo`s.
///
/// Deliberately dumb — no caching, no in-memory index — for the same reason
/// `TusUploadStore` is. Safe to touch from any thread.
///
/// Every public method takes the lock exactly once and goes through the
/// private unlocked primitives. That is not incidental: `NSLock` is not
/// recursive, so a `mutate` built on the public `load` and `save` would
/// deadlock the first time it ran.
final class PendingVideoStore: @unchecked Sendable {
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

    /// The default location: `Application Support/pending-videos`, readable
    /// after first unlock so a background reconcile works on a locked phone,
    /// and kept out of backups since these records are transient and point at
    /// container paths that will not survive a restore anyway.
    static func defaultDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("pending-videos", isDirectory: true)
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

    /// Video ids come from a server, so they are not trusted to be safe path
    /// components. Base64url of the id is reversible, collision-free, and
    /// cannot contain `/` or `..`.
    private func fileName(for id: PurpleVideoID) throws -> String {
        guard !id.isEmpty else { throw PendingVideoStoreError.invalidIdentifier(id) }
        let encoded = Data(id.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return encoded + ".json"
    }

    private func fileURL(for id: PurpleVideoID) throws -> URL {
        directory.appendingPathComponent(try fileName(for: id), isDirectory: false)
    }

    // MARK: - Unlocked primitives
    //
    // The lock is taken by the public methods. Nothing in here may take it.

    private func readUnlocked(id: PurpleVideoID) throws -> PendingVideo? {
        guard let data = try? Data(contentsOf: try fileURL(for: id)) else { return nil }
        return try decoder.decode(PendingVideo.self, from: data)
    }

    private func writeUnlocked(_ record: PendingVideo) throws {
        try Self.createDirectory(at: directory)
        let data = try encoder.encode(record)
        try data.write(
            to: try fileURL(for: record.videoId),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    // MARK: - CRUD

    func save(_ record: PendingVideo) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeUnlocked(record)
    }

    func load(id: PurpleVideoID) throws -> PendingVideo? {
        lock.lock()
        defer { lock.unlock() }
        return try readUnlocked(id: id)
    }

    /// Every readable record, newest first.
    ///
    /// An unreadable file — a truncated write from a kill mid-`write`, or a
    /// record written by a schema this build does not know — is skipped rather
    /// than failing the whole load. One bad record must not hide the others.
    func loadAll() -> [PendingVideo] {
        lock.lock()
        defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> PendingVideo? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(PendingVideo.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func delete(id: PurpleVideoID) throws {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: try fileURL(for: id))
    }

    // MARK: - Reconciling

    /// Reads, changes and writes one record without letting go of the lock.
    ///
    /// **The only supported way to change a record.** A push and a foreground
    /// reconcile arriving at the same moment would otherwise read the same
    /// record, each apply their own update, and each write it back — with the
    /// second silently discarding the first. The closure must not call back
    /// into the store.
    ///
    /// - Returns: the record as written, or nil if there was none to change.
    @discardableResult
    func mutate(id: PurpleVideoID, _ body: (inout PendingVideo) -> Void) throws -> PendingVideo? {
        lock.lock()
        defer { lock.unlock() }
        guard var record = try readUnlocked(id: id) else { return nil }
        body(&record)
        try writeUnlocked(record)
        return record
    }

    /// Writes a record, merging it with whatever is already on disk.
    ///
    /// The merge rules exist because not every caller knows everything:
    ///
    /// - `asset`, `composerDraftID` and `createdAt` are **local** facts. A
    ///   "video ready" push knows the guid and nothing else, and must not be
    ///   able to blank the local file this record points at.
    /// - `state` takes whichever is further along the ladder, so an
    ///   out-of-order arrival cannot walk a video backwards.
    /// - `lastCheckedAt` takes the later of the two.
    ///
    /// - Returns: the record as written.
    @discardableResult
    func upsert(_ record: PendingVideo) throws -> PendingVideo {
        lock.lock()
        defer { lock.unlock() }

        guard let existing = try readUnlocked(id: record.videoId) else {
            try writeUnlocked(record)
            return record
        }

        // Built from what is on disk and overlaid with what the caller
        // learned, rather than the other way round, so the local-only fields
        // (`asset`, `createdAt`) are kept by construction rather than by being
        // remembered.
        var merged = existing
        merged.composerDraftID = existing.composerDraftID ?? record.composerDraftID
        merged.expiry = record.expiry
        merged.uploadDeadline = record.uploadDeadline
        if record.state.rank > existing.state.rank {
            merged.state = record.state
        }
        merged.lastCheckedAt = [existing.lastCheckedAt, record.lastCheckedAt].compactMap { $0 }.max()

        try writeUnlocked(merged)
        return merged
    }
}
