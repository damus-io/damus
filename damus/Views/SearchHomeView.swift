//
//  SearchHomeView.swift
//  damus
//
//  Created by William Casarin on 2022-05-19.
//

import SwiftUI
import CryptoKit

struct SearchHomeView: View {
    let damus_state: DamusState
    @StateObject var model: SearchHomeModel
    @State var search: String = ""
    
    var SearchInput: some View {
        ZStack(alignment: .leading) {
            HStack{
                TextField("Search...", text: $search)
                    .padding(8)
                    .padding(.leading, 35)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                Text("Cancel")
                    .foregroundColor(.blue)
                    .padding(EdgeInsets(top: 0.0, leading: 0.0, bottom: 0.0, trailing: 10.0))
                    .opacity((search == "") ? 0.0 : 1.0)
                    .onTapGesture {
                        self.search = ""
                    }
            }
                
            Label("", systemImage: "magnifyingglass")
                .padding(.leading, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .foregroundColor(.secondary.opacity(0.2))
        }
        //.padding()
    }
    
    var GlobalContent: some View {
        return TimelineView(events: $model.events, loading: $model.loading, damus: damus_state, show_friend_icon: true, filter: { _ in true })
            .refreshable {
                // Fetch new information by unsubscribing and resubscribing to the relay
                model.unsubscribe()
                model.subscribe()
            }
    }
    
    var SearchContent: some View {
        SearchResultsView(damus_state: damus_state, search: $search)
            .refreshable {
                // Fetch new information by unsubscribing and resubscribing to the relay
                model.unsubscribe()
                model.subscribe()
            }.padding(.horizontal)
    }
    
    var MainContent: some View {
        Group {
            if search.isEmpty {
                GlobalContent
            } else {
                SearchContent
            }
        }
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            MainContent
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                SearchInput
                    //.frame(maxWidth: 275)
                    .padding()
                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .onChange(of: search) { s in
            print("search change 1")
        }
        .onAppear {
            if model.events.isEmpty {
                model.subscribe()
            }
        }
        .onDisappear {
            model.unsubscribe()
        }
    }
}

struct SearchHomeView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        SearchHomeView(
            damus_state: state,
            model: SearchHomeModel(damus_state: state)
        )
    }
}
