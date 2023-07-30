//
//  AttachedWalletNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct AttachedWalletNotify: Notify {
    typealias Payload = WalletConnectURL
    var payload: Payload
}

extension NotifyHandler {
    static var attached_wallet: NotifyHandler<AttachedWalletNotify> {
        .init()
    }
}

extension Notifications {
    static func attached_wallet(_ payload: WalletConnectURL) -> Notifications<AttachedWalletNotify> {
        .init(.init(payload: payload))
    }
}
