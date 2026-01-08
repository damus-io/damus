//
//  NdbNegentropy.swift
//  damus
//
//  Created by Claude on 2025-01-17.
//

import Foundation

/// Errors that can occur when working with NdbNegentropy.
enum NdbNegentropyError: Error {
    case storageInitFailed
    case storageSealFailed
    case storageAlreadySealed
    case storageFromFilterFailed
    case reconciliationInitFailed
    case initiateFailed
    case reconcileFailed
    case bufferTooSmall
}

/// Swift wrapper for negentropy storage (ndb_negentropy_storage).
/// Holds a sorted list of (timestamp, id) pairs for reconciliation.
final class NdbNegentropyStorage {
    private var storage: ndb_negentropy_storage
    private var isDestroyed = false

    /// Initialize empty storage.
    init() throws {
        storage = ndb_negentropy_storage()
        guard ndb_negentropy_storage_init(&storage) == 1 else {
            throw NdbNegentropyError.storageInitFailed
        }
    }

    /// Populate storage from a NostrDB filter query.
    /// The storage will be automatically sealed after this call.
    ///
    /// - Parameters:
    ///   - txn: Active read transaction (RawNdbTxnAccessible)
    ///   - filter: NdbFilter to query events
    ///   - limit: Maximum number of events (0 uses filter's limit or 10000)
    /// - Returns: Number of items added
    @discardableResult
    func populate(txn: any RawNdbTxnAccessible, filter: NdbFilter, limit: Int32 = 0) throws -> Int {
        var txnCopy = txn.txn
        let count = ndb_negentropy_storage_from_filter(
            &storage,
            &txnCopy,
            filter.unsafePointer,
            limit
        )
        guard count >= 0 else {
            throw NdbNegentropyError.storageFromFilterFailed
        }
        return Int(count)
    }

    /// Add an item to storage manually.
    /// Items can be added in any order - they will be sorted when sealed.
    ///
    /// - Parameters:
    ///   - timestamp: Event created_at timestamp
    ///   - id: 32-byte event ID
    func add(timestamp: UInt64, id: Data) throws {
        guard id.count == 32 else { return }
        let result = id.withUnsafeBytes { idPtr -> Int32 in
            guard let baseAddress = idPtr.baseAddress else { return 0 }
            return ndb_negentropy_storage_add(
                &storage,
                timestamp,
                baseAddress.assumingMemoryBound(to: UInt8.self)
            )
        }
        guard result == 1 else {
            throw NdbNegentropyError.storageAlreadySealed
        }
    }

    /// Add an item using NoteId.
    func add(timestamp: UInt64, noteId: NoteId) throws {
        try noteId.withUnsafePointer { idPtr in
            guard ndb_negentropy_storage_add(&storage, timestamp, idPtr) == 1 else {
                throw NdbNegentropyError.storageAlreadySealed
            }
        }
    }

    /// Seal the storage for use in reconciliation.
    /// After sealing, no more items can be added.
    func seal() throws {
        guard ndb_negentropy_storage_seal(&storage) == 1 else {
            throw NdbNegentropyError.storageSealFailed
        }
    }

    /// Number of items in storage.
    var count: Int {
        ndb_negentropy_storage_size(&storage)
    }

    /// Whether the storage is sealed and ready for reconciliation.
    var isSealed: Bool {
        storage.sealed != 0
    }

    /// Internal pointer for use with NdbNegentropy.
    var pointer: UnsafePointer<ndb_negentropy_storage> {
        withUnsafePointer(to: &storage) { $0 }
    }

    deinit {
        if !isDestroyed {
            ndb_negentropy_storage_destroy(&storage)
            isDestroyed = true
        }
    }
}

/// Configuration for negentropy reconciliation.
struct NdbNegentropyConfig {
    /// Maximum message size in bytes. 0 = unlimited.
    var frameSizeLimit: Int32 = 0

    /// Threshold for switching between fingerprint and idlist modes.
    /// Ranges with fewer items send full ID lists.
    var idlistThreshold: Int32 = 16

    /// Number of sub-ranges to split into when fingerprints differ.
    var splitCount: Int32 = 16

    /// Create a C config struct.
    func toCConfig() -> ndb_negentropy_config {
        return ndb_negentropy_config(
            frame_size_limit: frameSizeLimit,
            idlist_threshold: idlistThreshold,
            split_count: splitCount
        )
    }
}

/// Swift wrapper for negentropy reconciliation (ndb_negentropy).
/// Processes messages and determines which items each side has that the other lacks.
final class NdbNegentropy {
    private var neg: ndb_negentropy
    private var isDestroyed = false

    // Keep a strong reference to storage to prevent it from being deallocated
    private let storageRef: NdbNegentropyStorage

    /// Initialize reconciliation context.
    ///
    /// - Parameters:
    ///   - storage: Sealed storage containing local items
    ///   - config: Optional configuration (nil uses defaults)
    init(storage: NdbNegentropyStorage, config: NdbNegentropyConfig? = nil) throws {
        self.storageRef = storage
        self.neg = ndb_negentropy()

        var cConfig = config?.toCConfig() ?? ndb_negentropy_config()
        let configPtr = config != nil ? withUnsafePointer(to: &cConfig) { $0 } : nil

        guard ndb_negentropy_init(&neg, storage.pointer, configPtr) == 1 else {
            throw NdbNegentropyError.reconciliationInitFailed
        }
    }

