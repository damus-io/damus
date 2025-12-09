//
//  NotificationService.swift
//  DamusNotificationService
//
//  Created by Daniel D’Aquino on 2023-11-10.
//

import Kingfisher
import ImageIO
import UserNotifications
import Foundation
import Intents

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    private func configureKingfisherCache() {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.DAMUS_APP_GROUP_IDENTIFIER) else {
            return
        }

        let cachePath = groupURL.appendingPathComponent(Constants.IMAGE_CACHE_DIRNAME)
        if let cache = try? ImageCache(name: "sharedCache", cacheDirectoryURL: cachePath) {
            KingfisherManager.shared.cache = cache
        }
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        configureKingfisherCache()

        self.contentHandler = contentHandler
        
        guard let nostr_event_json = request.content.userInfo["nostr_event"] as? String,
              let nostr_event = NdbNote.owned_from_json(json: nostr_event_json)
        else {
            // No nostr event detected. Just display the original notification
            contentHandler(request.content)
            return;
        }
        
        // Log that we got a push notification
        Log.debug("Got nostr event push notification from pubkey %s", for: .push_notifications, nostr_event.pubkey.hex())
        
        guard let state = NotificationExtensionState() else {
            Log.debug("Failed to open nostrdb", for: .push_notifications)

            // Something failed to initialize so let's go for the next best thing
            guard let improved_content = NotificationFormatter.shared.format_message(event: nostr_event) else {
                // We cannot format this nostr event. Suppress notification.
                contentHandler(UNNotificationContent())
                return
            }
            contentHandler(improved_content)
            return
        }

        let sender_profile = {
            let profile = state.profiles.lookup(id: nostr_event.pubkey)
            let picture = ((profile?.picture.map { URL(string: $0) }) ?? URL(string: robohash(nostr_event.pubkey)))!
            return ProfileBuf(picture: picture,
                                 name: profile?.name,
                         display_name: profile?.display_name,
                                nip05: profile?.nip05)
        }()
        let sender_pubkey = nostr_event.pubkey
        
        Task {

            // Don't show notification details that match mute list.
            // TODO: Remove this code block once we get notification suppression entitlement from Apple. It will be covered by the `guard should_display_notification` block
            if await state.mutelist_manager.is_event_muted(nostr_event) {
                // We cannot really suppress muted notifications until we have the notification supression entitlement.
                // The best we can do if we ever get those muted notifications (which we generally won't due to server-side processing) is to obscure the details
                let content = UNMutableNotificationContent()
                content.title = NSLocalizedString("Muted event", comment: "Title for a push notification which has been muted")
                content.body = NSLocalizedString("This is an event that has been muted according to your mute list rules. We cannot suppress this notification, but we obscured the details to respect your preferences", comment: "Description for a push notification which has been muted, and explanation that we cannot suppress it")
                content.sound = UNNotificationSound.default
                contentHandler(content)
                return
            }

            guard await should_display_notification(state: state, event: nostr_event, mode: .push) else {
                Log.debug("should_display_notification failed", for: .push_notifications)
                // We should not display notification for this event. Suppress notification.
                // contentHandler(UNNotificationContent())
                // TODO: We cannot really suppress until we have the notification supression entitlement. Show the raw notification
                contentHandler(request.content)
                return
            }

            guard let notification_object = generate_local_notification_object(ndb: state.ndb, from: nostr_event, state: state) else {
                Log.debug("generate_local_notification_object failed", for: .push_notifications)
                // We could not process this notification. Probably an unsupported nostr event kind. Suppress.
                // contentHandler(UNNotificationContent())
                // TODO: We cannot really suppress until we have the notification supression entitlement. Show the raw notification
                contentHandler(request.content)
                return
            }
        
            let sender_dn = DisplayName(name: sender_profile.name, display_name: sender_profile.display_name, pubkey: sender_pubkey)
            guard let (improvedContent, _) = await NotificationFormatter.shared.format_message(displayName: sender_dn.displayName, notify: notification_object, state: state) else {

                Log.debug("NotificationFormatter.format_message failed", for: .push_notifications)
                return
            }

            // Attach profile picture to notification.
            // UNNotificationAttachment requires a LOCAL file URL - remote URLs silently fail.
            // We must download the image first and save it to disk.
            if let localPictureURL = await download_image_for_notification(picture: sender_profile.picture) {
                do {
                    let attachment = try UNNotificationAttachment(
                        identifier: sender_profile.picture.absoluteString,
                        url: localPictureURL,
                        options: nil  // Let iOS infer the type from the file extension
                    )
                    improvedContent.attachments = [attachment]
                } catch {
                    Log.error("Failed to create notification attachment: %s", for: .push_notifications, error.localizedDescription)
                }
            }

            let kind = nostr_event.known_kind

            // these aren't supported yet
            if !(kind == .text || kind == .dm) {
                contentHandler(improvedContent)
                return
            }

            // rich communication notifications for kind1, dms, etc

            let message_intent = await message_intent_from_note(ndb: state.ndb,
                                                                sender_profile: sender_profile,
                                                                content: improvedContent.body,
                                                                note: nostr_event,
                                                                our_pubkey: state.keypair.pubkey)

            improvedContent.threadIdentifier = nostr_event.thread_id().hex()
            improvedContent.categoryIdentifier = "COMMUNICATION"

            let interaction = INInteraction(intent: message_intent, response: nil)
            interaction.direction = .incoming
            do {
                try await interaction.donate()
                let updated = try improvedContent.updating(from: message_intent)
                contentHandler(updated)
            } catch {
                Log.error("failed to donate interaction: %s", for: .push_notifications, error.localizedDescription)
                contentHandler(improvedContent)
            }
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}

