//
//  MutelistView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct MutelistView: View {
    let damus_state: DamusState
    @State var show_add_muteitem: Bool = false

    @State var users: [MuteItem] = []
    @State var hashtags: [MuteItem] = []
    @State var threads: [MuteItem] = []
    @State var words: [MuteItem] = []
    
    @State var new_text: String = ""

    func RemoveAction(item: MuteItem) -> some View {
        Button {
            guard let mutelist = damus_state.mutelist_manager.event,
                  let keypair = damus_state.keypair.to_full(),
                  let new_ev = remove_from_mutelist(keypair: keypair,
                                                    prev: mutelist,
                                                    to_remove: item)
            else {
                return
            }

            damus_state.mutelist_manager.set_mutelist(new_ev)
            damus_state.nostrNetwork.postbox.send(new_ev)
            updateMuteItems()
        } label: {
            Label(NSLocalizedString("Delete", comment: "Button to remove a user from their mutelist."), image: "delete")
        }
        .tint(.red)
    }

    func updateMuteItems() {
        users = Array(damus_state.mutelist_manager.users)
        hashtags = Array(damus_state.mutelist_manager.hashtags)
        threads = Array(damus_state.mutelist_manager.threads)
        words = Array(damus_state.mutelist_manager.words)
    }

    var body: some View {
        List {
            Section(NSLocalizedString("Hashtags", comment: "Section header title for a list of hashtags that are muted.")) {
                ForEach(hashtags, id: \.self) { item in
                    if case let MuteItem.hashtag(hashtag, _) = item {
                        MuteItemRow(item: item) {
                            Text(verbatim: "#\(hashtag.hashtag)")
                        }
                        .id(hashtag.hashtag)
                        .swipeActions {
                            RemoveAction(item: .hashtag(hashtag, nil))
                        }
                        .onTapGesture {
                            damus_state.nav.push(route: Route.Search(search: SearchModel.init(state: damus_state, search: NostrFilter(hashtag: [hashtag.hashtag]))))
                        }
                    }
                }
            }
            Section(NSLocalizedString("Words", comment: "Section header title for a list of words that are muted.")) {
                ForEach(words, id: \.self) { item in
                    if case let MuteItem.word(word, _) = item {
                        MuteItemRow(item: item) {
                            Text(word)
                        }
                        .id(word)
                        .swipeActions {
                            RemoveAction(item: .word(word, nil))
                        }
                    }
                }
            }
            Section(NSLocalizedString("Threads", comment: "Section header title for a list of threads that are muted.")) {
                ForEach(threads, id: \.self) { item in
                    if case let MuteItem.thread(note_id, _) = item {
                        if let event = damus_state.events.lookup(note_id) {
                            MuteItemRow(item: item) {
                                EventView(damus: damus_state, event: event)
                            }
                            .id(note_id.hex())
                            .swipeActions {
                                RemoveAction(item: .thread(note_id, nil))
                            }
                        } else {
                            Text("Error retrieving muted event", comment: "Text for an item that application failed to retrieve the muted event for.")
                        }
                    }
                }
            }
            Section(
                header: Text(NSLocalizedString("Users", comment: "Section header title for a list of muted users.")),
                footer: Text("").padding(.bottom, 10 + tabHeight + getSafeAreaBottom())
            ) {
                ForEach(users, id: \.self) { user in
                    if case let MuteItem.user(pubkey, _) = user {
                        MuteItemRow(item: user) {
                            UserViewRow(damus_state: damus_state, pubkey: pubkey)
                        }
                        .id(pubkey)
                        .swipeActions {
                            RemoveAction(item: .user(pubkey, nil))
                        }
                        .onTapGesture {
                            damus_state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Muted", comment: "Navigation title of view to see list of muted users & phrases."))
        .onAppear {
            updateMuteItems()
        }
        .onReceive(handle_notify(.new_mutes)) { new_mutes in
            updateMuteItems()
        }
        .onReceive(handle_notify(.new_unmutes)) { new_unmutes in
            updateMuteItems()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    self.show_add_muteitem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $show_add_muteitem, onDismiss: { self.show_add_muteitem = false }) {
            AddMuteItemView(state: damus_state, new_text: $new_text)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Displays a mute item with an optional expiration indicator
struct MuteItemRow<Content: View>: View {
    let item: MuteItem
    @ViewBuilder let content: () -> Content

    @State private var timeRemaining: String?
    @State private var timer: Timer?

    var body: some View {
        HStack {
            content()

            Spacer()

            if let timeRemaining = timeRemaining {
                Text(timeRemaining)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .onAppear {
            updateTimeRemaining()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func updateTimeRemaining() {
        let expirationDate: Date? = {
            switch item {
            case .user(_, let date):
                return date
            case .hashtag(_, let date):
                return date
            case .word(_, let date):
                return date
            case .thread(_, let date):
                return date
            }
        }()

        guard let expirationDate = expirationDate else {
            timeRemaining = nil
            return
        }

        // Check if expired
        if expirationDate <= Date() {
            timeRemaining = NSLocalizedString("Expired", comment: "Label indicating a temporary mute has expired")
            return
        }

        timeRemaining = formatTimeRemaining(until: expirationDate)
    }

    private func formatTimeRemaining(until date: Date) -> String {
        let interval = date.timeIntervalSince(Date())

        if interval < 0 {
            return NSLocalizedString("Expired", comment: "Label indicating a temporary mute has expired")
        }

        // Round up to the nearest hour
        let totalHours = Int(ceil(interval / 3600.0))
        let days = totalHours / 24
        let remainingHours = totalHours % 24

        if days > 0 {
            if remainingHours > 0 {
                return String(format: NSLocalizedString("%dd %dh", comment: "Time remaining format: days and hours"), days, remainingHours)
            }
            return String(format: NSLocalizedString("%dd", comment: "Time remaining format: days only"), days)
        } else {
            return String(format: NSLocalizedString("%dh", comment: "Time remaining format: hours only"), totalHours)
        }
    }

    private func startTimer() {
        // Update every minute for temporary mutes
        guard timeRemaining != nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            updateTimeRemaining()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct MutelistView_Previews: PreviewProvider {
    static var previews: some View {
        MutelistView(damus_state: test_damus_state)
    }
}
