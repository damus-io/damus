enum ContactCardNotifyType {
    case favorite(Pubkey)
    case unfavorite(Pubkey)
    case favoritesUpdated
}

struct ContactCardNotify: Notify {
    typealias Payload = ContactCardNotifyType
    var payload: Payload
}

extension NotifyHandler {
    static var contactCard: NotifyHandler<ContactCardNotify> {
        NotifyHandler<ContactCardNotify>()
    }
}

extension Notifications {
    static func contactCard(_ type: ContactCardNotifyType) -> Notifications<ContactCardNotify> {
        .init(.init(payload: type))
    }
}
