import Foundation

struct UnfavoriteNotify: Notify {
    typealias Payload = Pubkey
    var payload: Payload
}

extension NotifyHandler {
    static var unfavorite: NotifyHandler<UnfavoriteNotify> {
        .init()
    }
}

extension Notifications {
    static func unfavorite(_ pubkey: Pubkey) -> Notifications<UnfavoriteNotify> {
        .init(.init(payload: pubkey))
    }
} 