struct ProfileBuf {
    let picture: URL
    let name: String?
    let display_name: String?
    let nip05: String?
}

func message_intent_from_note(ndb: Ndb, sender_profile: ProfileBuf, content: String, note: NdbNote, our_pubkey: Pubkey) async -> INSendMessageIntent {
    let sender_pk = note.pubkey
    let sender = await profile_to_inperson(name: sender_profile.name,
                                   display_name: sender_profile.display_name,
                                        picture: sender_profile.picture.absoluteString,
                                          nip05: sender_profile.nip05,
                                         pubkey: sender_pk,
                                     our_pubkey: our_pubkey)

    let conversationIdentifier = note.thread_id().hex()
    var recipients: [INPerson] = []
    var pks: [Pubkey] = []
    let meta = INSendMessageIntentDonationMetadata()

    // gather recipients
    if let recipient_note_id = note.direct_replies() {
        let replying_to_pk = ndb.lookup_note(recipient_note_id, borrow: { replying_to_note -> Pubkey? in
            switch replying_to_note {
            case .none: return nil
            case .some(let note): return note.pubkey
            }
        })
        if let replying_to_pk {
            meta.isReplyToCurrentUser = replying_to_pk == our_pubkey

            if replying_to_pk != sender_pk {
                // we push the actual person being replied to first
                pks.append(replying_to_pk)
            }
        }
    }

    let pubkeys = Array(note.referenced_pubkeys)
    meta.recipientCount = pubkeys.count
    if pubkeys.contains(sender_pk) {
        meta.recipientCount -= 1
    }

    for pk in pubkeys.prefix(3) {
        if pk == sender_pk || pks.contains(pk) {
            continue
        }

        if !meta.isReplyToCurrentUser && pk == our_pubkey {
            meta.mentionsCurrentUser = true
        }

        pks.append(pk)
    }

    for pk in pks {
        let recipient = await pubkey_to_inperson(ndb: ndb, pubkey: pk, our_pubkey: our_pubkey)
        recipients.append(recipient)
    }

    // we enable default formatting this way
    var groupName = INSpeakableString(spokenPhrase: "")

    // otherwise we just say its a DM
    if note.known_kind == .dm {
        groupName = INSpeakableString(spokenPhrase: "DM")
    }

    let intent = INSendMessageIntent(recipients: recipients,
                            outgoingMessageType: .outgoingMessageText,
                                        content: content,
                             speakableGroupName: groupName,
                         conversationIdentifier: conversationIdentifier,
                                    serviceName: "kind\(note.kind)",
                                         sender: sender,
                                    attachments: nil)
    intent.donationMetadata = meta

    // this is needed for recipients > 0
    if let img = sender.image {
        intent.setImage(img, forParameterNamed: \.speakableGroupName)
    }

    return intent
}

