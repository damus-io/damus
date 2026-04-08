//
//  SpellCardView.swift
//  damus
//
//  Renders a kind:777 spell event as a tappable card in a timeline.
//

import SwiftUI

struct SpellCardBody: View {
    let spell: SpellEvent
    let state: DamusState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.purple)
                    .font(.title3)

                Text(spell.displayName)
                    .font(.headline)
                    .lineLimit(1)
            }

            if !spell.displayDescription.isEmpty && spell.displayDescription != spell.displayName {
                Text(spell.displayDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if !spell.kinds.isEmpty {
                    SpellBadge(
                        text: spell.kinds.count == 1
                            ? kindLabel(spell.kinds.first!)
                            : "\(spell.kinds.count) kinds"
                    )
                }

                if spell.requiresContacts {
                    SpellBadge(text: NSLocalizedString("Contacts", comment: "Badge indicating spell uses contact list"))
                }

                if let limit = spell.limit {
                    SpellBadge(text: String(format: NSLocalizedString("limit %d", comment: "Badge showing spell result limit"), limit))
                }

                if spell.since != nil {
                    SpellBadge(text: sinceLabel)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }

    private var sinceLabel: String {
        guard let since = spell.since else { return "" }
        switch since {
        case .relative(let rel):
            return "\(rel.amount)\(rel.unit.rawValue)"
        case .absolute:
            return NSLocalizedString("since date", comment: "Badge for absolute timestamp filter")
        case .now:
            return NSLocalizedString("now", comment: "Badge for now timestamp filter")
        }
    }

    private func kindLabel(_ kind: UInt32) -> String {
        switch kind {
        case 1: return "Notes"
        case 6: return "Reposts"
        case 7: return "Reactions"
        case 9735: return "Zaps"
        case 30023: return "Articles"
        case 1984: return "Reports"
        default: return "kind:\(kind)"
        }
    }
}

struct SpellBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.12))
            .foregroundColor(.purple)
            .clipShape(Capsule())
    }
}

struct SpellCardView: View {
    let state: DamusState
    let event: NostrEvent
    let options: EventViewOptions

    var body: some View {
        EventShell(state: state, event: event, options: options) {
            if let spell = SpellEvent.parse(from: event) {
                SpellCardBody(spell: spell, state: state)
                    .padding(.horizontal, 16)
            }
        }
    }
}