    /// Create the initial message to start reconciliation.
    /// Returns the binary message to send to the relay.
    func initiate() throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var outlen: Int = 0

        guard ndb_negentropy_initiate(&neg, &buffer, buffer.count, &outlen) == 1 else {
            throw NdbNegentropyError.initiateFailed
        }

        return Data(buffer.prefix(outlen))
    }

    /// Create the initial message as a hex string for NIP-77.
    func initiateHex() throws -> String {
        let data = try initiate()
        return data.map { String(format: "%02x", $0) }.joined()
    }

    /// Process an incoming message and generate a response.
    ///
    /// - Parameter message: Binary message received from relay
    /// - Returns: Response message to send back (empty if reconciliation complete)
    func reconcile(message: Data) throws -> Data {
        // Use 1MB buffer for response generation
        // With 4000+ input ranges, output can exceed 512KB (seen 524KB+ in testing)
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        var outlen = buffer.count

        let result = message.withUnsafeBytes { msgPtr -> Int32 in
            guard let baseAddress = msgPtr.baseAddress else { return 0 }
            return ndb_negentropy_reconcile(
                &neg,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                message.count,
                &buffer,
                &outlen
            )
        }

        guard result == 1 else {
            // Try to diagnose the failure
            let rangeCheck = message.withUnsafeBytes { ptr -> Int32 in
                guard let baseAddress = ptr.baseAddress else { return -2 }
                return ndb_negentropy_message_count_ranges(
                    baseAddress.assumingMemoryBound(to: UInt8.self),
                    message.count
                )
            }
            // Log first 32 bytes of message for debugging
            let hexPrefix = message.prefix(32).map { String(format: "%02x", $0) }.joined()
            Log.error("ndb_negentropy_reconcile failed: input=%d bytes, version=0x%02x, rangeCheck=%d, bufsize=%d, prefix=%s",
                     for: .networking, message.count, message.first ?? 0, rangeCheck, buffer.count, hexPrefix)
            throw NdbNegentropyError.reconcileFailed
        }

        return Data(buffer.prefix(outlen))
    }

    /// Process an incoming hex message and generate a hex response.
    ///
    /// - Parameter hexMessage: Hex-encoded message from relay
    /// - Returns: Hex-encoded response (empty string if complete)
    func reconcileHex(hexMessage: String) throws -> String {
        guard let messageData = hexMessage.hexDecodedData else {
            Log.error("ndb_negentropy: failed to decode hex message (length=%d)", for: .networking, hexMessage.count)
            throw NdbNegentropyError.reconcileFailed
        }

        // Count ranges in message for diagnostics
        let rangeCount = messageData.withUnsafeBytes { ptr -> Int32 in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return ndb_negentropy_message_count_ranges(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                messageData.count
            )
        }

        Log.debug("ndb_negentropy: processing message of %d bytes (version=0x%02x, ranges=%d)",
                 for: .networking, messageData.count, messageData.first ?? 0, rangeCount)

        let response = try reconcile(message: messageData)

        // Empty response (just version byte) means complete
        if response.count <= 1 {
            Log.debug("ndb_negentropy: reconciliation complete (have=%d, need=%d)",
                     for: .networking, haveIds.count, needIds.count)
            return ""
        }

        Log.debug("ndb_negentropy: generated response of %d bytes", for: .networking, response.count)
        return response.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether reconciliation is complete.
    var isComplete: Bool {
        ndb_negentropy_is_complete(&neg) == 1
    }

    /// IDs we have that the remote needs (events to send).
    var haveIds: [NoteId] {
        var idsPtr: UnsafePointer<UInt8>?
        let count = ndb_negentropy_get_have_ids(&neg, &idsPtr)

        guard count > 0, let ptr = idsPtr else {
            return []
        }

        var result: [NoteId] = []
        for i in 0..<count {
            let idData = Data(bytes: ptr.advanced(by: Int(i) * 32), count: 32)
            result.append(NoteId(idData))
        }
        return result
    }

    /// IDs the remote has that we need (events to request).
    var needIds: [NoteId] {
        var idsPtr: UnsafePointer<UInt8>?
        let count = ndb_negentropy_get_need_ids(&neg, &idsPtr)

        guard count > 0, let ptr = idsPtr else {
            return []
        }

        var result: [NoteId] = []
        for i in 0..<count {
            let idData = Data(bytes: ptr.advanced(by: Int(i) * 32), count: 32)
            result.append(NoteId(idData))
        }
        return result
    }

    deinit {
        if !isDestroyed {
            ndb_negentropy_destroy(&neg)
            isDestroyed = true
        }
    }
}

// MARK: - Hex Decoding Helper

private extension String {
    var hexDecodedData: Data? {
        guard count % 2 == 0 else { return nil }

        var data = Data(capacity: count / 2)
        var index = startIndex

        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: 2)
            guard let byte = UInt8(self[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        return data
    }
}
