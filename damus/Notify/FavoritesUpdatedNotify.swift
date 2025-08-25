import Foundation

struct FavoritesUpdatedNotify: Notify {
    typealias Payload = Void
    var payload: Payload
}

extension NotifyHandler {
    static var favorites_updated: NotifyHandler<FavoritesUpdatedNotify> {
        .init()
    }
}

extension Notifications {
    static var favorites_updated: Notifications<FavoritesUpdatedNotify> {
        .init(.init(payload: ()))
    }
}
