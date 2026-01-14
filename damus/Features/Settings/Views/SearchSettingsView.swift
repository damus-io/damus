//
//  SearchSettingsView.swift
//  damus
//
//  Created by Ben Weeks on 29/05/2023.
//

import SwiftUI

struct SearchSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text("Spam", comment: "Section header for Universe/Search spam")) {
                Toggle(NSLocalizedString("View multiple events per user", comment: "Setting to only see 1 event per user (npub) in the search/universe"), isOn: $settings.multiple_events_per_pubkey)
                    .toggleStyle(.switch)
            }

            Section(header: Text("Privacy", comment: "Section header for search privacy settings")) {
                Toggle(NSLocalizedString("Enable relay search (NIP-50)", comment: "Setting to enable NIP-50 relay search which may expose search queries to relay operators"), isOn: $settings.enable_nip50_relay_search)
                    .toggleStyle(.switch)
                Text("When enabled, search queries are sent to relays. This may expose your search terms to relay operators.", comment: "Description for NIP-50 relay search privacy setting")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(NSLocalizedString("Search/Universe", comment: "Navigation title for universe/search settings."))
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
}

struct SearchSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SearchSettingsView(settings: UserSettingsStore())
    }
}
