//
//  EventView.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI

enum EventViewKind {
    case small
    case normal
    case selected
}

struct EventView: View {
    let event: NostrEvent
    let options: EventViewOptions
    let damus: DamusState
    let pubkey: String

    @EnvironmentObject var action_bar: ActionBarModel

    init(damus: DamusState, event: NostrEvent, pubkey: String? = nil, options: EventViewOptions = []) {
        self.event = event
        self.options = options
        self.damus = damus
        self.pubkey = pubkey ?? event.pubkey
    }

    var body: some View {
        VStack {
            if event.known_kind == .boost {
                if let inner_ev = event.inner_event {
                    RepostedEvent(damus: damus, event: event, inner_ev: inner_ev, options: options)
                } else {
                    EmptyView()
                }
            } else if event.known_kind == .zap {
                if let zap = damus.zaps.zaps[event.id] {
                    ZapEvent(damus: damus, zap: zap)
                } else {
                    EmptyView()
                }
            } else {
                TextEvent(damus: damus, event: event, pubkey: pubkey, options: options)
                    //.padding([.top], 6)
            }
        }
    }
}

// blame the porn bots for this code
func should_show_images(settings: UserSettingsStore, contacts: Contacts, ev: NostrEvent, our_pubkey: String, booster_pubkey: String? = nil) -> Bool {
    if settings.always_show_images {
        return true
    }
    
    if ev.pubkey == our_pubkey {
        return true
    }
    if contacts.is_in_friendosphere(ev.pubkey) {
        return true
    }
    if let boost_key = booster_pubkey, contacts.is_in_friendosphere(boost_key) {
        return true
    }
    return false
}

func event_validity_color(_ validation: ValidationResult) -> some View {
    Group {
        switch validation {
        case .ok:
            EmptyView()
        case .bad_id:
            Color.orange.opacity(0.4)
        case .bad_sig:
            Color.red.opacity(0.4)
        }
    }
}

extension View {
    func pubkey_context_menu(bech32_pubkey: String) -> some View {
        return self.contextMenu {
            Button {
                    UIPasteboard.general.string = bech32_pubkey
            } label: {
                Label(NSLocalizedString("Copy Account ID", comment: "Context menu option for copying the ID of the account that created the note."), systemImage: "doc.on.doc")
            }
        }
    }
    
    func event_context_menu(_ event: NostrEvent, keypair: Keypair, target_pubkey: String, bookmarks: BookmarksManager) -> some View {
        return self.contextMenu {
            EventMenuContext(event: event, keypair: keypair, target_pubkey: target_pubkey, bookmarks: bookmarks)
        }

    }
}

func format_relative_time(_ created_at: Int64) -> String
{
    return time_ago_since(Date(timeIntervalSince1970: Double(created_at)))
}

func format_date(_ created_at: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(created_at))
    let dateFormatter = DateFormatter()
    dateFormatter.timeStyle = .short
    dateFormatter.dateStyle = .short
    return dateFormatter.string(from: date)
}

func make_actionbar_model(ev: String, damus: DamusState) -> ActionBarModel {
    let model = ActionBarModel.empty()
    model.update(damus: damus, evid: ev)
    return model
}

func eventviewsize_to_font(_ size: EventViewKind) -> Font {
    switch size {
    case .small:
        return .body
    case .normal:
        return .body
    case .selected:
        return .custom("selected", size: 21.0)
    }
}

func eventviewsize_to_uifont(_ size: EventViewKind) -> UIFont {
    switch size {
    case .small:
        return .preferredFont(forTextStyle: .body)
    case .normal:
        return .preferredFont(forTextStyle: .body)
    case .selected:
        return .preferredFont(forTextStyle: .title2)
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
            EventView( damus: test_damus_state(), event: test_event )
        }
        .padding()
    }
}

let test_event =
        NostrEvent(
            content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jpg cool",
            pubkey: "pk",
            createdAt: Int64(Date().timeIntervalSince1970 - 100)
        )
