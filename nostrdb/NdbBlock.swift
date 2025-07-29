//
//  NdbBlock.swift
//  damus
//
//  Created by William Casarin on 2024-01-25.
//

import Foundation

enum NdbBlockType: UInt32 {
    case hashtag = 1
    case text = 2
    case mention_index = 3
    case mention_bech32 = 4
    case url = 5
    case invoice = 6
}

extension ndb_mention_bech32_block {
    var bech32_type: NdbBech32Type? {
        NdbBech32Type(rawValue: self.bech32.type.rawValue)
    }
}

enum NdbBech32Type: UInt32 {
    case note = 1
    case npub = 2
    case nprofile = 3
    case nevent = 4
    case nrelay = 5
    case naddr = 6
    case nsec = 7

    var is_notelike: Bool {
        return self == .note || self == .nevent
    }
}

extension ndb_invoice_block {
    func as_invoice() -> Invoice? {
        let b11 = self.invoice
        let invstr = self.invstr.as_str()

        guard let description = convert_invoice_description(b11: b11) else {
            return nil
        }
        
        let amount: Amount = b11.amount == 0 ? .any : .specific(Int64(b11.amount))

        return Invoice(description: description, amount: amount, string: invstr, expiry: b11.expiry, created_at: b11.timestamp)
    }
}

enum NdbBlock: ~Copyable {
    case text(ndb_str_block)
    case mention(ndb_mention_bech32_block)
    case hashtag(ndb_str_block)
    case url(ndb_str_block)
    case invoice(ndb_invoice_block)
    case mention_index(UInt32)

    init?(_ ptr: ndb_block_ptr) {
        guard let type = NdbBlockType(rawValue: ndb_get_block_type(ptr.ptr).rawValue) else {
            return nil
        }
        switch type {
        case .hashtag: self = .hashtag(ptr.block.str)
        case .text:    self = .text(ptr.block.str)
        case .invoice: self = .invoice(ptr.block.invoice)
        case .url:     self = .url(ptr.block.str)
        case .mention_bech32: self = .mention(ptr.block.mention_bech32)
        case .mention_index:  self = .mention_index(ptr.block.mention_index)
        }
    }
    
    var is_previewable: Bool {
        switch self {
        case .mention(let m):
            switch m.bech32_type {
            case .note, .nevent: return true
            default: return false
            }
        case .invoice:
            return true
        case .url:
            return true
        default:
            return false
        }
    }
    
    static func convertToStringCopy(from block: str_block_t) -> String? {
        guard let cString = block.str else {
            return nil
        }
        // Copy byte-by-byte from the pointer into a new buffer
        let byteBuffer = UnsafeBufferPointer(start: cString, count: Int(block.len)).map { UInt8(bitPattern: $0) }

        // Create an owned Swift String from the buffer we created
        return String(bytes: byteBuffer, encoding: .utf8)
    }
}

/// Represents a group of blocks
struct NdbBlockGroup: ~Copyable {
    /// The block offsets
    fileprivate let metadata: MaybeTxn<BlocksMetadata>
    /// The raw text content of the note
    fileprivate let rawTextContent: String
    var words: Int {
        return metadata.borrow { $0.words }
    }
    
    /// Gets the parsed blocks from a specific note.
    ///
    /// This function will:
    /// - fetch blocks information from NostrDB if possible _and_ available, or
    /// - parse blocks on-demand.
    static func from(event: NdbNote, using ndb: Ndb, and keypair: Keypair) throws(NdbBlocksError) -> Self {
        if event.is_content_encrypted() {
            return try parse(event: event, keypair: keypair)
        }
        else if event.known_kind == .highlight {
            return try parse(event: event, keypair: keypair)
        }
        else {
            guard let offsets = event.block_offsets(ndb: ndb) else {
                return try parse(event: event, keypair: keypair)
            }
            return .init(metadata: .txn(offsets), rawTextContent: event.content)
        }
    }
    
    /// Parses the note contents on-demand from a specific note.
    ///
    /// Prioritize using `from(event: NdbNote, using ndb: Ndb, and keypair: Keypair)` when possible.
    static func parse(event: NdbNote, keypair: Keypair) throws(NdbBlocksError) -> Self {
        guard let content = event.maybe_get_content(keypair) else { throw NdbBlocksError.decryptionError }
        guard let metadata = BlocksMetadata.parseContent(content: content) else { throw NdbBlocksError.parseError }
        return self.init(
            metadata: .pure(metadata),
            rawTextContent: content
        )
    }
    
    /// Parses the note contents on-demand from a specific text.
    static func parse(content: String) throws(NdbBlocksError) -> Self {
        guard let metadata = BlocksMetadata.parseContent(content: content) else { throw NdbBlocksError.parseError }
        return self.init(
            metadata: .pure(metadata),
            rawTextContent: content
        )
    }
}

enum MaybeTxn<T: ~Copyable>: ~Copyable {
    case pure(T)
    case txn(SafeNdbTxn<T>)
    
    func borrow<Y>(_ borrowFunction: (borrowing T) throws -> Y) rethrows -> Y {
        switch self {
        case .pure(let item):
            return try borrowFunction(item)
        case .txn(let txn):
            return try borrowFunction(txn.val)
        }
    }
}


// MARK: - Helper structs

extension NdbBlockGroup {
    /// Wrapper for the `ndb_blocks` C struct
    ///
    /// This does not store the actual block contents, only the offsets on the content string and block metadata.
    ///
    /// **Implementation note:** This would be better as `~Copyable`, but `NdbTxn` does not support `~Copyable` yet.
    struct BlocksMetadata: ~Copyable {
        private let blocks_ptr: ndb_blocks_ptr
        private let buffer: UnsafeMutableRawPointer?
        
