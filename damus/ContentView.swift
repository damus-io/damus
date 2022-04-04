//
//  ContentView.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import Starscream

struct EventView: View {
    let event: NostrEvent

    var body: some View {
        VStack {
            Text(String(event.pubkey.prefix(16)))
                .bold()
                .onTapGesture {
                    UIPasteboard.general.string = event.pubkey
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(event.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        }
    }
}

enum Sheets: Identifiable {
    case post

    var id: String {
        switch self {
        case .post:
            return "post"
        }
    }
}

struct ContentView: View {
    @State var status: String = "Not connected"
    @State var sub_id: String? = nil
    @State var active_sheet: Sheets? = nil
    @State var events: [NostrEvent] = []
    @State var has_events: [String: Bool] = [:]
    @State var loading: Bool = true
    @State var connection: NostrConnection? = nil

    var MainContent: some View {
        ScrollView {
            ForEach(events.reversed(), id: \.id) {
                EventView(event: $0)
            }
        }
    }

    var body: some View {
        ZStack {
            MainContent
                .padding()
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    PostButton {
                        self.active_sheet = .post
                    }
                }
            }
        }
        .onAppear() {
            self.connect()
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .post:
                PostView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .post)) { obj in
            let post = obj.object as! NostrPost
            print("post \(post.content)")
        }
    }

    func connect() {
        let url = URL(string: "wss://nostr.bitcoiner.social")!
        let conn = NostrConnection(url: url, handleEvent: handle_event)
        conn.connect()
        self.connection = conn
    }

    func handle_event(conn_event: NostrConnectionEvent) {
        switch conn_event {
        case .ws_event(let ev):
            switch ev {
            case .connected:
                let now = Int64(Date().timeIntervalSince1970)
                let yesterday = now - 24 * 60 * 60
                let filter = NostrFilter.filter_since(yesterday)
                let sub_id = self.sub_id ?? UUID().description
                if self.sub_id != sub_id {
                    self.sub_id = sub_id
                }
                print("subscribing to \(sub_id)")
                self.connection?.send(filter, sub_id: sub_id)
            case .cancelled:
                self.connection?.connect()
            default:
                break
            }
            print("ws_event \(ev)")

        case .nostr_event(let ev):
            switch ev {
            case .event(_, let ev):
                if self.loading {
                    self.loading = false
                }
                self.sub_id = sub_id
                if ev.kind == 1 && !(has_events[ev.id] ?? false) {
                    has_events[ev.id] = true
                    self.events.append(ev)
                }
            case .notice(let msg):
                print(msg)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

func PostButton(action: @escaping () -> ()) -> some View {
    return Button(action: action, label: {
        Text("+")
            .font(.system(.largeTitle))
            .frame(width: 57, height: 50)
            .foregroundColor(Color.white)
            .padding(.bottom, 7)
    })
    .background(Color.blue)
    .cornerRadius(38.5)
    .padding()
    .shadow(color: Color.black.opacity(0.3),
            radius: 3,
            x: 3,
            y: 3)
}