func pubkey_to_inperson(ndb: Ndb, pubkey: Pubkey, our_pubkey: Pubkey) async -> INPerson {
    let profile = ndb.lookup_profile(pubkey, borrow: { profileRecord in
        switch profileRecord {
        case .some(let pr): return pr.profile
        case .none: return nil
        }
    })
    let name = profile?.name
    let display_name = profile?.display_name
    let nip05 = profile?.nip05
    let picture = profile?.picture

    return await profile_to_inperson(name: name,
                             display_name: display_name,
                                  picture: picture,
                                    nip05: nip05,
                                   pubkey: pubkey,
                               our_pubkey: our_pubkey)
}

func fetch_pfp(picture: URL) async throws -> RetrieveImageResult {
    try await withCheckedThrowingContinuation { continuation in
        KingfisherManager.shared.retrieveImage(with: Kingfisher.ImageResource(downloadURL: picture)) { result in
            switch result {
            case .success(let img):
                continuation.resume(returning: img)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

func profile_to_inperson(name: String?, display_name: String?, picture: String?, nip05: String?, pubkey: Pubkey, our_pubkey: Pubkey) async -> INPerson {
    let npub = pubkey.npub
    let handle = INPersonHandle(value: npub, type: .unknown)
    var aliases: [INPersonHandle] = []

    if let nip05 {
        aliases.append(INPersonHandle(value: nip05, type: .emailAddress))
    }

    let nostrName = DisplayName(name: name, display_name: display_name, pubkey: pubkey)
    let nameComponents = nostrName.nameComponents()
    let displayName = nostrName.displayName
    let contactIdentifier = npub
    let customIdentifier = npub
    let suggestionType = INPersonSuggestionType.socialProfile

    var image: INImage? = nil

    if let picture,
       let url = URL(string: picture),
       let img = try? await fetch_pfp(picture: url),
       let imgdata = img.data()
    {
        image = INImage(imageData: imgdata)
    } else {
        Log.error("Failed to fetch pfp (%s) for %s", for: .push_notifications, picture ?? "nil", displayName)
    }

    let person = INPerson(personHandle: handle,
                        nameComponents: nameComponents,
                           displayName: displayName,
                                 image: image,
                     contactIdentifier: contactIdentifier,
                      customIdentifier: customIdentifier,
                                  isMe: pubkey == our_pubkey,
                        suggestionType: suggestionType
    )

    return person
}

func robohash(_ pk: Pubkey) -> String {
    return "https://robohash.org/" + pk.hex()
}

// MARK: - Notification Attachment Helpers

/// Downloads a profile picture and saves it to a local file for use as a notification attachment.
///
/// UNNotificationAttachment requires a local file URL - it cannot fetch remote images directly.
/// This function bridges that gap by:
/// 1. Using Kingfisher to download (or retrieve from cache) the image
/// 2. Saving the image data to a temporary file in the app group container
/// 3. Returning the local file URL suitable for UNNotificationAttachment
///
/// - Parameter picture: The remote URL of the profile picture to download
/// - Returns: A local file URL pointing to the downloaded image, or nil if download/save failed
func download_image_for_notification(picture: URL) async -> URL? {
    // Fetch the image using Kingfisher (handles caching automatically)
    guard let result = try? await fetch_pfp(picture: picture) else {
        Log.error("Failed to fetch profile picture for notification: %s", for: .push_notifications, picture.absoluteString)
        return nil
    }

    // Use Kingfisher's data() which preserves the original image format,
    // rather than re-encoding with pngData() which could break animated GIFs or increase file size
    guard let imageData = result.data() else {
        Log.error("Failed to get image data from fetch result", for: .push_notifications)
        return nil
    }

    // Save to a temporary file in the app group container.
    // Using app group ensures the notification extension has access to the file.
    guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.DAMUS_APP_GROUP_IDENTIFIER) else {
        Log.error("Failed to get app group container URL", for: .push_notifications)
        return nil
    }

    // Determine file extension from the original URL to preserve format
    let pathExtension = picture.pathExtension.isEmpty ? "jpg" : picture.pathExtension
    // Create a unique filename based on the URL hash to avoid collisions
    let filename = "notif_pfp_\(picture.absoluteString.hashValue).\(pathExtension)"
    let localURL = groupURL.appendingPathComponent(filename)

    do {
        try imageData.write(to: localURL)
        return localURL
    } catch {
        Log.error("Failed to write profile picture to local file: %s", for: .push_notifications, error.localizedDescription)
        return nil
    }
}


