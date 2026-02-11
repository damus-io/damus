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

/// Type-safe keys for NdbTxn thread-local storage
fileprivate enum NdbTxnThreadDictionaryKey {
    static let txn = "ndb_txn"
    static let refCount = "ndb_txn_ref_count"
    static let generation = "txn_generation"
}

/// Helper to safely clear all NdbTxn thread-local state
fileprivate extension NSMutableDictionary {
    func clearNdbTxnState() {
        self.removeObject(forKey: NdbTxnThreadDictionaryKey.txn)
        self.removeObject(forKey: NdbTxnThreadDictionaryKey.refCount)
        self.removeObject(forKey: NdbTxnThreadDictionaryKey.generation)
    }
}

// Would use struct and ~Copyable but generics aren't supported well
class NdbTxn<T>: RawNdbTxnAccessible {
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
    
    /// Simple helper struct for the init function to avoid compiler errors encountered by using other techniques
    private struct R {
        let txn: ndb_txn
        let generation: Int
    }

    init?(ndb: Ndb, with: (NdbTxn<T>) -> T = { _ in () }, name: String? = nil) {
        guard !ndb.is_closed else { return nil }
        self.name = name ?? "txn"
        self.ndb = ndb
        self.generation = ndb.generation

        // Extract all thread dictionary values safely (no force unwraps)
        let threadDictionary = Thread.current.threadDictionary
        let activeTxn = threadDictionary[NdbTxnThreadDictionaryKey.txn] as? ndb_txn
        let txnGeneration = threadDictionary[NdbTxnThreadDictionaryKey.generation] as? Int
        let refCount = threadDictionary[NdbTxnThreadDictionaryKey.refCount] as? Int

        // Check if we can inherit a valid parent transaction
        if let activeTxn, let txnGeneration, txnGeneration == ndb.generation, let refCount {
            // All required values present and valid - inherit the transaction
            print("txn: inherited txn")
            self.txn = activeTxn
            self.inherited = true
            self.generation = txnGeneration
            threadDictionary[NdbTxnThreadDictionaryKey.refCount] = refCount + 1
        } else {
            // Cannot inherit - clear any partial/stale state and create fresh transaction
            if activeTxn != nil || txnGeneration != nil || refCount != nil {
                print("txn: inconsistent state detected, clearing and creating fresh transaction")
                threadDictionary.clearNdbTxnState()
            }

            let result: R? = try? ndb.withNdb({
                var txn = ndb_txn()
                #if TXNDEBUG
                txn_count += 1
                #endif
                let ok = ndb_begin_query(ndb.ndb.ndb, &txn) != 0
                guard ok else { return .none }
                return .some(R(txn: txn, generation: ndb.generation))
            }, maxWaitTimeout: .milliseconds(200))
            guard let result else { return nil }
            self.txn = result.txn
            self.generation = result.generation
            threadDictionary[NdbTxnThreadDictionaryKey.txn] = self.txn
            threadDictionary[NdbTxnThreadDictionaryKey.refCount] = 1
            threadDictionary[NdbTxnThreadDictionaryKey.generation] = ndb.generation
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
    internal var unsafeUnownedValue: T {
        precondition(!moved)
        return val
    }

    deinit {
        if self.generation != ndb.generation {
            print("txn: OLD GENERATION (\(self.generation) != \(ndb.generation)), IGNORING")
            return
        }
        if ndb.is_closed {
            print("txn: not closing. db closed")
            return
        }

        let threadDictionary = Thread.current.threadDictionary
        if let refCount = threadDictionary[NdbTxnThreadDictionaryKey.refCount] as? Int {
            let newRefCount = refCount - 1
            threadDictionary[NdbTxnThreadDictionaryKey.refCount] = newRefCount
            assert(newRefCount >= 0, "NdbTxn reference count should never be below zero")
            if newRefCount <= 0 {
                _ = try? ndb.withNdb({
                    ndb_end_query(&self.txn)
                }, maxWaitTimeout: .milliseconds(200))
                threadDictionary.clearNdbTxnState()
            }
        }
        if inherited {
            print("txn: not closing. inherited ")
            return
        }
        if moved {
            //print("txn: not closing. moved")
            return
        }

        #if TXNDEBUG
        txn_count -= 1;
        print("txn: close gen\(generation) '\(name)' \(txn_count)")
        #endif
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

protocol RawNdbTxnAccessible: AnyObject {
    var txn: ndb_txn { get set }
}

class PlaceholderNdbTxn: RawNdbTxnAccessible {
    var txn: ndb_txn
    
    init(txn: ndb_txn) {
        self.txn = txn
    }
}

class SafeNdbTxn<T: ~Copyable> {
    var txn: ndb_txn
    var val: T!
    var moved: Bool
    var inherited: Bool
    var ndb: Ndb
    var generation: Int
    var name: String

    static func pure(ndb: Ndb, val: consuming T) -> SafeNdbTxn<T> {
        .init(ndb: ndb, txn: ndb_txn(), val: val, generation: ndb.generation, inherited: true, name: "pure_txn")
    }
    
    /// Simple helper struct for the init function to avoid compiler errors encountered by using other techniques
    private struct R {
        let txn: ndb_txn
        let generation: Int
    }
    
    static func new(on ndb: Ndb, with valueGetter: (PlaceholderNdbTxn) -> T? = { _ in () }, name: String = "txn") -> SafeNdbTxn<T>? {
        guard !ndb.is_closed else { return nil }
        let generation: Int
        let txn: ndb_txn
        let inherited: Bool

        // Extract all thread dictionary values safely (no force unwraps)
        let threadDictionary = Thread.current.threadDictionary
        let activeTxn = threadDictionary[NdbTxnThreadDictionaryKey.txn] as? ndb_txn
        let txnGeneration = threadDictionary[NdbTxnThreadDictionaryKey.generation] as? Int
        let refCount = threadDictionary[NdbTxnThreadDictionaryKey.refCount] as? Int

        // Check if we can inherit a valid parent transaction
        if let activeTxn, let txnGeneration, txnGeneration == ndb.generation, let refCount {
            // All required values present and valid - inherit the transaction
            print("txn: inherited txn")
            txn = activeTxn
            inherited = true
            generation = txnGeneration
            threadDictionary[NdbTxnThreadDictionaryKey.refCount] = refCount + 1
        } else {
            // Cannot inherit - clear any partial/stale state and create fresh transaction
            if activeTxn != nil || txnGeneration != nil || refCount != nil {
                print("txn: inconsistent state detected, clearing and creating fresh transaction")
                threadDictionary.clearNdbTxnState()
            }

            let result: R? = try? ndb.withNdb({
                var txn = ndb_txn()
                #if TXNDEBUG
                txn_count += 1
                #endif
                let ok = ndb_begin_query(ndb.ndb.ndb, &txn) != 0
                guard ok else { return .none }
                return .some(R(txn: txn, generation: ndb.generation))
            }, maxWaitTimeout: .milliseconds(200))
            guard let result else { return nil }
            txn = result.txn
            generation = result.generation
            threadDictionary[NdbTxnThreadDictionaryKey.txn] = txn
            threadDictionary[NdbTxnThreadDictionaryKey.refCount] = 1
            threadDictionary[NdbTxnThreadDictionaryKey.generation] = ndb.generation
            inherited = false
        }
        #if TXNDEBUG
        print("txn: open  gen\(generation) '\(name)' \(txn_count)")
        #endif
        let placeholderTxn = PlaceholderNdbTxn(txn: txn)
        guard let val = valueGetter(placeholderTxn) else {
            // Fix leak: Close transaction before returning nil
            if !inherited {
                var mutableTxn = txn
                _ = try? ndb.withNdb({ ndb_end_query(&mutableTxn) }, maxWaitTimeout: .milliseconds(200))
                #if TXNDEBUG
                txn_count -= 1
                print("txn: close (valueGetter nil) gen\(generation) '\(name)' \(txn_count)")
                #endif
            }
            return nil
        }
        return SafeNdbTxn<T>(ndb: ndb, txn: txn, val: val, generation: generation, inherited: inherited, name: name)
    }

    private init(ndb: Ndb, txn: ndb_txn, val: consuming T, generation: Int, inherited: Bool, name: String) {
        self.txn = txn
        self.val = consume val
        self.moved = false
        self.inherited = inherited
        self.ndb = ndb
        self.generation = generation
        self.name = name
    }

    deinit {
        if self.generation != ndb.generation {
            print("txn: OLD GENERATION (\(self.generation) != \(ndb.generation)), IGNORING")
            return
        }
        if ndb.is_closed {
            print("txn: not closing. db closed")
            return
        }

        let threadDictionary = Thread.current.threadDictionary
        if let refCount = threadDictionary[NdbTxnThreadDictionaryKey.refCount] as? Int {
            let newRefCount = refCount - 1
            threadDictionary[NdbTxnThreadDictionaryKey.refCount] = newRefCount
            assert(newRefCount >= 0, "NdbTxn reference count should never be below zero")
            if newRefCount <= 0 {
                _ = try? ndb.withNdb({
                    ndb_end_query(&self.txn)
                }, maxWaitTimeout: .milliseconds(200))
                threadDictionary.clearNdbTxnState()
            }
        }
        if inherited {
            print("txn: not closing. inherited ")
            return
        }
        if moved {
            //print("txn: not closing. moved")
            return
        }

        #if TXNDEBUG
        txn_count -= 1;
        print("txn: close gen\(generation) '\(name)' \(txn_count)")
        #endif
    }

    // functor
    func map<Y>(_ transform: (borrowing T) -> Y) -> SafeNdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: transform(val), generation: generation, inherited: inherited, name: self.name)
    }

    // comonad!?
    // useful for moving ownership of a transaction to another value
    func extend<Y>(_ with: (SafeNdbTxn<T>) -> Y) -> SafeNdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: with(self), generation: generation, inherited: inherited, name: self.name)
    }
    
    consuming func maybeExtend<Y>(_ with: (consuming SafeNdbTxn<T>) -> Y?) -> SafeNdbTxn<Y>? where Y: ~Copyable {
        self.moved = true
        let ndb = self.ndb
        let txn = self.txn
        let generation = self.generation
        let inherited = self.inherited
        let name = self.name

        guard let newVal = with(consume self) else {
            // Fix leak: Close transaction on nil path if we own it
            if !inherited {
                var mutableTxn = txn
                _ = try? ndb.withNdb({ ndb_end_query(&mutableTxn) }, maxWaitTimeout: .milliseconds(200))
                #if TXNDEBUG
                txn_count -= 1
                print("txn: close (maybeExtend nil) gen\(generation) '\(name)' \(txn_count)")
                #endif
            }
            return nil
        }

        return .init(ndb: ndb, txn: txn, val: newVal, generation: generation, inherited: inherited, name: name)
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
