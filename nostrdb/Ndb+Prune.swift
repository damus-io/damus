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

    /// Room for the default keep-policy plus one filter the caller appends
    /// (a `since` cutoff, say).
    ///
    /// `ndb_prune_default_filters` treats a capacity below
    /// `NDB_PRUNE_DEFAULT_FILTERS` as a failure rather than a truncated policy,
    /// and ignores any capacity beyond what it uses.
    static let defaultPruneFilterCapacity = Int(NDB_PRUNE_DEFAULT_FILTERS) + 1

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

    /// Builds nostrdb's default prune keep-policy: every kind-0 profile, plus
    /// every note authored by one of `pubkeys`.
    ///
    /// With no pubkeys this is just the profiles filter — nostrdb skips the
    /// authors filter entirely rather than emitting one with an empty `authors`
    /// field, which would match nothing.
    ///
    /// - Parameters:
    ///   - pubkeys: The authors whose notes are kept.
    ///   - capacity: How many slots to allocate. Defaults to
    ///     ``defaultPruneFilterCapacity``, which leaves one spare for a filter
    ///     the caller appends afterwards.
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

/// Errors from ``Ndb/prune(to:filters:)``.
enum NdbPruneError: Error, LocalizedError {
    case pruneFailed(path: String)

    var errorDescription: String? {
        switch self {
        case .pruneFailed(let path):
            return "Failed to prune the database into \(path)."
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
    func prune(to path: String, filters: NdbFilterArray) throws {
        // `filters` owns the allocation `filters.unsafePointer` points into, so
        // it has to outlive the call rather than just its last use.
        try withExtendedLifetime(filters, {
            try prune(to: path, filterStorage: filters.unsafePointer, count: filters.count)
        })
    }

    /// Writes a pruned copy of the database to `path`, keeping only the notes
    /// that match at least one of `filters`.
    ///
    /// See the `NdbFilterArray` overload for the details; this one exists for
    /// callers that already hold ``NdbFilter`` objects.
    func prune(to path: String, filters: [NdbFilter]) throws {
        // `NdbFilter.ndbFilter` copies the struct out, which gives us the
        // contiguous array C wants — but the copy is shallow, its `elem_buf`
        // still pointing into the originating NdbFilter's own allocation. So
        // every NdbFilter has to stay alive for the whole prune, not just until
        // its struct has been copied.
        try withExtendedLifetime(filters, {
            var filterStructs = filters.map(\.ndbFilter)
            return try filterStructs.withUnsafeMutableBufferPointer({ buffer in
                // A nil base address only happens when there are no filters, and
                // nostrdb never dereferences the array in that case.
                try prune(to: path, filterStorage: buffer.baseAddress, count: buffer.count)
            })
        })
    }

    private func prune(to path: String, filterStorage: UnsafeMutablePointer<ndb_filter>?, count: Int) throws {
        try withNdb({
            try path.withCString({ pathCString in
                guard ndb_prune(self.ndb.ndb, pathCString, filterStorage, Int32(count)) == 1 else {
                    throw NdbPruneError.pruneFailed(path: path)
                }
            })
        })
    }
}
