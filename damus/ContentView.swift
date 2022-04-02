//
//  ContentView.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import Starscream

struct ContentView: View {
    @State var status: String = "Not connected"
    @State var events: [NostrEvent] = []
    @State var connection: NostrConnection? = nil
    
    var body: some View {
        ForEach(events, id: \.id) {
            Text($0.content)
                .padding()
        }
        .onAppear() {
            let url = URL(string: "wss://nostr.bitcoiner.social")!
            let conn = NostrConnection(url: url, handleEvent: handle_event)
            conn.connect()
            self.connection = conn
        }
    }
    
    func handle_event(conn_event: NostrConnectionEvent) {
        
        switch conn_event {
        case .ws_event(let ev):
            if case .connected = ev {
                self.connection?.send(NostrFilter.filter_since(1648851447))
            }
            print("ws_event \(ev)")
        case .nostr_event(let ev):
            switch ev {
            case .event(_, let ev):
                self.events.append(ev)
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
