//
//  DamusViewModel.swift
//  damus
//
//  Created by Sam DuBois on 12/21/22.
//

import SwiftUI

class DamusViewModel: ObservableObject {
    @Published var status: String = "Not connected"
    @Published var active_sheet: Sheets? = nil
    @Published var damus_state: DamusState? = nil
    @Published var selected_timeline: Timeline? = .home
    @Published var is_thread_open: Bool = false
    @Published var is_profile_open: Bool = false
    @Published var event: NostrEvent? = nil
    @Published var active_profile: String? = nil
    @Published var active_search: NostrFilter? = nil
    @Published var active_event_id: String? = nil
    @Published var profile_open: Bool = false
    @Published var thread_open: Bool = false
    @Published var search_open: Bool = false
    @Published var filter_state : FilterState = .posts_and_replies
}
