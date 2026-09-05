//
//  TusUploadClient.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-09-05.
//
//  A resumable tus 1.0.0 upload client built on a background URLSession.
//
//  Why hand-rolled rather than TUSKit: the protocol we actually need is a HEAD
//  for the offset plus a sequence of PATCHes, which is the bulk of this file.
//  What we need *around* it — a background session so an 850 MB upload survives
//  the app being backgrounded, an offset that survives the app being killed, and
//  caller-supplied authorization headers that arrive from the Purple API and
//  expire — is exactly the part a general-purpose library owns and would have to
//  be prised back open. See the notes on headway:damus-ios/rabbit-tooth-post.
//
//  Shape of the thing:
//
//    enqueue()  -> a TusUploadRecord on disk
//    start()    -> [create] -> HEAD for the true offset -> PATCH, PATCH, PATCH...
//
//  Each PATCH sends one chunk from a temp file (a background session can only
//  upload from a file, and slicing a suffix of an 850 MB asset to disk is not
//  an option). Every chunk that lands is persisted before the next one starts,
//  so a kill costs at most one chunk — and even that is recovered by the HEAD,
//  which is always the authority on where to resume.
//

import Foundation

@MainActor
protocol TusUploadClientDelegate: AnyObject {
    func tusUploadClient(_ client: TusUploadClient, didUpdate state: TusUploadState)
    func tusUploadClient(_ client: TusUploadClient, didFinish id: TusUploadID, uploadURL: URL)
    func tusUploadClient(_ client: TusUploadClient, didFail id: TusUploadID, error: TusUploadError)
}

extension TusUploadClientDelegate {
    func tusUploadClient(_ client: TusUploadClient, didUpdate state: TusUploadState) { }
    func tusUploadClient(_ client: TusUploadClient, didFinish id: TusUploadID, uploadURL: URL) { }
    func tusUploadClient(_ client: TusUploadClient, didFail id: TusUploadID, error: TusUploadError) { }
}

/// The observable slice of an upload, for progress UI.
struct TusUploadState: Equatable, Sendable {
    let id: TusUploadID
    var phase: TusUploadPhase
    /// Bytes the server has acknowledged.
    var confirmedBytes: Int64
    /// `confirmedBytes` plus whatever the in-flight chunk has pushed. Regresses
    /// to `confirmedBytes` when a chunk has to be retried, which is honest.
    var sentBytes: Int64
    var totalBytes: Int64
    var lastError: String?

    var fractionComplete: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(sentBytes) / Double(totalBytes))
    }
}

/// Where the bytes are going.
enum TusDestination: Equatable, Sendable {
    /// The tus resource already exists. This is the Purple/Bunny case: the
    /// authorization endpoint creates the video object and hands us its URL.
    case uploadURL(URL)
    /// We create it ourselves with a `POST`. Used against a bare tus server.
    case create(endpoint: URL)
}

@MainActor
final class TusUploadClient: NSObject, ObservableObject {
    /// How the transfer session is configured.
    enum SessionMode: Equatable, Sendable {
        /// Transfers continue while the app is backgrounded or killed. Only one
        /// `URLSession` may exist per identifier per process, so the identifier
        /// has to be unique.
        case background(identifier: String)
        /// A plain in-process session. For unit tests, where a background
        /// session's out-of-process delivery makes assertions racy.
        case foreground
    }

    struct Configuration: Sendable {
        var sessionMode: SessionMode = .background(identifier: TusUploadClient.defaultSessionIdentifier)
        /// Bytes per PATCH. Bounds both the temp-file footprint and how much
        /// work a kill can cost.
        var chunkSize: Int = 8 * 1024 * 1024
        var backoff: TusBackoff = TusBackoff()
        var maxAttempts: Int = 8
        /// Ceiling on how long a single chunk may take before the OS gives up.
        var requestTimeout: TimeInterval = 90
        /// Ceiling on the whole upload, across retries and reconnects.
        var resourceTimeout: TimeInterval = 7 * 24 * 60 * 60
        var allowsCellularAccess: Bool = true
        /// Minimum interval between published progress updates.
        var progressThrottle: TimeInterval = 0.1
    }

