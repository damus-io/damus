//
//  Ndb+Prune.swift
//  damus
//
//  Swift bindings for nostrdb's `ndb_prune`, which copies out only the notes a
//  set of unioned filters matches. Unlike `ndb_snapshot`/`compact(to:)`, which
//  is a lossless LMDB page copy, this actually drops notes — so it is the only
//  operation that can shrink a database that keeps growing.
//

import Foundation

/// `unsigned char [32]`, as the Clang importer spells a fixed-size C array.
///
/// Swift tuple types are structural, so this is the very same type
/// `ndb_prune_default_filters` asks for in its `const unsigned char (*)[32]`
/// parameter — there is no way to write that name without spelling the tuple out.
private typealias NdbKey32 =
    (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

/// Errors from building an ``NdbFilterArray``.
enum NdbFilterArrayError: Error, LocalizedError {
    /// A filter was appended to an array with no free slot left.
    case full(capacity: Int)
    /// `nostrdb` refused to initialize the filter.
    case filterInitializationFailed
    /// The requested capacity is below what `ndb_prune_default_filters` needs.
    case capacityTooSmall(capacity: Int, minimum: Int)
    /// `ndb_prune_default_filters` failed. It leaves no filter initialized in
    /// this case, so there is nothing to clean up.
    case defaultPruneFiltersFailed
    /// A pubkey was not 32 bytes long, so it cannot be handed to nostrdb.
    case invalidPubkeyLength(bytes: Int)

    var errorDescription: String? {
        switch self {
        case .full(let capacity):
            return "The filter array is full (capacity \(capacity))."
        case .filterInitializationFailed:
            return "nostrdb failed to initialize the filter."
        case .capacityTooSmall(let capacity, let minimum):
            return "A filter array capacity of \(capacity) is too small; ndb_prune_default_filters needs at least \(minimum)."
        case .defaultPruneFiltersFailed:
            return "nostrdb failed to build the default prune filters."
        case .invalidPubkeyLength(let bytes):
            return "Expected a 32-byte pubkey, got \(bytes) bytes."
        }
    }
}

/// An owned, contiguous run of `ndb_filter` structs.
///
/// nostrdb's array-taking entry points — `ndb_prune`, `ndb_query`,
/// `ndb_subscribe` — want a C array of `struct ndb_filter`, not an array of
/// pointers to them, and ``NdbFilter`` allocates each of its filters
/// separately. This is the other shape: one allocation holding `capacity`
/// slots, of which the first ``count`` are initialized. `deinit` runs
/// `ndb_filter_destroy` on each of those, which is the caller's obligation
/// after `ndb_prune_default_filters` hands them over.
final class NdbFilterArray {
    private let storage: UnsafeMutablePointer<ndb_filter>

    /// How many filters this array has room for.
    let capacity: Int

    /// How many of the slots are initialized. Only these are handed to C, and
    /// only these are destroyed.
    private(set) var count: Int = 0

    /// Room for exactly the default keep-policy.
    ///
    /// `ndb_prune_default_filters` treats a capacity below
    /// `NDB_PRUNE_DEFAULT_FILTERS` as a failure rather than a truncated policy,
    /// and ignores any capacity beyond what it uses.
    static let defaultPruneFilterCapacity = Int(NDB_PRUNE_DEFAULT_FILTERS)

    /// Allocates room for `capacity` filters, none of them initialized yet.
    init(capacity: Int) {
        precondition(capacity > 0, "an NdbFilterArray needs at least one slot")
        self.capacity = capacity
        self.storage = UnsafeMutablePointer<ndb_filter>.allocate(capacity: capacity)
    }

    /// The filters, for handing to a C entry point that takes
    /// `struct ndb_filter *` plus a count.
    ///
    /// - Warning: Only valid while this object is alive. Keep a strong reference
    ///   for the whole duration of the C call.
    var unsafePointer: UnsafeMutablePointer<ndb_filter> {
        return storage
    }

    /// Initializes the next free slot in place.
    ///
    /// - Parameter initializer: Receives an uninitialized slot and must run the
    ///   whole `ndb_filter_init*` … `ndb_filter_end` sequence on it, returning
    ///   `true` once the filter is ready to use. Returning `false` leaves the
    ///   slot free and ``count`` unchanged, so `initializer` has to clean up
    ///   after its own partial work — the same contract nostrdb's own builders
    ///   follow.
    /// - Throws: ``NdbFilterArrayError`` if there is no free slot, or if
    ///   `initializer` reports failure.
    func appendFilter(_ initializer: (UnsafeMutablePointer<ndb_filter>) -> Bool) throws {
        guard count < capacity else {
            throw NdbFilterArrayError.full(capacity: capacity)
        }
        guard initializer(storage.advanced(by: count)) else {
            throw NdbFilterArrayError.filterInitializationFailed
        }
        count += 1
    }

    /// Builds a filter into the next free slot with ``NdbFilterBuilder``.
    ///
    /// The builder destroys a filter it could not finish, so a throw here leaves
    /// the slot free and ``count`` unchanged, exactly as the raw
    /// ``appendFilter(_:)`` does.
    ///
    /// - Throws: ``NdbFilterArrayError/full(capacity:)`` if there is no free slot,
    ///   or whatever ``NdbFilterBuilder/build(into:_:)`` throws.
    func appendFilter(building body: (NdbFilterBuilder) throws -> Void) throws {
        guard count < capacity else {
            throw NdbFilterArrayError.full(capacity: capacity)
        }
        try NdbFilterBuilder.build(into: storage.advanced(by: count), body)
        count += 1
    }

    /// Builds nostrdb's default prune keep-policy: every kind-0 profile, plus
    /// every note authored by one of `pubkeys`.
    ///
    /// This is the whole keep-policy a prune runs with. It carries no kind
    /// restriction on the author filter, so the things a user cannot get back
    /// from a relay on demand — their contact list, their mutelist, their
    /// bookmarks, their own posts — are kept by virtue of being theirs.
    /// Everything else is cache, and refills from relays.
    ///
    /// With no pubkeys this is just the profiles filter — nostrdb skips the
    /// authors filter entirely rather than emitting one with an empty `authors`
    /// field, which would match nothing.
    ///
    /// - Parameters:
    ///   - pubkeys: The authors whose notes are kept.
    ///   - capacity: How many slots to allocate. Defaults to
    ///     ``defaultPruneFilterCapacity``, which is exactly what the policy
    ///     needs.
    /// - Returns: An array owning the filters, which are destroyed when it is
    ///   released.
    /// - Throws: ``NdbFilterArrayError`` if `capacity` is too small, a pubkey is
    ///   not 32 bytes, or nostrdb fails to build the filters.
    static func defaultPruneFilters(keeping pubkeys: [Pubkey],
                                    capacity: Int = NdbFilterArray.defaultPruneFilterCapacity) throws -> NdbFilterArray {
        let minimum = Int(NDB_PRUNE_DEFAULT_FILTERS)
        guard capacity >= minimum else {
            throw NdbFilterArrayError.capacityTooSmall(capacity: capacity, minimum: minimum)
        }

        // `const unsigned char (*)[32]` is one flat run of bytes on the C side,
        // so flatten first and reinterpret the buffer as 32-byte keys below.
        var keyBytes = [UInt8]()
        keyBytes.reserveCapacity(pubkeys.count * 32)
        for pubkey in pubkeys {
            let bytes = pubkey.bytes
            guard bytes.count == 32 else {
                throw NdbFilterArrayError.invalidPubkeyLength(bytes: bytes.count)
            }
            keyBytes.append(contentsOf: bytes)
        }

        let filters = NdbFilterArray(capacity: capacity)
        var numFilters: Int32 = 0

        let result: Int32 = keyBytes.withUnsafeBufferPointer({ buffer in
            guard let base = buffer.baseAddress, !pubkeys.isEmpty else {
                return ndb_prune_default_filters(nil, 0, filters.storage, Int32(capacity), &numFilters)
            }
            return base.withMemoryRebound(to: NdbKey32.self, capacity: pubkeys.count, { keys in
                ndb_prune_default_filters(keys, Int32(pubkeys.count), filters.storage, Int32(capacity), &numFilters)
            })
        })

        guard result == 1 else {
            // On failure nostrdb leaves no filter initialized, so `count` stays
            // at zero and `deinit` destroys nothing.
            throw NdbFilterArrayError.defaultPruneFiltersFailed
        }

        filters.count = Int(numFilters)
        return filters
    }

    deinit {
        for index in 0..<count {
            ndb_filter_destroy(storage.advanced(by: index))
        }
        storage.deallocate()
    }
}

/// What `ndb_prune` reported about a run, whether or not it finished.
///
/// `ndb_prune` answers 0 or 1 and writes everything else to stderr, which is
/// gone by the time anyone reads a crash report — so a prune that failed in the
/// field used to be undiagnosable without reproducing it with a console
/// attached. This is the rest of what it knows: where it stopped if it did,
/// what LMDB said about that, how far the copy got, and the two mapsizes.
struct NdbPruneReport: Equatable {
    /// Where it stopped, e.g. `"dst_env_open"`, or `"ok"` if it did not.
    ///
    /// Taken from `ndb_prune_phase_name` rather than mirrored into Swift, so
    /// adding a phase in C cannot leave a stale name here.
    let phase: String

    /// The raw phase value, for grouping reports without depending on the
    /// spelling of ``phase``.
    let phaseCode: UInt32

    /// Whether the run finished.
    var succeeded: Bool { return phaseCode == NDB_PRUNE_OK.rawValue }

    /// The LMDB return code from the call that failed, or `0` where that call
    /// had none to give.
    let rc: Int32

    /// The mapsize `ndb_prune` asked of the destination environment, and the
    /// source's own.
    ///
    /// Worth carrying because neither is an input anything on our side
    /// chooses: `ndb_prune` derives the first from the source's own usage, so
    /// this is the only place either is visible. A destination map as large as
    /// the source's is how the second prune failed in the field — two 32 GiB
    /// reservations in one process is at the iOS address space ceiling — so
    /// these two numbers are the evidence that fix is holding.
    let destinationMapsizeBytes: UInt64
    let sourceMapsizeBytes: UInt64

    /// How far the copy got before it stopped.
    let profilesCopied: Int
    let notesCopied: Int

    init(_ err: ndb_prune_error) {
        self.phase = String(cString: ndb_prune_phase_name(err.phase))
        self.phaseCode = err.phase.rawValue
        self.rc = err.rc
        self.destinationMapsizeBytes = err.dst_mapsize
        self.sourceMapsizeBytes = err.src_mapsize
        self.profilesCopied = Int(err.profiles)
        self.notesCopied = Int(err.notes)
    }

    /// LMDB's own text for ``rc``, or `nil` where there is no code to explain.
    var rcDescription: String? {
        guard rc != 0, let text = mdb_strerror(rc) else { return nil }
        return String(cString: text)
    }

    /// One line naming the site and the code — what a developer needs to tell
    /// which `fprintf` in `ndb_prune` fired, without the log it went to.
    var summary: String {
        var line = succeeded ? "copied" : "failed at \(phase)"
        if let rcDescription {
            line += " (LMDB error \(rc): \(rcDescription))"
        }
        line += ", destination mapsize \(destinationMapsizeBytes) bytes"
        line += " of a source mapsize of \(sourceMapsizeBytes)"
        line += succeeded ? ", copying " : ", after copying "
        line += "\(profilesCopied) profiles and \(notesCopied) notes"
        return line
    }

    /// Flat and string-valued, for attaching to a crash report.
    ///
    /// Kept plain `String` on both sides because this type compiles into the
    /// extensions, where Sentry does not exist — the app target is what turns
    /// this into a scope context.
    var reportContext: [String: String] {
        var context = [
            "phase": phase,
            "phase_code": String(phaseCode),
            "rc": String(rc),
            "destination_mapsize_bytes": String(destinationMapsizeBytes),
            "source_mapsize_bytes": String(sourceMapsizeBytes),
            "profiles_copied": String(profilesCopied),
            "notes_copied": String(notesCopied),
        ]
        if let rcDescription {
            context["rc_description"] = rcDescription
        }
        return context
    }
}

/// Errors from ``Ndb/prune(to:filters:)``.
enum NdbPruneError: Error, LocalizedError {
    case pruneFailed(path: String, report: NdbPruneReport)

    var errorDescription: String? {
        switch self {
        case .pruneFailed(let path, let report):
            return "Failed to prune the database into \(path): \(report.summary)."
        }
    }

    /// The diagnostics to attach to a crash report, for whichever target can
    /// reach one.
    var reportContext: [String: String] {
        switch self {
        case .pruneFailed(let path, let report):
            return report.reportContext.merging(["path": path], uniquingKeysWith: { current, _ in current })
        }
    }
}

extension Ndb {
    /// Writes a pruned copy of the database to `path`, keeping only the notes
    /// that match at least one of `filters`.
    ///
    /// `ndb_prune` commits the destination, writes its database version and
    /// closes its environment itself, so on return `path` holds a complete,
    /// closed, standalone database. Nothing about the live database changes.
    ///
    /// - Note: Filters are unioned, exactly as in `ndb_query`. An **empty**
    ///   `filters` array therefore keeps every note — a plain copy, not an empty
    ///   database.
    ///
    /// - Note: Pruning rewrites every kept note through the writer, so note keys
    ///   in the output are freshly assigned and will not match the source, and
    ///   which relays a note was seen on is not carried over.
    ///
    /// - Important: This runs on the calling thread and can take a long time on
    ///   a large database, so call it off the main thread. It holds the
    ///   ``withNdb(_:maxWaitTimeout:)`` guard for its whole duration, which
    ///   keeps nostrdb from closing until it finishes.
    ///
    /// - Parameters:
    ///   - path: An **existing, empty** directory to write the pruned database
    ///     into. LMDB does not create it.
    ///   - filters: The keep-policy. Kept alive across the call.
    /// - Returns: What the prune did — the counts it copied and the mapsizes it
    ///   used. Discardable; the failure case is a throw, not a return value.
    @discardableResult
    func prune(to path: String, filters: NdbFilterArray) throws -> NdbPruneReport {
        // `filters` owns the allocation `filters.unsafePointer` points into, so
        // it has to outlive the call rather than just its last use.
        return try withExtendedLifetime(filters, {
            try prune(to: path, filterStorage: filters.unsafePointer, count: filters.count)
        })
    }

    /// Writes a pruned copy of the database to `path`, keeping only the notes
    /// that match at least one of `filters`.
    ///
    /// See the `NdbFilterArray` overload for the details; this one exists for
    /// callers that already hold ``NdbFilter`` objects.
    @discardableResult
    func prune(to path: String, filters: [NdbFilter]) throws -> NdbPruneReport {
        // `NdbFilter.ndbFilter` copies the struct out, which gives us the
        // contiguous array C wants — but the copy is shallow, its `elem_buf`
        // still pointing into the originating NdbFilter's own allocation. So
        // every NdbFilter has to stay alive for the whole prune, not just until
        // its struct has been copied.
        return try withExtendedLifetime(filters, {
            var filterStructs = filters.map(\.ndbFilter)
            return try filterStructs.withUnsafeMutableBufferPointer({ buffer in
                // A nil base address only happens when there are no filters, and
                // nostrdb never dereferences the array in that case.
                try prune(to: path, filterStorage: buffer.baseAddress, count: buffer.count)
            })
        })
    }

    private func prune(to path: String, filterStorage: UnsafeMutablePointer<ndb_filter>?, count: Int) throws -> NdbPruneReport {
        return try withNdb({
            try path.withCString({ pathCString in
                // `ndb_prune` fills this in either way, so the same report
                // covers the success path.
                var err = ndb_prune_error()
                let ok = ndb_prune(self.ndb.ndb, pathCString, filterStorage, Int32(count), &err) == 1
                let report = NdbPruneReport(err)
                guard ok else {
                    Log.error("ndb_prune failed: %@", for: .storage, report.summary)
                    throw NdbPruneError.pruneFailed(path: path, report: report)
                }
                Log.info("ndb_prune %@", for: .storage, report.summary)
                return report
            })
        })
    }
}

// MARK: - The space budget

/// How much space the user is willing to let nostrdb take up.
///
/// This is purely the trigger for a prune, not a size the prune aims at. A
/// database that crosses its budget is collapsed to what
/// ``NdbFilterArray/defaultPruneFilters(keeping:capacity:)`` keeps — profiles
/// and our own notes — and the timeline refills from relays from there. So the
/// result lands far *under* the budget rather than near it, which is why
/// nothing here computes a target.
///
/// - Important: The cases are ordered smallest-first, and both the settings
///   picker and ``Ndb/default_space_budget(forDatabaseSizeBytes:)`` rely on
///   that ordering.
enum NdbSpaceBudget: String, CaseIterable, Equatable {
    case small
    case medium
    case large
    /// No cap at all — the opt-out. The database is never pruned.
    case unlimited

    /// The budget in bytes, or `nil` for ``unlimited``, which has none.
    var bytes: UInt64? {
        switch self {
        case .small:     return 512 * 1024 * 1024
        case .medium:    return 2 * 1024 * 1024 * 1024
        case .large:     return 8 * 1024 * 1024 * 1024
        case .unlimited: return nil
        }
    }

    /// Human-readable label shown in the settings UI.
    func text_description() -> String {
        switch self {
        case .small:
            return NSLocalizedString("Small (512 MB)", comment: "Space budget option: keep the database under 512 megabytes")
        case .medium:
            return NSLocalizedString("Medium (2 GB)", comment: "Space budget option: keep the database under 2 gigabytes")
        case .large:
            return NSLocalizedString("Large (8 GB)", comment: "Space budget option: keep the database under 8 gigabytes")
        case .unlimited:
            return NSLocalizedString("Unlimited", comment: "Space budget option: never limit the size of the database")
        }
    }
}

extension Ndb {
    /// The `UserDefaults` key holding the space budget (stored as raw string).
    static let space_budget_key = "ndb_space_budget"

    /// The budget an install with a database of `size` bytes should start on:
    /// the tightest tier it already fits inside.
    ///
    /// Existing users are not all dropped into the smallest tier, because that
    /// would prune most of them on the first launch after updating — a setting
    /// they never chose silently deleting notes. Instead everyone starts where
    /// they already are and only pays for growth from here.
    ///
    /// A database larger than every tier therefore lands on ``NdbSpaceBudget/unlimited``.
    /// That is the deliberate cost of the rule: the biggest databases keep
    /// growing until their owner picks a tier.
    static func default_space_budget(forDatabaseSizeBytes size: UInt64) -> NdbSpaceBudget {
        // `allCases` is smallest-first, and `unlimited` compares as unbounded,
        // so the first tier that fits is both the tightest one and always found.
        return NdbSpaceBudget.allCases.first(where: { ($0.bytes ?? .max) >= size }) ?? .unlimited
    }

    /// Reads the persisted space budget, adopting a size-derived default the
    /// first time it is asked for.
    ///
    /// The derived default is **written back**, which is what makes it stable:
    /// re-deriving it on every read would let the tier drift upwards as the
    /// database grew, and it would never prune.
    ///
    /// - Parameter db_path: Override the database directory path. Pass `nil`
    ///   (default) to use ``Ndb/db_path``.
    static func get_space_budget(db_path: String? = nil) -> NdbSpaceBudget {
        if let raw = UserDefaults.standard.string(forKey: space_budget_key),
           let budget = NdbSpaceBudget(rawValue: raw) {
            return budget
        }

        // No database yet means a fresh install, which starts at the tightest tier.
        let size = (db_path ?? Self.db_path).flatMap({ database_file_size(path: $0) }) ?? 0
        let budget = default_space_budget(forDatabaseSizeBytes: size)
        Log.info("No space budget set yet; adopting %@ for a %d byte database", for: .storage, budget.rawValue, size)
        set_space_budget(budget)
        return budget
    }

    /// Persists the space budget to `UserDefaults`.
    static func set_space_budget(_ budget: NdbSpaceBudget) {
        UserDefaults.standard.set(budget.rawValue, forKey: space_budget_key)
    }
}

// MARK: - The staged prune marker

/// What a prune's keep-policy promised to carry over, read off the source
/// database while the prune ran.
///
/// The swap at the next launch needs something to check the staged copy
/// against, and "it is a valid LMDB database" is not it. `ndb_prune` is
/// **lossy**, unlike the lossless page copy this replaced, so a bad cutoff or a
/// bad filter produces a perfectly well-formed, nearly empty `data.mdb` that
/// would sail through a size check and take the user's notes with it. Only the
/// prune knows what it set out to keep, so it writes that down here.
///
/// Each field is something the keep-policy guarantees unconditionally — see
/// ``NdbFilterArray/defaultPruneFilters(keeping:capacity:)`` — so a staged copy
/// that fails one of them is broken by definition rather than merely
/// surprising.
struct NdbPrunePromise: Equatable {
    /// Whether the source held any kind-0 profile. The policy keeps every one of
    /// them however old, so profiles in the source and none in the staged copy
    /// can only mean the prune went wrong.
    let hasProfiles: Bool

    /// Which of the authors the policy keeps in full — ours — the source held a
    /// kind-1 text note from.
    ///
    /// Recorded rather than assumed, because a lurker who has never posted has
    /// none, and demanding their own notes survive would refuse every prune they
    /// ever stage and quietly stop enforcing their budget.
    ///
    /// Text notes specifically, not any note by them: their kind-0 profile is
    /// kept by the profiles filter regardless, so a copy that dropped every post
    /// they ever wrote would still answer an unrestricted author query. Their
    /// posts are also the thing a user would actually notice losing.
    let authorsWithPosts: [Pubkey]

    /// Reads the promises a prune of `source` keeping `keepAuthors` makes.
    ///
    /// Call with the source open and the prune about to run. These are indexed
    /// existence checks rather than scans, but they are still nostrdb work and
    /// belong on the prune's own queue.
    init(source: Ndb, keepAuthors: [Pubkey]) throws {
        self.hasProfiles = try source.containsNote(matching: NostrFilter(kinds: [.metadata]))
        // One query per author: nostrdb plans a single-author filter through the
        // author index and falls back to walking the whole database for several
        // at once.
        self.authorsWithPosts = try keepAuthors.filter({
            try source.containsNote(matching: NostrFilter(kinds: [.text], authors: [$0]))
        })
    }

    /// Memberwise, for the swap's validation tests and for reading a marker back.
    init(hasProfiles: Bool, authorsWithPosts: [Pubkey]) {
        self.hasProfiles = hasProfiles
        self.authorsWithPosts = authorsWithPosts
    }
}

/// A pruned copy of the database that finished successfully and is waiting for
/// the next launch to be swapped into place.
///
/// The prune runs while the app is live and never touches the database in use,
/// so the swap is a file move at the next launch, before nostrdb opens. Notes
/// ingested between the prune finishing and that swap are lost — accepted and
/// deliberate, see headway:damus-ios/spike-inspire-glide.
struct NdbPendingPrune: Equatable {
    /// The directory holding the pruned database. It contains a complete,
    /// closed, standalone `data.mdb`.
    let path: String

    /// When the prune finished. See ``Ndb/staged_prune_expiry`` for how stale a
    /// staged copy may get before the swap throws it away instead.
    let completedAt: Date

    /// What the prune's keep-policy promised, for the swap to check the staged
    /// copy against.
    let promise: NdbPrunePromise
}

extension Ndb {
    /// The directory a prune stages its output in, a sibling of `data.mdb`
    /// inside the database directory.
    ///
    /// Deliberately not the system temporary directory: a staged prune has to
    /// survive until the next launch, and iOS is free to empty `tmp` in between.
    static let staged_prune_directory_name = "ndb_prune_staged"

    /// The `UserDefaults` key holding the staged prune's directory.
    static let pending_prune_path_key = "ndb_pending_prune_path"

    /// The `UserDefaults` key holding when the staged prune finished.
    static let pending_prune_completed_at_key = "ndb_pending_prune_completed_at"

    /// The `UserDefaults` key holding whether the source had any profile.
    static let pending_prune_has_profiles_key = "ndb_pending_prune_has_profiles"

    /// The `UserDefaults` key holding the kept authors, as hex pubkeys.
    static let pending_prune_authors_key = "ndb_pending_prune_authors"

    /// The `UserDefaults` key holding the marker's format version.
    static let pending_prune_version_key = "ndb_pending_prune_version"

    /// Marker keys no version of this code writes any more.
    ///
    /// Kept only so ``clear_pending_prune()`` can sweep them off an install that
    /// updated with one still set.
    static let legacy_pending_prune_keys = [
        // Version 1's `NDB_FILTER_SINCE` cutoff, from the keep-policy that
        // computed one. Its absence is also what identifies a version 1 marker,
        // since that format had no version of its own.
        "ndb_pending_prune_since",
    ]

    /// The marker format this code writes, and the only one it will read.
    ///
    /// Version 1 markers carried a `since` cutoff and promised
    /// ``NdbStagedPruneRejection`` coverage that no longer exists: their staged
    /// copy was produced by a keep-policy this code cannot check, so honouring
    /// one would swap a database in on weaker terms than it was staged under.
    /// Bump this whenever what the promise means changes.
    static let pending_prune_marker_version = 2

    /// The staged prune waiting to be swapped in, if there is one.
    ///
    /// The marker is only written after `ndb_prune` reports success and the
    /// output has been checked, so its presence means the directory held a
    /// complete database at the time it was written. Whoever swaps it in should
    /// still confirm the file is there — the marker outlives a reinstall of the
    /// app's container, and iOS can delete files underneath us.
    ///
    /// A marker without the current version stamp is not a marker. That covers
    /// both a format we can no longer validate and a marker only half written
    /// before the process died — in either case the swap has no keep-policy it
    /// can check the copy against, and refusing to see it here is what keeps a
    /// swap from ever running unvalidated. The stamp is written last for exactly
    /// that reason.
    ///
    /// A pure read: whoever wants the residue cleaned up has to do it, because
    /// only they know which database's staging directory goes with it.
    static func get_pending_prune() -> NdbPendingPrune? {
        guard let path = UserDefaults.standard.string(forKey: pending_prune_path_key),
              let completedAt = UserDefaults.standard.object(forKey: pending_prune_completed_at_key) as? Date,
              let version = UserDefaults.standard.object(forKey: pending_prune_version_key) as? NSNumber,
              version.intValue == pending_prune_marker_version else {
            return nil
        }

        let authors = (UserDefaults.standard.stringArray(forKey: pending_prune_authors_key) ?? [])
            .compactMap({ Pubkey(hex: $0) })
        let promise = NdbPrunePromise(hasProfiles: UserDefaults.standard.bool(forKey: pending_prune_has_profiles_key),
                                      authorsWithPosts: authors)

        return NdbPendingPrune(path: path, completedAt: completedAt, promise: promise)
    }

    /// Whether anything marker-shaped is recorded, readable or not.
    ///
    /// The swap uses this to tell "nothing was ever staged" from "a marker is
    /// there that ``get_pending_prune()`` refuses to read", which leaves a
    /// staging directory to clear.
    static func has_pending_prune_residue() -> Bool {
        return UserDefaults.standard.string(forKey: pending_prune_path_key) != nil
    }

    /// Records a staged prune for the next launch to pick up.
    static func set_pending_prune(_ pending: NdbPendingPrune) {
        UserDefaults.standard.set(pending.path, forKey: pending_prune_path_key)
        UserDefaults.standard.set(pending.completedAt, forKey: pending_prune_completed_at_key)
        UserDefaults.standard.set(pending.promise.hasProfiles, forKey: pending_prune_has_profiles_key)
        UserDefaults.standard.set(pending.promise.authorsWithPosts.map({ $0.hex() }), forKey: pending_prune_authors_key)
        // Last, so a marker interrupted halfway through is unreadable rather
        // than readable and wrong.
        UserDefaults.standard.set(NSNumber(value: pending_prune_marker_version), forKey: pending_prune_version_key)
    }

    /// Forgets any staged prune. Does not delete the directory it named.
    static func clear_pending_prune() {
        // The version stamp first: the marker stops being readable the moment it
        // goes, so an interrupted clear leaves nothing a swap would act on.
        for key in [pending_prune_version_key,
                    pending_prune_path_key,
                    pending_prune_completed_at_key,
                    pending_prune_has_profiles_key,
                    pending_prune_authors_key] + legacy_pending_prune_keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Whether any note in the database matches `filter`.
    ///
    /// Asks for a single result, so for any filter nostrdb can plan this costs
    /// an index seek rather than a scan.
    func containsNote(matching filter: NostrFilter) throws -> Bool {
        return try !query(filters: [NdbFilter(from: filter)], maxResults: 1).isEmpty
    }
}
