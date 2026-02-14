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

private extension DispatchTimeInterval {
    static let ndbTransactionTimeout = DispatchTimeInterval.milliseconds(200)
}

// Would use struct and ~Copyable but generics aren't supported well
class NdbTxn<T>: RawNdbTxnAccessible {
    var txn: ndb_txn
    private var val: T!
    var moved: Bool
    var ownsTxn: Bool
    var ndb: Ndb
    var generation: Int
    var name: String

    static func pure(ndb: Ndb, val: T) -> NdbTxn<T> {
        .init(ndb: ndb, txn: ndb_txn(), val: val, generation: ndb.generation, ownsTxn: false, name: "pure_txn")
    }

    /// Simple helper struct for the init function to avoid compiler errors encountered by using other techniques
    private struct R {
        let txn: ndb_txn
        let generation: Int
    }

    /// Creates a new transaction with its own fresh LMDB snapshot.
    /// Returns `nil` if the database is closed or transaction creation fails.
    init?(ndb: Ndb, with: (NdbTxn<T>) -> T = { _ in () }, name: String? = nil) {
        guard !ndb.is_closed else { return nil }
        self.name = name ?? "txn"
        self.ndb = ndb
        self.generation = ndb.generation

        // Always create fresh transaction
        let result: R? = try? ndb.withNdb({
            var txn = ndb_txn()
            let ok = ndb_begin_query(ndb.ndb.ndb, &txn) != 0
            guard ok else {
                Log.error("Failed to begin NdbTxn '%s' (is_closed=%d)", for: .ndb, name ?? "txn", ndb.is_closed ? 1 : 0)
                return .none
            }
            #if TXNDEBUG
            txn_count += 1
            #endif
            return .some(R(txn: txn, generation: ndb.generation))
        }, maxWaitTimeout: .ndbTransactionTimeout)
        guard let result else { return nil }
        self.txn = result.txn
        self.generation = result.generation
        self.ownsTxn = true

        #if TXNDEBUG
        print("txn: open  gen\(self.generation) '\(self.name)' \(txn_count)")
        #endif
        self.moved = false
        self.val = with(self)
    }

    private init(ndb: Ndb, txn: ndb_txn, val: T, generation: Int, ownsTxn: Bool, name: String) {
        self.txn = txn
        self.val = val
        self.moved = false
        self.ownsTxn = ownsTxn
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
        if moved {
            //print("txn: not closing. moved")
            return
        }
        if !ownsTxn {
            print("txn: not closing. does not own txn")
            return
        }

        _ = try? ndb.withNdb({
            ndb_end_query(&self.txn)
        }, maxWaitTimeout: .ndbTransactionTimeout)

        #if TXNDEBUG
        txn_count -= 1;
        print("txn: close gen\(generation) '\(name)' \(txn_count)")
        #endif
    }

