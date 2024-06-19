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
