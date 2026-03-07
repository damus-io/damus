//
//  EventView.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI
import UIKit

enum EventViewKind {
    case small
    case normal
    case selected
    case title
    case subheadline
}

struct EventView: View {
    let event: NostrEvent
    let options: EventViewOptions
    let damus: DamusState
    let pubkey: Pubkey
    let highlightTerms: [String]

    init(damus: DamusState, event: NostrEvent, pubkey: Pubkey? = nil, options: EventViewOptions = [], highlightTerms: [String] = []) {
        self.event = event
        self.options = options
        self.damus = damus
        self.pubkey = pubkey ?? event.pubkey
        self.highlightTerms = highlightTerms
    }

    var body: some View {
        VStack {
            if event.known_kind == .boost {
                if let inner_ev = event.get_inner_event(cache: damus.events) {
                    RepostedEvent(damus: damus, event: event, inner_ev: inner_ev, options: options)
                } else if let target = event.repostTarget() {
                    // Inner event not in cache - load using relay hints from e tag (NIP-18)
                    EventLoaderView(damus_state: damus, event_id: target.noteId, relayHints: target.relayHints) { loaded_event in
                        RepostedEvent(damus: damus, event: event, inner_ev: loaded_event, options: options)
                    }
                } else {
                    EmptyView()
                }
            } else if event.known_kind == .zap {
                if let zap = damus.zaps.zaps[event.id] {
                    ZapEvent(damus: damus, zap: zap, is_top_zap: options.contains(.top_zap))
                } else {
                    EmptyView()
                }
            } else if event.known_kind == .longform {
                LongformPreview(state: damus, ev: event, options: options)
            } else if event.known_kind == .highlight {
                HighlightView(state: damus, event: event, options: options)
            } else {
                TextEvent(damus: damus, event: event, pubkey: pubkey, options: options, highlightTerms: highlightTerms)
                    //.padding([.top], 6)
            }
        }
    }
}

// blame the porn bots for this code
@MainActor
func should_blur_images(settings: UserSettingsStore, contacts: Contacts, ev: NostrEvent, our_pubkey: Pubkey, booster_pubkey: Pubkey? = nil) -> Bool {
    if settings.undistractMode {
        return true
    }
    
    if !settings.blur_images {
        return false
    }
    
    if ev.pubkey == our_pubkey {
        return false
    }
    if contacts.is_in_friendosphere(ev.pubkey) {
        return false
    }
    if let boost_key = booster_pubkey, contacts.is_in_friendosphere(boost_key) {
        return false
    }
    return true
}

// blame the porn bots for this code too
@MainActor
func should_blur_images(damus_state: DamusState, ev: NostrEvent) -> Bool {
    return should_blur_images(
        settings: damus_state.settings,
        contacts: damus_state.contacts,
        ev: ev,
        our_pubkey: damus_state.pubkey
    )
}

func format_relative_time(_ created_at: UInt32) -> String
{
    return time_ago_since(Date(timeIntervalSince1970: Double(created_at)))
}

func format_date(created_at: UInt32) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(created_at))
    return format_date(date: date)
}

func format_date(date: Date, time_style: DateFormatter.Style = .short) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.timeStyle = time_style
    dateFormatter.dateStyle = .short
    return dateFormatter.string(from: date)
}

func make_actionbar_model(ev: NoteId, damus: DamusState) -> ActionBarModel {
    let model = ActionBarModel.empty()
    Task { await model.update(damus: damus, evid: ev) }
    return model
}

/// Returns a Dynamic Type-aware font for the given event view size and user font multiplier.
func eventviewsize_to_font(_ size: EventViewKind, font_size: Double) -> Font {
    let baseSize: CGFloat
    let textStyle: UIFont.TextStyle

    switch size {
    case .small:
        baseSize = 12.0 * font_size
        textStyle = .caption1
    case .normal:
        baseSize = 17.0 * font_size
        textStyle = .body
    case .selected:
        baseSize = 21.0 * font_size
        textStyle = .title2
    case .title:
        baseSize = 24.0 * font_size
        textStyle = .title1
    case .subheadline:
        baseSize = 14.0 * font_size
        textStyle = .subheadline
    }

    let scaledUIFont = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: UIFont.systemFont(ofSize: baseSize))
    return Font(scaledUIFont)
}

func eventviewsize_to_uifont(_ size: EventViewKind) -> UIFont {
    switch size {
    case .small:
        return .preferredFont(forTextStyle: .body)
    case .normal:
        return .preferredFont(forTextStyle: .body)
    case .selected:
        return .preferredFont(forTextStyle: .title2)
    case .subheadline:
        return .preferredFont(forTextStyle: .subheadline)
    case .title:
        return .preferredFont(forTextStyle: .title1)
    }
}


struct EventView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            /*
            EventView(damus: test_damus_state(), event: NostrEvent(content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool", pubkey: "pk"), show_friend_icon: true, size: .small)
            EventView(damus: test_damus_state(), event: NostrEvent(content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool", pubkey: "pk"), show_friend_icon: true, size: .normal)
            EventView(damus: test_damus_state(), event: NostrEvent(content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool", pubkey: "pk"), show_friend_icon: true, size: .big)
            
             */

            EventView( damus: test_damus_state, event: test_note )

            EventView( damus: test_damus_state, event: test_longform_event.event, options: [.wide] )
        }
        .padding()
    }
}
