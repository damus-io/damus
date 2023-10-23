//
//  LNUrls.swift
//  damus
//
//  Created by William Casarin on 2023-01-17.
//

import Foundation

enum LNUrlState {
    case not_fetched
    case fetching(Task<LNUrlPayRequest?, Never>)
    case fetched(LNUrlPayRequest)
    case failed(tries: Int)
}

class LNUrls {
    var endpoints: [Pubkey: LNUrlState]

    init() {
        self.endpoints = [:]
    }

    @MainActor
    func lookup_or_fetch(pubkey: Pubkey, lnurl: String) async -> LNUrlPayRequest? {
        switch lookup(pubkey: pubkey) {
        case .failed(let tries):
            print("lnurls.lookup_or_fetch failed \(tries) \(lnurl)")
            guard tries < 5 else { return nil }
            self.endpoints[pubkey] = .failed(tries: tries + 1)
        case .fetched(let pr):
            //print("lnurls.lookup_or_fetch fetched \(lnurl)")
            return pr
        case .fetching(let task):
            //print("lnurls.lookup_or_fetch already fetching \(lnurl)")
            return await task.value
        case .not_fetched:
            print("lnurls.lookup_or_fetch not fetched \(lnurl)")
            break
        }

        let task = Task {
            let v = await fetch_static_payreq(lnurl)
            return v
        }

        self.endpoints[pubkey] = .fetching(task)

        let v = await task.value

        if let v {
            self.endpoints[pubkey] = .fetched(v)
        } else {
            self.endpoints[pubkey] = .failed(tries: 1)
        }

        return v
    }

    func lookup(pubkey: Pubkey) -> LNUrlState {
        return self.endpoints[pubkey] ?? .not_fetched
    }
}
