//
//  EventLoaderView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-27.
//

import SwiftUI

/// This view handles the loading logic for Nostr events, so that you can easily use views that require `NostrEvent`, even if you only have a `NoteId`.
///
/// Supports NIP-01/NIP-10 relay hints to fetch events from relays not in the user's pool.
struct EventLoaderView<Content: View>: View {
    let damus_state: DamusState
    let event_id: NoteId
    let relayHints: [RelayURL]
    @State var event: NostrEvent?
    @State private var eventNotFound: Bool = false
    @State private var isReloading: Bool = false
    let content: (NostrEvent) -> Content

    /// Creates an event loader view.
    ///
    /// - Parameters:
    ///   - damus_state: The app's shared state.
    ///   - event_id: The ID of the event to load.
    ///   - relayHints: Optional relay URLs where the event may be found (per NIP-01/NIP-10).
    ///   - content: A view builder that receives the loaded event.
    init(damus_state: DamusState, event_id: NoteId, relayHints: [RelayURL] = [], @ViewBuilder content: @escaping (NostrEvent) -> Content) {
        self.damus_state = damus_state
        self.event_id = event_id
        self.relayHints = relayHints
        self.content = content
        let event = damus_state.events.lookup(event_id)
        _event = State(initialValue: event)
    }

    /// Loads the event from nostrdb or the network using relay hints or the default relay pool.
    ///
    /// This method attempts to fetch the event via `nostrNetwork.reader.lookup`, which first checks
    /// nostrdb for a cached copy, then queries the network if not found locally. Network queries use
    /// either the specified relay hints (if provided) or the user's relay pool (if no hints are provided).
    /// On success, sets `event` and clears `eventNotFound`. On failure, sets `eventNotFound` to true.
    ///
    /// Side effects:
    /// - Updates `event` with the fetched event on success
    /// - Updates `eventNotFound` flag based on the result
    /// - Logs debug information when relay hints are used
    func load() async {
        let targetRelays = relayHints.isEmpty ? nil : relayHints
        #if DEBUG
        if let targetRelays, !targetRelays.isEmpty {
            print("[relay-hints] EventLoaderView: Loading event \(event_id.hex().prefix(8))... with \(targetRelays.count) relay hint(s): \(targetRelays.map { $0.absoluteString })")
        }
        #endif
        let lender = try? await damus_state.nostrNetwork.reader.lookup(noteId: self.event_id, to: targetRelays)
        if let foundEvent = lender?.justGetACopy() {
            event = foundEvent
            eventNotFound = false
        }
        else {
            // Handle nil case: event was not found
            eventNotFound = true
        }
        #if DEBUG
        if let targetRelays, !targetRelays.isEmpty {
            print("[relay-hints] EventLoaderView: Event \(event_id.hex().prefix(8))... loaded: \(event != nil)")
        }
        #endif
    }
    
    /// Retries loading the event and displays loading state during the operation.
    ///
    /// This method sets the `isReloading` flag to true, calls `load()`, and resets
    /// the flag when complete. It is typically triggered by user action (e.g., "Try Again" button).
    ///
    /// Side effects:
    /// - Updates `isReloading` to true during the operation
    /// - Delegates to `load()`, which updates `event` and `eventNotFound`
    /// - Resets `isReloading` to false after completion
    func retry() async {
        isReloading = true
        await load()
        isReloading = false
    }
    
    var body: some View {
        VStack { 
            if let event {
                self.content(event)
            } else if eventNotFound {
                not_found
            } else {
                ProgressView().padding()
            }
        }
        .task {
            guard event == nil else {
                return
            }
            await self.load()
        }
    }
    
    var not_found: some View {
        VStack(spacing: 0) {
            LoadableNostrEventView.SomethingWrong(
                imageSystemName: "questionmark.app",
                heading: NSLocalizedString("Note not found", comment: "Heading for the event loader view in a not found error state."),
                description: NSLocalizedString("This note may have been deleted, or it might not be available on the relays you're connected to.", comment: "Text for the event loader view when it is unable to find the note the user is looking for"),
                advice: NSLocalizedString("Try checking your internet connection, expanding your relay list, or contacting the person who quoted this note.", comment: "Tips on what to do if a quoted note cannot be found.")
            )
            
            Button(action: {
                Task {
                    await retry()
                }
            }) {
                HStack {
                    if !isReloading {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again", comment: "Button label to retry loading a note that was not found")
                    }
                    else {
                        ProgressView()
                        Text("Retrying…", comment: "Button label for the retry-in-progress state when loading a note")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.secondary)
                .cornerRadius(10)
            }
            .disabled(isReloading)
            .opacity(isReloading ? 0.6 : 1.0)
            .padding(.bottom, 20)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}


struct EventLoaderView_Previews: PreviewProvider {
    static var previews: some View {
        EventLoaderView(damus_state: test_damus_state, event_id: test_note.id) { event in
            EventView(damus: test_damus_state, event: event)
        }
    }
}
