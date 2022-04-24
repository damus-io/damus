//
//  ThreadView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI


struct ThreadView: View {
    @State var is_chatroom: Bool = false
    
    @EnvironmentObject var profiles: Profiles
    @EnvironmentObject var thread: ThreadModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Group {
            if is_chatroom {
                ChatroomView()
                    .navigationBarTitle("Chat")
                    .environmentObject(profiles)
                    .environmentObject(thread)
            } else {
                EventDetailView(thread: thread)
                    .navigationBarTitle("Thread")
                    .environmentObject(profiles)
                    .environmentObject(thread)
            }
            
            
            /*
            NavigationLink(destination: edv, isActive: $is_chatroom) {
                EmptyView()
            }
             */
        }
        .onReceive(NotificationCenter.default.publisher(for: .switched_timeline)) { n in
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggle_thread_view)) { _ in
            is_chatroom = !is_chatroom
            //print("is_chatroom: \(is_chatroom)")
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