    nonisolated static let defaultSessionIdentifier = "io.damus.tus.upload"

    /// Live state per upload, for SwiftUI. Mirrors what is on disk.
    @Published private(set) var uploads: [TusUploadID: TusUploadState] = [:]

    weak var delegate: TusUploadClientDelegate?

    let store: TusUploadStore
    let config: Configuration

    /// A chunk currently being PATCHed.
    private struct InFlight {
        let task: URLSessionTask
        let chunkURL: URL
        let offset: Int64
        let length: Int
    }

    private var inFlight: [TusUploadID: InFlight] = [:]
    private var retryTimers: [TusUploadID: Task<Void, Never>] = [:]
    private var steps: [TusUploadID: Task<Void, Never>] = [:]
    /// Uploads whose offset we must re-`HEAD` before sending anything. Set on a
    /// fresh start, a relaunch, and after any error.
    private var needsResync: Set<TusUploadID> = []
    private var lastProgressPublish: [TusUploadID: Date] = [:]
    private var backgroundEventsCompletion: (() -> Void)?

    /// Where chunk temp files live. Alongside the records, so the same
    /// protection class and backup exclusion apply and a relaunch can find them.
    private var chunkDirectory: URL { store.directory.appendingPathComponent("chunks", isDirectory: true) }

    private lazy var transferSession: URLSession = {
        let configuration: URLSessionConfiguration
        switch config.sessionMode {
        case .background(let identifier):
            configuration = URLSessionConfiguration.background(withIdentifier: identifier)
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = true
        case .foreground:
            configuration = URLSessionConfiguration.default
        }
        configuration.timeoutIntervalForRequest = config.requestTimeout
        configuration.timeoutIntervalForResource = config.resourceTimeout
        configuration.allowsCellularAccess = config.allowsCellularAccess
        // Chunks are strictly ordered; parallelism here would only create
        // offset conflicts.
        configuration.httpMaximumConnectionsPerHost = 1
        // Delivering on the main queue keeps delegate callbacks ordered and lets
        // the state machine stay on the MainActor. The only expensive work —
        // slicing chunks off the source file — is pushed off it explicitly.
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    /// Small control-plane requests (create, HEAD, terminate). Kept off the
    /// background session because those only support upload and download tasks,
    /// and because a control request is worthless if it outlives the app.
    private lazy var controlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = config.requestTimeout
        configuration.allowsCellularAccess = config.allowsCellularAccess
        return URLSession(configuration: configuration)
    }()

    init(store: TusUploadStore, config: Configuration = Configuration()) {
        self.store = store
        self.config = config
        super.init()
        try? FileManager.default.createDirectory(at: chunkDirectory, withIntermediateDirectories: true)
        for record in store.loadAll() {
            uploads[record.id] = Self.state(for: record, sentBytes: record.confirmedOffset)
        }
    }

    // MARK: - Public API

    /// Record an upload. Does not start it.
    ///
    /// - Parameters:
    ///   - id: caller-assigned; for Purple video, the Bunny video GUID.
    ///   - headers: authorization and any other headers to attach to every
    ///     request. Persisted, and replaceable later with `updateHeaders`.
    @discardableResult
    func enqueue(
        id: TusUploadID,
        sourceURL: URL,
        destination: TusDestination,
        headers: [String: String] = [:],
        metadata: [String: String] = [:],
        chunkSize: Int? = nil
    ) throws -> TusUploadRecord {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw TusUploadError.sourceFileMissing(sourceURL)
        }
        let totalBytes: Int64
        do {
            let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
            totalBytes = Int64(values.fileSize ?? 0)
        } catch {
            throw TusUploadError.sourceFileUnreadable(sourceURL, underlying: error.localizedDescription)
        }

