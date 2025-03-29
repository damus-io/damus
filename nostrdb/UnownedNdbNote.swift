//
//  UnownedNdbNote.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-25.
//

/// A function that allows an unowned NdbNote to be lent out temporarily
///
/// Use this to provide access to NostrDB unowned notes in a way that has much better compile-time safety guarantees.
///
/// # Usage examples
///
/// ## Lending out or providing Ndb notes
///
/// ```swift
/// // Define the lender
/// let lender: NdbNoteLender = { lend in
///     guard let ndbNoteTxn = ndb.lookup_note(noteId) else {   // Note: Must have access to `Ndb`
///         throw NdbNoteLenderError.errorLoadingNote           // Throw errors if loading fails
///     }
///     guard let unownedNote = UnownedNdbNote(ndbNoteTxn) else {
///         throw NdbNoteLenderError.errorLoadingNote
///     }
///     lend(unownedNote)                                       // Lend out the Unowned Ndb note
/// }
/// return lender                                               // Return or pass the lender to another class
/// ```
///
/// ## Borrowing Ndb notes
///
/// Assuming you are given a lender, here is how you can use it:
///
/// ```swift
/// let borrow: NdbNoteLender = functionThatProvidesALender()
/// try? borrow { note in               // You can optionally handle errors if borrowing fails
///    self.date = note.createdAt       // You can do things with the note without copying it over
///    // self.note = note              // Not allowed by the compiler
///    self.note = note.toOwned()       // You can copy the note if needed
/// }
/// ```
typealias NdbNoteLender = ((_: borrowing UnownedNdbNote) -> Void) throws -> Void

enum NdbNoteLenderError: Error {
    case errorLoadingNote
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
