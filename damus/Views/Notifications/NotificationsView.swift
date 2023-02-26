//
//  NotificationsView.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import SwiftUI

struct NotificationsView: View {
    let state: DamusState
    @ObservedObject var notifications: NotificationsModel
    
    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading) {
                    Color.white.opacity(0)
                        .id("startblock")
                        .frame(height: 5)
                    ForEach(notifications.notifications, id: \.id) { item in
                        NotificationItemView(state: state, item: item)
                    }
                }
                .background(GeometryReader { proxy -> Color in
                    DispatchQueue.main.async {
                        handle_scroll_queue(proxy, queue: self.notifications)
                    }
                    return Color.clear
                })
                .padding(.horizontal)
            }
            .onReceive(handle_notify(.scroll_to_top)) { notif in
                let _ = notifications.flush()
                self.notifications.should_queue = false
                scroll_to_event(scroller: scroller, id: "startblock", delay: 0.0, animate: true, anchor: .top)
            }
        }
        .onAppear {
            let _ = notifications.flush()
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView(state: test_damus_state(), notifications: NotificationsModel())
    }
}