        var record = TusUploadRecord(
            id: id,
            source: sourceURL,
            totalBytes: totalBytes,
            headers: headers,
            metadata: metadata,
            chunkSize: chunkSize ?? config.chunkSize
        )
        switch destination {
        case .uploadURL(let url):
            record.uploadURL = url
        case .create(let endpoint):
            record.creationEndpoint = endpoint
        }
        try store.save(record)
        publish(record, sentBytes: 0)
        return record
    }

    /// Begin (or continue) moving bytes.
    func start(id: TusUploadID) {
        guard var record = loadRecord(id) else { return }
        guard record.phase != .completed else { return }
        record.phase = .uploading
        record.attempt = 0
        record.lastErrorDescription = nil
        try? store.save(record)
        // A fresh start never trusts the persisted offset.
        needsResync.insert(id)
        publish(record, sentBytes: record.confirmedOffset)
        advance(id: id)
    }

    /// Stop without discarding progress. The upload can be `start`ed again.
    func pause(id: TusUploadID) {
        cancelWork(id: id)
        guard var record = loadRecord(id) else { return }
        guard record.phase == .uploading else { return }
        record.phase = .paused
        record.pendingChunk = nil
        try? store.save(record)
        publish(record, sentBytes: record.confirmedOffset)
    }

    /// Abandon the upload and forget it.
    ///
    /// - Parameter terminateOnServer: also `DELETE` the tus resource, so a
    ///   half-written object is not left behind. Best effort.
    func cancel(id: TusUploadID, terminateOnServer: Bool = true) {
        cancelWork(id: id)
        let record = loadRecord(id)
        if terminateOnServer, let record, let uploadURL = record.uploadURL {
            let request = TusRequest.termination(uploadURL: uploadURL, headers: record.headers)
            let session = controlSession
            Task.detached { _ = try? await session.data(for: request) }
        }
        try? store.delete(id: id)
        uploads[id] = nil
        lastProgressPublish[id] = nil
        if let record { removeChunkFile(for: record) }
    }

    /// Swap in freshly minted authorization headers.
    ///
    /// Bunny's upload signature expires, so an upload that has been sitting
    /// paused overnight needs Phase 7 to re-authorize before it can resume.
    func updateHeaders(for id: TusUploadID, headers: [String: String]) {
        guard var record = loadRecord(id) else { return }
        record.headers = headers
        try? store.save(record)
    }

    /// Reattach to whatever was happening before the app died, then restart
    /// anything that should be running and is not.
    ///
    /// Call this once at launch. This is the entry point that makes resume
    /// across an app kill work.
    func resumeAll() async {
        let liveTasks = await transferSession.allTasks
        var adopted: [TusUploadID: URLSessionTask] = [:]
        for task in liveTasks {
            guard let id = task.taskDescription else {
                task.cancel()
                continue
            }
            adopted[id] = task
        }

        let records = store.loadAll()
        var referencedChunks: Set<String> = []

        for record in records {
            if let task = adopted[record.id], let pending = record.pendingChunk {
                // Still in flight out of process. Pick the delegate callbacks
                // back up rather than starting a duplicate PATCH.
                inFlight[record.id] = InFlight(
                    task: task,
                    chunkURL: chunkDirectory.appendingPathComponent(pending.fileName),
                    offset: pending.offset,
                    length: pending.length
                )
                referencedChunks.insert(pending.fileName)
                publish(record, sentBytes: record.confirmedOffset)
                continue
            }

            // A task we cannot match to a record is not resumable; drop it.
            adopted[record.id]?.cancel()

            if record.phase == .uploading {
                needsResync.insert(record.id)
                advance(id: record.id)
            } else {
                publish(record, sentBytes: record.confirmedOffset)
            }
        }

        let knownIDs = Set(records.map { $0.id })
        for (id, task) in adopted where !knownIDs.contains(id) {
            task.cancel()
        }
        reapOrphanChunks(keeping: referencedChunks)
    }

    /// Hook for `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    ///
    /// Phase 9 wires this from `AppDelegate`; until it does, transfers still
    /// complete, iOS just is not told when we are done processing them.
    func setBackgroundEventsCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundEventsCompletion = handler
    }

    func state(for id: TusUploadID) -> TusUploadState? { uploads[id] }

    /// `TusUploadStore.load` throws on a decode failure; inside the state
    /// machine an unreadable record is indistinguishable from an absent one.
    private func loadRecord(_ id: TusUploadID) -> TusUploadRecord? {
        (try? store.load(id: id)) ?? nil
    }

    // MARK: - State machine

    private func advance(id: TusUploadID) {
        guard inFlight[id] == nil, steps[id] == nil else { return }
        steps[id] = Task { [weak self] in
            await self?.step(id: id)
            self?.steps[id] = nil
        }
    }

    private func step(id: TusUploadID) async {
        guard var record = loadRecord(id), record.phase == .uploading else { return }

        // 1. Make sure a tus resource exists.
        if record.uploadURL == nil {
            guard let endpoint = record.creationEndpoint else {
                fail(id: id, error: .missingLocationHeader)
                return
            }
            do {
                let uploadURL = try await create(endpoint: endpoint, record: record)
                record.uploadURL = uploadURL
                record.creationEndpoint = nil
                try? store.save(record)
            } catch let error as TusUploadError {
                handle(error: error, id: id)
                return
            } catch {
                handle(error: .transport(error.localizedDescription), id: id)
                return
            }
        }

        guard let uploadURL = record.uploadURL else {
            fail(id: id, error: .missingLocationHeader)
            return
        }

        // 2. Ask the server where we actually are. Our persisted offset is only
        //    a hint — the process can die between a chunk landing and us
        //    recording it, and the server is the one that knows.
        if needsResync.contains(id) {
            do {
                let serverOffset = try await fetchOffset(uploadURL: uploadURL, headers: record.headers)
                guard serverOffset <= record.totalBytes else {
                    fail(id: id, error: .offsetBeyondFile(serverOffset: serverOffset, totalBytes: record.totalBytes))
                    return
                }
                record.confirmedOffset = serverOffset
                try? store.save(record)
                needsResync.remove(id)
                publish(record, sentBytes: record.confirmedOffset)
            } catch let error as TusUploadError {
                handle(error: error, id: id)
                return
            } catch {
                handle(error: .transport(error.localizedDescription), id: id)
                return
            }
        }

        // 3. Done?
        guard let chunk = record.nextChunkRange() else {
            complete(record: record, uploadURL: uploadURL)
            return
        }

        // 4. Slice the next chunk to a temp file and hand it to the session.
        //    A background session can only upload from a file, and copying an
        //    850 MB suffix is not an option, so we pay one chunk of disk.
        let source = record.source.url
        guard record.source.exists else {
            fail(id: id, error: .sourceFileMissing(source))
            return
        }
        let fileName = "\(UUID().uuidString).chunk"
        let chunkURL = chunkDirectory.appendingPathComponent(fileName)
        do {
            let directory = chunkDirectory
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try TusUploadClient.writeChunk(from: source, offset: chunk.offset, length: chunk.length, to: chunkURL)
            }.value
        } catch let error as TusUploadError {
            fail(id: id, error: error)
            return
        } catch {
            fail(id: id, error: .sourceFileUnreadable(source, underlying: error.localizedDescription))
            return
        }

        // Re-read: a pause or cancel may have landed while we were slicing.
        guard let current = loadRecord(id), current.phase == .uploading else {
            try? FileManager.default.removeItem(at: chunkURL)
            return
        }
        record = current

        let request = TusRequest.patch(
            uploadURL: uploadURL,
            offset: chunk.offset,
            contentLength: chunk.length,
            headers: record.headers
        )
        let task = transferSession.uploadTask(with: request, fromFile: chunkURL)
        // The only handle we get back after a relaunch is this string.
        task.taskDescription = id
        record.pendingChunk = TusPendingChunk(offset: chunk.offset, length: chunk.length, fileName: fileName)
        try? store.save(record)
        inFlight[id] = InFlight(task: task, chunkURL: chunkURL, offset: chunk.offset, length: chunk.length)
        task.resume()
    }

    private func complete(record: TusUploadRecord, uploadURL: URL) {
        var record = record
        record.phase = .completed
        record.pendingChunk = nil
        record.attempt = 0
        record.lastErrorDescription = nil
        try? store.save(record)
        publish(record, sentBytes: record.totalBytes)
        delegate?.tusUploadClient(self, didFinish: record.id, uploadURL: uploadURL)
    }

    /// Route a failure into either a retry, a resync, or a hard stop.
    private func handle(error: TusUploadError, id: TusUploadID) {
        switch error {
        case .cancelled:
            return
        case .unauthorized, .uploadGone, .sourceFileMissing, .sourceFileUnreadable,
             .sourceFileTruncated, .offsetBeyondFile, .missingLocationHeader:
            fail(id: id, error: error)
        case .server(let status), .creationFailed(let status):
            switch TusRetryPolicy.forStatus(status) {
            case .fatal: fail(id: id, error: error)
            case .resync: needsResync.insert(id); scheduleRetry(id: id, error: error)
            case .retry: scheduleRetry(id: id, error: error)
            }
        case .missingOffsetHeader, .transport, .retryLimitExceeded:
            // Transport errors are the airplane-mode case: always worth another
            // go, and the backoff keeps us from spinning.
            needsResync.insert(id)
            scheduleRetry(id: id, error: error)
        }
    }

    private func scheduleRetry(id: TusUploadID, error: TusUploadError) {
        guard var record = loadRecord(id), record.phase == .uploading else { return }
        record.attempt += 1
        record.lastErrorDescription = error.localizedDescription
        guard record.attempt <= config.maxAttempts else {
            try? store.save(record)
            fail(id: id, error: .retryLimitExceeded(attempts: record.attempt - 1, lastError: error.localizedDescription))
            return
        }
        try? store.save(record)
        publish(record, sentBytes: record.confirmedOffset)

        let delay = config.backoff.delay(forAttempt: record.attempt, randomness: Double.random(in: 0...1))
        retryTimers[id]?.cancel()
        retryTimers[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.retryTimers[id] = nil
            self.advance(id: id)
        }
    }

    private func fail(id: TusUploadID, error: TusUploadError) {
        cancelWork(id: id)
        guard var record = loadRecord(id) else { return }
        record.phase = .failed
        record.pendingChunk = nil
        record.lastErrorDescription = error.localizedDescription
        try? store.save(record)
        publish(record, sentBytes: record.confirmedOffset)
        delegate?.tusUploadClient(self, didFail: id, error: error)
    }

    /// Tear down anything in flight for `id` without touching its record.
    private func cancelWork(id: TusUploadID) {
        retryTimers[id]?.cancel()
        retryTimers[id] = nil
        steps[id]?.cancel()
        steps[id] = nil
        if let flight = inFlight.removeValue(forKey: id) {
            flight.task.cancel()
            try? FileManager.default.removeItem(at: flight.chunkURL)
        }
        needsResync.insert(id)
    }

    // MARK: - Control-plane requests

    private func create(endpoint: URL, record: TusUploadRecord) async throws -> URL {
        let request = TusRequest.creation(
            endpoint: endpoint,
            length: record.totalBytes,
            metadata: record.metadata,
            headers: record.headers
        )
        let (_, response) = try await controlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TusUploadError.creationFailed(status: -1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw Self.mapStatus(http.statusCode)
        }
        guard let location = TusResponse.location(from: http, relativeTo: endpoint) else {
            throw TusUploadError.missingLocationHeader
        }
        return location
    }

    private func fetchOffset(uploadURL: URL, headers: [String: String]) async throws -> Int64 {
        let request = TusRequest.head(uploadURL: uploadURL, headers: headers)
        let (_, response) = try await controlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TusUploadError.transport("No HTTP response to HEAD.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw Self.mapStatus(http.statusCode)
        }
        guard let offset = TusResponse.offset(from: http) else {
            throw TusUploadError.missingOffsetHeader
        }
        return offset
    }

    nonisolated static func mapStatus(_ status: Int) -> TusUploadError {
        switch status {
        case 401, 403: return .unauthorized(status: status)
        case 404, 410: return .uploadGone(status: status)
        default: return .server(status: status)
        }
    }

    // MARK: - Chunk files

    /// Copy `length` bytes starting at `offset` out of `source`.
    ///
    /// `nonisolated static` so it can run off the MainActor — this is the only
    /// genuinely expensive thing the client does.
    nonisolated static func writeChunk(from source: URL, offset: Int64, length: Int, to destination: URL) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: source)
        } catch {
            throw TusUploadError.sourceFileUnreadable(source, underlying: error.localizedDescription)
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: length) ?? Data()
            guard data.count == length else {
                throw TusUploadError.sourceFileTruncated(expected: length, got: data.count)
            }
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch let error as TusUploadError {
            throw error
        } catch {
            throw TusUploadError.sourceFileUnreadable(source, underlying: error.localizedDescription)
        }
    }

    private func removeChunkFile(for record: TusUploadRecord) {
        guard let pending = record.pendingChunk else { return }
        try? FileManager.default.removeItem(at: chunkDirectory.appendingPathComponent(pending.fileName))
    }

    /// Delete chunk files no record refers to — leftovers from a kill.
    private func reapOrphanChunks(keeping keep: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: chunkDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Publishing

    private static func state(for record: TusUploadRecord, sentBytes: Int64) -> TusUploadState {
        TusUploadState(
            id: record.id,
            phase: record.phase,
            confirmedBytes: record.confirmedOffset,
            sentBytes: max(sentBytes, record.confirmedOffset),
            totalBytes: record.totalBytes,
            lastError: record.lastErrorDescription
        )
    }

    private func publish(_ record: TusUploadRecord, sentBytes: Int64) {
        let state = Self.state(for: record, sentBytes: sentBytes)
        guard uploads[record.id] != state else { return }
        uploads[record.id] = state
        lastProgressPublish[record.id] = Date()
        delegate?.tusUploadClient(self, didUpdate: state)
    }

    /// Progress ticks arrive per socket write, which is far more often than any
    /// UI needs, so they are throttled. Terminal updates go through `publish`.
    private func publishProgress(id: TusUploadID, sentBytes: Int64) {
        guard var state = uploads[id] else { return }
        let now = Date()
        if let last = lastProgressPublish[id], now.timeIntervalSince(last) < config.progressThrottle {
            return
        }
        state.sentBytes = max(state.confirmedBytes, sentBytes)
        guard uploads[id] != state else { return }
        uploads[id] = state
        lastProgressPublish[id] = now
        delegate?.tusUploadClient(self, didUpdate: state)
    }
}

