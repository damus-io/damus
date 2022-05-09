//
//  SearchView.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import SwiftUI

struct SearchView: View {
    let appstate: DamusState
    @StateObject var search: SearchModel
    
    var body: some View {
        TimelineView(events: $search.events, damus: appstate)
        .padding([.leading, .trailing], 6)
        .onAppear() {
            search.subscribe()
        }
        .onDisappear() {
            search.unsubscribe()
        }
    }
}

/*
struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        SearchView()
    }
}
 */
