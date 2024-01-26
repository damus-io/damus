//
//  NdbTx.swift
//  damus
//
//  Created by William Casarin on 2023-08-30.
//

import Foundation

#if TXNDEBUG
fileprivate var txn_count: Int = 0
#endif

// Would use struct and ~Copyable but generics aren't supported well
class NdbTxn<T> {
    var txn: ndb_txn
    private var val: T!
    var moved: Bool
    var inherited: Bool
    var ndb: Ndb
    var generation: Int

    init?(ndb: Ndb, with: (NdbTxn<T>) -> T = { _ in () }) {
        guard !ndb.closed else { return nil }
        self.ndb = ndb
        self.generation = ndb.generation
#if TXNDEBUG
        txn_count += 1
        print("opening transaction \(txn_count)")
        #endif
        if let active_txn = Thread.current.threadDictionary["ndb_txn"] as? ndb_txn {
            // some parent thread is active, use that instead
            self.txn = active_txn
            self.inherited = true
            self.generation = Thread.current.threadDictionary["txn_generation"] as! Int
        } else {
            self.txn = ndb_txn()
            guard !ndb.closed else { return nil }
            self.generation = ndb.generation
            let ok = ndb_begin_query(ndb.ndb.ndb, &self.txn) != 0
            if !ok {
                return nil
            }
            self.generation = ndb.generation
            Thread.current.threadDictionary["ndb_txn"] = self.txn
            Thread.current.threadDictionary["txn_generation"] = ndb.generation
            self.inherited = false
        }
        self.moved = false
        self.val = with(self)
    }

    private init(ndb: Ndb, txn: ndb_txn, val: T) {
        self.txn = txn
        self.val = val
        self.moved = false
        self.inherited = false
        self.ndb = ndb
        self.generation = 0
    }

    /// Only access temporarily! Do not store database references for longterm use. If it's a primitive type you
    /// can retrieve this value with `.value`
    var unsafeUnownedValue: T {
        precondition(!moved)
        return val
    }

    deinit {
        if self.generation != ndb.generation {
            //print("txn: OLD GENERATION (\(self.generation) != \(ndb.generation)), IGNORING")
            return
        }
        if moved || inherited || ndb.closed {
            return
        }

        #if TXNDEBUG
        txn_count -= 1;
        print("txn: closing transaction \(txn_count)")
        #endif
        ndb_end_query(&self.txn)
        Thread.current.threadDictionary.removeObject(forKey: "ndb_txn")
    }

    // functor
    func map<Y>(_ transform: (T) -> Y) -> NdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: transform(val))
    }

    // comonad!?
    // useful for moving ownership of a transaction to another value
    func extend<Y>(_ with: (NdbTxn<T>) -> Y) -> NdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: with(self))
    }
}

protocol OptionalType {
    associatedtype Wrapped
    var optional: Wrapped? { get }
}

extension Optional: OptionalType {
    typealias Wrapped = Wrapped

    var optional: Wrapped? {
        return self
    }
}

extension NdbTxn where T: OptionalType {
    func collect() -> NdbTxn<T.Wrapped>? {
        guard let unwrappedVal: T.Wrapped = val.optional else {
            return nil
        }
        self.moved = true
        return NdbTxn<T.Wrapped>(ndb: self.ndb, txn: self.txn, val: unwrappedVal)
    }
}

extension NdbTxn where T == Bool { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == Bool? { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == Int { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == Int? { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == Double { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == Double? { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == UInt64 { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == UInt64? { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == String { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == String? { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == NoteId? { var value: T { return self.unsafeUnownedValue } }
extension NdbTxn where T == NoteId { var value: T { return self.unsafeUnownedValue } }