    // functor
    func map<Y>(_ transform: (T) -> Y) -> NdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: transform(val), generation: generation, ownsTxn: ownsTxn, name: self.name)
    }

    // comonad!?
    // useful for moving ownership of a transaction to another value
    func extend<Y>(_ with: (NdbTxn<T>) -> Y) -> NdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: with(self), generation: generation, ownsTxn: ownsTxn, name: self.name)
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
    var ownsTxn: Bool
    var ndb: Ndb
    var generation: Int
    var name: String

    static func pure(ndb: Ndb, val: consuming T) -> SafeNdbTxn<T> {
        .init(ndb: ndb, txn: ndb_txn(), val: val, generation: ndb.generation, ownsTxn: false, name: "pure_txn")
    }
    
    /// Simple helper struct for the init function to avoid compiler errors encountered by using other techniques
    private struct R {
        let txn: ndb_txn
        let generation: Int
    }

    /// Creates a new transaction with its own fresh LMDB snapshot.
    /// If `valueGetter` returns `nil`, the transaction is closed before returning.
    static func new(on ndb: Ndb, with valueGetter: (PlaceholderNdbTxn) -> T? = { _ in () }, name: String = "txn") -> SafeNdbTxn<T>? {
        guard !ndb.is_closed else { return nil }

        // Always create fresh transaction
        let result: R? = try? ndb.withNdb({
            var txn = ndb_txn()
            let ok = ndb_begin_query(ndb.ndb.ndb, &txn) != 0
            guard ok else { return .none }
            #if TXNDEBUG
            txn_count += 1
            #endif
            return .some(R(txn: txn, generation: ndb.generation))
        }, maxWaitTimeout: .ndbTransactionTimeout)
        guard let result else { return nil }
        let txn = result.txn
        let generation = result.generation

        #if TXNDEBUG
        print("txn: open  gen\(generation) '\(name)' \(txn_count)")
        #endif
        let placeholderTxn = PlaceholderNdbTxn(txn: txn)
        guard let val = valueGetter(placeholderTxn) else {
            // Fix leak: Close transaction before returning nil
            var mutableTxn = txn
            _ = try? ndb.withNdb({ ndb_end_query(&mutableTxn) }, maxWaitTimeout: .ndbTransactionTimeout)
            #if TXNDEBUG
            txn_count -= 1
            print("txn: close (valueGetter nil) gen\(generation) '\(name)' \(txn_count)")
            #endif
            return nil
        }
        return SafeNdbTxn<T>(ndb: ndb, txn: txn, val: val, generation: generation, ownsTxn: true, name: name)
    }

    private init(ndb: Ndb, txn: ndb_txn, val: consuming T, generation: Int, ownsTxn: Bool, name: String) {
        self.txn = txn
        self.val = consume val
        self.moved = false
        self.ownsTxn = ownsTxn
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
        if moved {
            //print("txn: not closing. moved")
            return
        }
        if !ownsTxn {
            print("txn: not closing. does not own txn")
            return
        }

        _ = try? ndb.withNdb({
            ndb_end_query(&self.txn)
        }, maxWaitTimeout: .ndbTransactionTimeout)

        #if TXNDEBUG
        txn_count -= 1;
        print("txn: close gen\(generation) '\(name)' \(txn_count)")
        #endif
    }

    // functor
    func map<Y>(_ transform: (borrowing T) -> Y) -> SafeNdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: transform(val), generation: generation, ownsTxn: ownsTxn, name: self.name)
    }

    // comonad!?
    // useful for moving ownership of a transaction to another value
    func extend<Y>(_ with: (SafeNdbTxn<T>) -> Y) -> SafeNdbTxn<Y> {
        self.moved = true
        return .init(ndb: self.ndb, txn: self.txn, val: with(self), generation: generation, ownsTxn: ownsTxn, name: self.name)
    }
    
    consuming func maybeExtend<Y>(_ with: (consuming SafeNdbTxn<T>) -> Y?) -> SafeNdbTxn<Y>? where Y: ~Copyable {
        self.moved = true
        let ndb = self.ndb
        let txn = self.txn
        let generation = self.generation
        let ownsTxn = self.ownsTxn
        let name = self.name

        guard let newVal = with(consume self) else {
            // Fix leak: Close transaction on nil path if we own it
            if ownsTxn {
                var mutableTxn = txn
                _ = try? ndb.withNdb({ ndb_end_query(&mutableTxn) }, maxWaitTimeout: .ndbTransactionTimeout)
                #if TXNDEBUG
                txn_count -= 1
                print("txn: close (maybeExtend nil) gen\(generation) '\(name)' \(txn_count)")
                #endif
            }
            return nil
        }

        return .init(ndb: ndb, txn: txn, val: newVal, generation: generation, ownsTxn: ownsTxn, name: name)
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
        return NdbTxn<T.Wrapped>(ndb: self.ndb, txn: self.txn, val: unwrappedVal, generation: generation, ownsTxn: ownsTxn, name: name)
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
