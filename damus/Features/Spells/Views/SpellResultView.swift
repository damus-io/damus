//
//  SpellResultView.swift
//  damus
//
//  Displays spell feed results with referenced event resolution.
//  When a spell returns zaps, reactions, or reposts, this view
//  loads and displays the referenced event as primary content
//  with action context.
//

import SwiftUI

/// The extracted reference from a spell feed result event.
///
/// When a spell returns events like zaps or reactions, we need
/// to resolve the referenced event and display it as primary content.
enum SpellResultReference: Equatable {
    /// A reaction (kind:7) referencing a note.
    case reaction(referencedNoteId: NoteId, reactorPubkey: Pubkey, emoji: String)
    /// A zap receipt (kind:9735) referencing a note.
    case zap(referencedNoteId: NoteId, senderPubkey: Pubkey, amountMsats: Int64?)
    /// Not a reference type — display the event directly.
    case directEvent

    /// Extracts the reference from a spell result event.
    static func extract(from event: NostrEvent) -> SpellResultReference {
        switch event.known_kind {
        case .like:
            guard let refId = event.referenced_ids.last else {
                return .directEvent
            }
            let emoji = to_reaction_emoji(ev: event) ?? "❤️"
            return .reaction(referencedNoteId: refId, reactorPubkey: event.pubkey, emoji: emoji)

        case .zap:
            guard let refId = event.referenced_ids.first else {
                return .directEvent
            }
            let senderPubkey: Pubkey
            if let zapRequest = get_zap_request(event) {
                senderPubkey = zapRequest.pubkey
            } else {
                senderPubkey = event.pubkey
            }
            let amountMsats = extractZapAmount(from: event)
            return .zap(referencedNoteId: refId, senderPubkey: senderPubkey, amountMsats: amountMsats)

        default:
            return .directEvent
        }
    }

    /// Extracts the zap amount in millisatoshis from the bolt11 tag.
    private static func extractZapAmount(from event: NostrEvent) -> Int64? {
        guard let bolt11String = event_tag(event, name: "bolt11"),
              let invoice = decode_bolt11(bolt11String),
              case .specific(let msats) = invoice.amount else {
            return nil
        }
        return msats
    }
}

/// Displays a spell feed result event, resolving referenced events
/// for kinds that are inherently references (reactions, zaps).
///
/// For kind:7 (reactions) and kind:9735 (zaps), shows the referenced
/// event as primary content with a context header describing the action.
/// For all other kinds, delegates to the standard EventView.
struct SpellResultView: View {
    let damus: DamusState
    let event: NostrEvent
    let options: EventViewOptions

    var body: some View {
        let ref = SpellResultReference.extract(from: event)
        switch ref {
        case .reaction(let refId, let reactorPubkey, let emoji):
            VStack(alignment: .leading, spacing: 0) {
                let name = event_author_name(profiles: damus.profiles, pubkey: reactorPubkey)
                let label = String(format: NSLocalizedString("%@ reacted", comment: "Text in spell feed indicating who reacted to a note"), name)
                spellActionHeader(pubkey: reactorPubkey, icon: emoji, label: label)
                    .padding(.horizontal)
                referencedEventContent(refId: refId)
            }

        case .zap(let refId, let senderPubkey, let amountMsats):
            VStack(alignment: .leading, spacing: 0) {
                let name = event_author_name(profiles: damus.profiles, pubkey: senderPubkey)
                let label: String = {
                    if let msats = amountMsats {
                        return String(format: NSLocalizedString("%@ zapped %@", comment: "Text in spell feed showing who zapped and the amount"), name, format_msats(msats))
                    }
                    return String(format: NSLocalizedString("%@ zapped", comment: "Text in spell feed indicating who zapped a note"), name)
                }()
                spellActionHeader(pubkey: senderPubkey, icon: "⚡", label: label)
                    .padding(.horizontal)
                referencedEventContent(refId: refId)
            }

        case .directEvent:
            EventView(damus: damus, event: event, options: options)
        }
    }

    // MARK: - Shared

    /// Loads and displays a referenced event by its ID.
    @ViewBuilder
    private func referencedEventContent(refId: NoteId) -> some View {
        EventLoaderView(damus_state: damus, event_id: refId) { loadedEvent in
            EventMutingContainerView(
                damus_state: damus,
                event: loadedEvent,
                muteBox: { shown, reason in
                    AnyView(
                        EventMutedBoxView(shown: shown, reason: reason)
                            .padding(.horizontal, 5)
                    )
                }
            ) {
                EventView(damus: damus, event: loadedEvent, options: options.union(.wide))
            }
        }
    }

    /// A context header showing who performed an action on a referenced event.
    private func spellActionHeader(pubkey: Pubkey, icon: String, label: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(icon)
                .font(.subheadline)

            ProfilePicView(
                pubkey: pubkey,
                size: eventview_pfp_size(.small),
                highlight: .none,
                profiles: damus.profiles,
                disable_animation: damus.settings.disable_animation,
                damusState: damus
            )

            Text(label)
                .font(.subheadline)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

