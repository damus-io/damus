struct FavoriteNotify: Notify {
    typealias Payload = Void
    var payload: Void
}

extension NotifyHandler {
    static var favoriteUpdated: NotifyHandler<FavoriteNotify> {
        .init()
    }
}

extension Notifications {
    static func favoriteUpdated() -> Notifications<FavoriteNotify> {
        .init(.init(payload: ()))
    }
}
