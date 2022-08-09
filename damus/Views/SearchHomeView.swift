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
                TextField("", text: $search)
                    .padding(5)
                    .padding(.leading, 35)
                    .textInputAutocapitalization(.never)
                Label("", systemImage: "xmark.square")
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
            RoundedRectangle(cornerRadius: 20)
            .foregroundColor(.gray.opacity(0.2))
        }
        .padding()
    }
    
    var GlobalContent: some View {
        TimelineView(events: $model.events, loading: $model.loading, damus: damus_state)
    }
    
    var SearchContent: some View {
        SearchResultsView(damus_state: damus_state, search: $search)
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
    
    var body: some View {
        VStack {
            SearchInput
            
            MainContent
        }
        .onChange(of: search) { s in
            print("search change 1")
        }
        .onAppear {
            model.subscribe()
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
