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
    var name: String

    static func pure(ndb: Ndb, val: T) -> NdbTxn<T> {
        .init(ndb: ndb, txn: ndb_txn(), val: val, generation: ndb.generation, inherited: true, name: "pure_txn")
    }

    init?(ndb: Ndb, with: (NdbTxn<T>) -> T = { _ in () }, name: String? = nil) {
        guard !ndb.is_closed else { return nil }
        self.name = name ?? "txn"
        self.ndb = ndb
        self.generation = ndb.generation
        if let active_txn = Thread.current.threadDictionary["ndb_txn"] as? ndb_txn {
            // some parent thread is active, use that instead
            print("txn: inherited txn")
            self.txn = active_txn
            self.inherited = true
            self.generation = Thread.current.threadDictionary["txn_generation"] as! Int
        } else {
            self.txn = ndb_txn()
            guard !ndb.is_closed else { return nil }
            self.generation = ndb.generation
            #if TXNDEBUG
            txn_count += 1
            #endif
            let ok = ndb_begin_query(ndb.ndb.ndb, &self.txn) != 0
            if !ok {
                return nil
            }
            self.generation = ndb.generation
            Thread.current.threadDictionary["ndb_txn"] = self.txn
            Thread.current.threadDictionary["txn_generation"] = ndb.generation
            self.inherited = false
        }
        #if TXNDEBUG
        print("txn: open  gen\(self.generation) '\(self.name)' \(txn_count)")
        #endif
        self.moved = false
        self.val = with(self)
    }

    private init(ndb: Ndb, txn: ndb_txn, val: T, generation: Int, inherited: Bool, name: String) {
        self.txn = txn
        self.val = val
        self.moved = false
        self.inherited = inherited
        self.ndb = ndb
        self.generation = generation
        self.name = name
    }

    /// Only access temporarily! Do not store database references for longterm use. If it's a primitive type you
    /// can retrieve this value with `.value`
    var unsafeUnownedValue: T {
        precondition(!moved)
        return val
    }

    deinit {
        if self.generation != ndb.generation {
            print("txn: OLD GENERATION (\(self.generation) != \(ndb.generation)), IGNORING")
            return
        }
        if inherited {
            print("txn: not closing. inherited ")
            return
        }
        if moved {
            //print("txn: not closing. moved")
            return
        }
        if ndb.is_closed {
            print("txn: not closing. db closed")
            return
        }

        #if TXNDEBUG
        txn_count -= 1;
        print("txn: close gen\(generation) '\(name)' \(txn_count)")
        #endif
        ndb_end_query(&self.txn)
        //self.skip_close = true
        Thread.current.threadDictionary.removeObject(forKey: "ndb_txn")
    }

    // functor
    func map<Y>(_ transform: (T) -> Y) -> NdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: transform(val), generation: generation, inherited: inherited, name: self.name)
    }

    // comonad!?
    // useful for moving ownership of a transaction to another value
    func extend<Y>(_ with: (NdbTxn<T>) -> Y) -> NdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: with(self), generation: generation, inherited: inherited, name: self.name)
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
        return NdbTxn<T.Wrapped>(ndb: self.ndb, txn: self.txn, val: unwrappedVal, generation: generation, inherited: inherited, name: name)
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
