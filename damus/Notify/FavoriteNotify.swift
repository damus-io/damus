import Foundation

struct FavoriteNotify: Notify {
    typealias Payload = Pubkey
    var payload: Payload
}

extension NotifyHandler {
    static var favorite: NotifyHandler<FavoriteNotify> {
        NotifyHandler<FavoriteNotify>()
    }
}

extension Notifications {
    static func favorite(_ pubkey: Pubkey) -> Notifications<FavoriteNotify> {
        .init(.init(payload: pubkey))
    }
} 
