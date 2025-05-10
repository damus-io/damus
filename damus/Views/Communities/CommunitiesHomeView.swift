//
//  CommunitiesHomeView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-09.
//

import SwiftUI

struct CommunitiesHomeView: View {
    let damus: DamusState
    
    var body: some View {
        List(content: {
            listView(id: .hashtag("bitcoin"))
            listView(id: .hashtag("linux"))
            listView(id: .hashtag("ux-design"))
        })
    }
    
    func listView(id: NIP73.ID.Value) -> some View {
        NavigationLink(value: Route.Community(id: id)) {
            HStack(spacing: 8) {
                SystemIconAvatar(system_name: "person.2.fill")
                VStack(alignment: .leading, spacing: 6) {
                    Text(id.displayName)
                        .bold()
                    Text(id.kindDisplayName)
                }
            }
        }
    }
}

#Preview {
    CommunitiesHomeView(damus: test_damus_state)
}
