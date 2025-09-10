//
//  UnownedNdbNote.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-25.
//

/// Allows an unowned note to be safely lent out temporarily.
///
/// Use this to provide access to NostrDB unowned notes in a way that has much better compile-time safety guarantees.
///
/// # Usage examples
///
/// ## Lending out or providing Ndb notes
///
/// ```swift
/// let noteKey = functionThatDoesSomeLookupOrSubscriptionOnNDB()
/// // Define the lender
/// let lender = NdbNoteLender(ndb: self.ndb, noteKey: noteKey)
/// return lender                                               // Return or pass the lender to another class
/// ```
///
/// ## Borrowing Ndb notes
///
/// Assuming you are given a lender, here is how you can use it:
///
/// ```swift
/// func getTimestampForMyMutelist() throws -> UInt32 {
///     let lender = functionThatSomehowReturnsMyMutelist()
///     return try lender.borrow({ event in     // Here we are only borrowing, so the compiler won't allow us to copy `event` to an external variable
///         return event.created_at             // No need to copy the entire note, we only need the timestamp
///     })
/// }
/// ```
///
/// If you need to retain the entire note, you may need to copy it. Here is how:
///
/// ```swift
/// func getTimestampForMyContactList() throws -> NdbNote {
///     let lender = functionThatSomehowReturnsMyContactList()
///     return try lender.getNoteCopy() // This will automatically make an owned copy of the note, which can be passed around safely.
/// }
/// ```
enum NdbNoteLender: Sendable {
    case ndbNoteKey(Ndb, NoteKey)
    case owned(NdbNote)
    
    init(ndb: Ndb, noteKey: NoteKey) {
        self = .ndbNoteKey(ndb, noteKey)
    }
    
    init(ownedNdbNote: NdbNote) {
        self = .owned(ownedNdbNote)
    }
    
    /// Borrows the note temporarily
    func borrow<T>(_ lendingFunction: (_: borrowing UnownedNdbNote) throws -> T) throws -> T {
        switch self {
        case .ndbNoteKey(let ndb, let noteKey):
            guard !ndb.is_closed else { throw LendingError.ndbClosed }
            guard let ndbNoteTxn = ndb.lookup_note_by_key(noteKey) else { throw LendingError.errorLoadingNote }
            guard let unownedNote = UnownedNdbNote(ndbNoteTxn) else { throw LendingError.errorLoadingNote }
            return try lendingFunction(unownedNote)
        case .owned(let note):
            return try lendingFunction(UnownedNdbNote(note))
        }
        
    }
    
    /// Gets an owned copy of the note
    func getCopy() throws -> NdbNote {
        return try self.borrow({ ev in
            return ev.toOwned()
        })
    }
    
    /// A lenient and simple function to just use a copy, where implementing custom error handling is unfeasible or too burdensome and failures should not stop flow.
    ///
    /// Since the errors related to borrowing and copying are unlikely, instead of implementing custom error handling, a simple default error handling logic may be used.
    ///
    /// This implements error handling in the following way:
    /// - On debug builds, it will throw an assertion to alert developers that something is off
    /// - On production builds, an error will be printed to the logs.
    func justUseACopy<T>(_ useFunction: (_: NdbNote) throws -> T) rethrows -> T? {
        guard let event = self.justGetACopy() else { return nil }
        return try useFunction(event)
    }
    
    /// A lenient and simple function to just use a copy, where implementing custom error handling is unfeasible or too burdensome and failures should not stop flow.
    ///
    /// Since the errors related to borrowing and copying are unlikely, instead of implementing custom error handling, a simple default error handling logic may be used.
    ///
    /// This implements error handling in the following way:
    /// - On debug builds, it will throw an assertion to alert developers that something is off
    /// - On production builds, an error will be printed to the logs.
    func justUseACopy<T>(_ useFunction: (_: NdbNote) async throws -> T) async rethrows -> T? {
        guard let event = self.justGetACopy() else { return nil }
        return try await useFunction(event)
    }
    
    /// A lenient and simple function to just get a copy, where implementing custom error handling is unfeasible or too burdensome and failures should not stop flow.
    ///
    /// Since the errors related to borrowing and copying are unlikely, instead of implementing custom error handling, a simple default error handling logic may be used.
    ///
    /// This implements error handling in the following way:
    /// - On debug builds, it will throw an assertion to alert developers that something is off
    /// - On production builds, an error will be printed to the logs.
    func justGetACopy() -> NdbNote? {
        do {
            return try self.getCopy()
        }
        catch {
            assertionFailure("Unexpected error while fetching a copy of an NdbNote: \(error.localizedDescription)")
            Log.error("Unexpected error while fetching a copy of an NdbNote: %s", for: .ndb, error.localizedDescription)
        }
        return nil
    }
    
    enum LendingError: Error {
        case errorLoadingNote
        case ndbClosed
    }
}


/// A wrapper to NdbNote that allows unowned NdbNotes to be safely handled
struct UnownedNdbNote: ~Copyable {
    private let _ndbNote: NdbNote
    
    init(_ txn: NdbTxn<NdbNote>) {
        self._ndbNote = txn.unsafeUnownedValue
    }
    
    init?(_ txn: NdbTxn<NdbNote?>) {
        guard let note = txn.unsafeUnownedValue else { return nil }
        self._ndbNote = note
    }
    
    init(_ ndbNote: NdbNote) {
        self._ndbNote = ndbNote
    }
    
    var kind: UInt32 { _ndbNote.kind }
    var known_kind: NostrKind? { _ndbNote.known_kind }
    var content: String { _ndbNote.content }
    var tags: TagsSequence { _ndbNote.tags }
    var pubkey: Pubkey { _ndbNote.pubkey }
    var createdAt: UInt32 { _ndbNote.created_at }
    var id: NoteId { _ndbNote.id }
    var sig: Signature { _ndbNote.sig }
    
    func toOwned() -> NdbNote {
        return _ndbNote.to_owned()
    }
}