        init(ptr: OpaquePointer?, buffer: UnsafeMutableRawPointer? = nil) {
            self.blocks_ptr = ndb_blocks_ptr(ptr: ptr)
            self.buffer = buffer
        }
        
        var words: Int {
            Int(ndb_blocks_word_count(blocks_ptr.ptr))
        }
        
        /// Gets the opaque pointer
        ///
        /// **Implementation note:** This is marked `fileprivate` because we want to minimize the exposure of raw pointers to Swift code outside these wrapper structs.
        fileprivate func as_ptr() -> OpaquePointer? {
            return self.blocks_ptr.ptr
        }
        
        /// Parses text content and returns the parsed block metadata if successful
        ///
        /// **Implementation notes:** This is `fileprivate` because it makes no sense for outside Swift code to use this directly. Use `NdbBlockGroup` instead.
        fileprivate static func parseContent(content: String) -> Self? {
            // Allocate scratch buffer with enough space
            guard let buffer = malloc(MAX_NOTE_SIZE) else {
                return nil
            }
            
            var blocks: OpaquePointer? = nil
            
            // Call the C parsing function and check its success status
            let success = content.withCString { contentPtr -> Bool in
                let contentLen = content.utf8.count
                return ndb_parse_content(
                    buffer.assumingMemoryBound(to: UInt8.self),
                    Int32(MAX_NOTE_SIZE),
                    contentPtr,
                    Int32(contentLen),
                    &blocks
                ) == 1
            }
            
            if !success || blocks == nil {
                // Something failed
                free(buffer)
                return nil
            }
            
            // TODO: We should set the owned flag as in the C code.
            // However, There does not seem to be a way to set this from Swift code. The code shown below does not work.
            // blocks!.pointee.flags |= NDB_BLOCK_FLAG_OWNED
            // But perhaps this is not necessary because `NdbBlockGroup` is non-copyable
            
            return BlocksMetadata(ptr: blocks, buffer: buffer)
        }
        
        deinit {
            if let buffer {
                free(buffer)
            }
        }
    }
    
    /// Models specific errors that may happen when parsing or constructing an `NdbBlocks` object
    enum NdbBlocksError: Error {
        case parseError
        case decryptionError
    }
}


// MARK: - Enumeration support

extension NdbBlockGroup {
    typealias NdbBlockList = NonCopyableLinkedList<NdbBlock>
    
    /// Borrows all blocks in the group one by one and runs a function defined by the caller.
    ///
    /// **Implementation note:**
    /// This is done as a function instead of using `Sequence` and  `Iterator` protocols because it is currently not possible to conform to both `Sequence` and `~Copyable` at the same time, as Sequence requires elements to be `Copyable`
    ///
    /// - Parameter borrowingFunction: The function to be run on each iteration. Takes in two parameters: The index of the item in the list (zero-indexed), and the block itself.
    /// - Returns: The `Y` value returned by the provided function, when such function returns `.loopReturn(Y)`
    @discardableResult
    func forEachBlock<Y>(_ borrowingFunction: ((Int, borrowing NdbBlock) throws -> NdbBlockList.LoopCommand<Y>)) rethrows -> Y?  {
        return try withList({ try $0.forEachItem(borrowingFunction) })
    }
    
    /// Borrows all blocks in the group one by one and runs a function defined by the caller, in reverse order
    ///
    /// **Implementation note:**
    /// This is done as a function instead of using `Sequence` and  `Iterator` protocols because it is currently not possible to conform to both `Sequence` and `~Copyable` at the same time, as Sequence requires elements to be `Copyable`
    ///
    /// - Parameter borrowingFunction: The function to be run on each iteration. Takes in two parameters: The index of the item in the list (zero-indexed), and the block itself.
    /// - Returns: The `Y` value returned by the provided function, when such function returns `.loopReturn(Y)`
    @discardableResult
    func forEachBlockReversed<Y>(_ borrowingFunction: ((Int, borrowing NdbBlock) throws -> NdbBlockList.LoopCommand<Y>)) rethrows -> Y?  {
        return try withList({ try $0.forEachItemReversed(borrowingFunction) })
    }
    
    /// Iterates over each item of the list, updating a final value, and returns the final result at the end.
    func reduce<Y>(initialResult: Y, _ borrowingFunction: ((_ index: Int, _ partialResult: Y, _ item: borrowing NdbBlock) throws -> NdbBlockList.LoopCommand<Y>)) rethrows -> Y?  {
        return try withList({ try $0.reduce(initialResult: initialResult, borrowingFunction) })
    }
    
    /// Borrows the block list for processing
    func withList<Y>(_ borrowingFunction: (borrowing NdbBlockList) throws -> Y) rethrows -> Y {
        var linkedList: NdbBlockList = .init()
        
        return try self.rawTextContent.withCString { cptr in
            var iter = ndb_block_iterator(content: cptr, blocks: nil, block: ndb_block(), p: nil)
            
            // Start the iteration
            return try self.metadata.borrow { value in
                ndb_blocks_iterate_start(cptr, value.as_ptr(), &iter)
                
                // Collect blocks into array
                outerLoop: while let ptr = ndb_blocks_iterate_next(&iter),
                      let block = NdbBlock(ndb_block_ptr(ptr: ptr)) {
                    linkedList.add(item: block)
                }
                
                return try borrowingFunction(linkedList)
            }
        }
    }
}