// MARK: - URLSession delegate

extension TusUploadClient: URLSessionDataDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        MainActor.assumeIsolated {
            guard let id = task.taskDescription, let flight = self.inFlight[id], flight.task === task else { return }
            self.publishProgress(id: id, sentBytes: flight.offset + totalBytesSent)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            self.handleCompletion(task: task, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            let handler = self.backgroundEventsCompletion
            self.backgroundEventsCompletion = nil
            handler?()
        }
    }

    private func handleCompletion(task: URLSessionTask, error: Error?) {
        guard let id = task.taskDescription else { return }
        guard let flight = inFlight[id], flight.task === task else { return }
        inFlight[id] = nil
        try? FileManager.default.removeItem(at: flight.chunkURL)

        guard var record = loadRecord(id) else { return }
        record.pendingChunk = nil

        if let error {
            let nsError = error as NSError
            try? store.save(record)
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                // We cancelled it: pause, cancel, or a fail already in progress.
                return
            }
            handle(error: .transport(error.localizedDescription), id: id)
            return
        }

        guard let http = task.response as? HTTPURLResponse else {
            try? store.save(record)
            handle(error: .transport("The server did not answer the upload."), id: id)
            return
        }

        guard (200...299).contains(http.statusCode) else {
            try? store.save(record)
            handle(error: Self.mapStatus(http.statusCode), id: id)
            return
        }

        // A conforming server echoes the new offset. If it does not, assume the
        // whole chunk landed but re-`HEAD` before the next one rather than
        // building on a guess.
        if let serverOffset = TusResponse.offset(from: http) {
            record.confirmedOffset = serverOffset
        } else {
            record.confirmedOffset = flight.offset + Int64(flight.length)
            needsResync.insert(id)
        }
        record.attempt = 0
        record.lastErrorDescription = nil
        // Persisted before the next chunk starts: this write is what bounds the
        // cost of an app kill to one chunk.
        try? store.save(record)
        publish(record, sentBytes: record.confirmedOffset)

        guard let uploadURL = record.uploadURL else { return }
        if record.isFinished {
            complete(record: record, uploadURL: uploadURL)
        } else {
            advance(id: id)
        }
    }
}
