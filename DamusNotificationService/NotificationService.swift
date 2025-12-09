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
import CryptoKit
import UniformTypeIdentifiers

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

        // Clean up old notification profile pictures to prevent disk space accumulation.
        // This runs on each notification which is frequent enough to keep the cache tidy.
        cleanup_old_notification_images()

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

        // Look up sender's profile from the shared Ndb database.
        // If the profile is not found (nil), DisplayName will fall back to an abbreviated
        // bech32 pubkey (e.g., "npub1abc:xyz"). This happens when:
        // - The user has never been viewed in the main app
        // - The profile metadata hasn't been fetched from relays yet
        // - The database isn't properly synced between main app and extension
        let sender_profile = {
            let profile = state.profiles.lookup(id: nostr_event.pubkey)
            if profile == nil {
                Log.debug("Profile not found in database for pubkey %s - will display abbreviated bech32", for: .push_notifications, nostr_event.pubkey.npub)
            }
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

/// Subdirectory within the app group container for notification profile pictures.
/// Using a dedicated folder avoids enumerating the entire app group container during cleanup.
private let NOTIFICATION_PFP_DIRNAME = "notification_pfp"

/// Cleans up old notification profile picture files from the dedicated subdirectory.
/// Call this periodically to prevent disk space accumulation.
func cleanup_old_notification_images() {
    guard let pfpDirectory = notification_pfp_directory() else {
        return
    }

    let fileManager = FileManager.default
    guard let contents = try? fileManager.contentsOfDirectory(at: pfpDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
        return
    }

    let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago

    for fileURL in contents {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let creationDate = attributes[.creationDate] as? Date,
              creationDate < cutoffDate else {
            continue
        }

        try? fileManager.removeItem(at: fileURL)
    }
}

/// Returns the dedicated directory for notification profile pictures, creating it if needed.
private func notification_pfp_directory() -> URL? {
    guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.DAMUS_APP_GROUP_IDENTIFIER) else {
        return nil
    }

    let pfpDirectory = groupURL.appendingPathComponent(NOTIFICATION_PFP_DIRNAME)

    // Create directory if it doesn't exist
    if !FileManager.default.fileExists(atPath: pfpDirectory.path) {
        try? FileManager.default.createDirectory(at: pfpDirectory, withIntermediateDirectories: true)
    }

    return pfpDirectory
}

/// Downloads a profile picture and saves it to a local file for use as a notification attachment.
///
/// UNNotificationAttachment requires a local file URL - it cannot fetch remote images directly.
/// This function bridges that gap by:
/// 1. Using Kingfisher to download (or retrieve from cache) the image
/// 2. Detecting the actual image type from the data (not relying on URL extension)
/// 3. Saving the image data to a dedicated subdirectory in the app group container
/// 4. Returning the local file URL suitable for UNNotificationAttachment
///
/// The filename uses a stable SHA256 hash of the URL, so the same image URL will always
/// map to the same file. This enables reuse across notification service extension launches
/// and reduces disk churn.
///
/// - Parameter picture: The remote URL of the profile picture to download
/// - Returns: A local file URL pointing to the downloaded image, or nil if download/save failed
func download_image_for_notification(picture: URL) async -> URL? {
    guard let pfpDirectory = notification_pfp_directory() else {
        Log.error("Failed to get notification PFP directory", for: .push_notifications)
        return nil
    }

    // Generate stable filename from URL using SHA256 (not hashValue, which varies per process)
    let urlHash = stable_hash_for_url(picture)

    // Check if we already have this image cached (reuse across extension launches)
    // Validate the cached file is readable as an image to avoid reusing corrupt/zero-byte files
    let existingFiles = try? FileManager.default.contentsOfDirectory(at: pfpDirectory, includingPropertiesForKeys: nil)
    if let existingFile = existingFiles?.first(where: { $0.lastPathComponent.hasPrefix(urlHash) }),
       is_valid_image_file(existingFile) {
        return existingFile
    }

    // Fetch the image using Kingfisher (handles its own caching)
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

    // Detect actual image type from data using ImageIO, not URL extension.
    // This handles extension-less URLs and servers that serve different formats.
    let fileExtension = detect_image_extension(from: imageData) ?? "jpg"
    let filename = "\(urlHash).\(fileExtension)"
    let localURL = pfpDirectory.appendingPathComponent(filename)

    do {
        try imageData.write(to: localURL)
        return localURL
    } catch {
        Log.error("Failed to write profile picture to local file: %s", for: .push_notifications, error.localizedDescription)
        return nil
    }
}

/// Generates a stable hash string for a URL using SHA256.
/// Unlike Swift's hashValue, this is consistent across process launches.
private func stable_hash_for_url(_ url: URL) -> String {
    let data = Data(url.absoluteString.utf8)
    let hash = SHA256.hash(data: data)
    // Use first 16 bytes (32 hex chars) for reasonable uniqueness without excessive length
    return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
}

/// Detects the image format from raw data and returns the appropriate file extension.
/// Uses ImageIO's CGImageSource to inspect the actual image data, not the URL.
private func detect_image_extension(from data: Data) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let uti = CGImageSourceGetType(source) else {
        return nil
    }

    // Convert UTI to file extension using UniformTypeIdentifiers
    if let utType = UTType(uti as String),
       let preferredExtension = utType.preferredFilenameExtension {
        return preferredExtension
    }

    // Fallback: map common UTIs manually
    let utiString = uti as String
    switch utiString {
    case "public.jpeg": return "jpg"
    case "public.png": return "png"
    case "com.compuserve.gif": return "gif"
    case "public.heic": return "heic"
    case "org.webmproject.webp": return "webp"
    default: return nil
    }
}

/// Validates that a file exists and contains a readable image.
/// Uses ImageIO to verify the file is not corrupt or zero-byte.
private func is_valid_image_file(_ url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return false
    }
    // Check that ImageIO can determine the image type (implies valid header)
    return CGImageSourceGetType(source) != nil
}
