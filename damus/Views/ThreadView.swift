//
//  ThreadView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

struct ThreadView: View {
    @StateObject var thread: ThreadModel
    @State var is_thread: Bool = false
    
    @EnvironmentObject var profiles: Profiles
    
    var body: some View {
        Group {
            ChatroomView()
                .environmentObject(thread)
                .onReceive(NotificationCenter.default.publisher(for: .convert_to_thread)) { _ in
                    is_thread = true
                }
            
            let edv = EventDetailView(thread: thread).environmentObject(profiles)
            NavigationLink(destination: edv, isActive: $is_thread) {
                EmptyView()
            }
        }
        .onDisappear() {
            thread.unsubscribe()
        }
        .onAppear() {
            thread.subscribe()
        }
    }
}

/*
struct ThreadView_Previews: PreviewProvider {
    static var previews: some View {
        ThreadView()
    }
}
*/
