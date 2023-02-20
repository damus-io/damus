//
//  LoadMoreButton.swift
//  damus
//
//  Created by William Casarin on 2023-02-20.
//

import SwiftUI

struct LoadMoreButton: View {
    @ObservedObject var events: EventHolder
    let scroller: ScrollViewProxy?
    
    func click() {
        events.flush()
        guard let ev = events.events.first, let scroller else {
            return
        }
        scroll_to_event(scroller: scroller, id: ev.id, delay: 0.1, animate: true)
    }
    
    var body: some View {
        Group {
            if events.queued > 0 {
                Button(action: click) {
                    Text("Load \(events.queued) more")
                }
                .font(.system(size: 14, weight: .bold))
                .padding(10)
                .frame(height: 30)
                .foregroundColor(.white)
                .background(LINEAR_GRADIENT)
                .clipShape(Capsule())
            } else {
                EmptyView()
            }
        }
    }
}

struct LoadMoreButton_Previews: PreviewProvider {
    @StateObject static var events: EventHolder = test_event_holder
    
    static var previews: some View {
        LoadMoreButton(events: events, scroller: nil)
    }
}


let test_event_holder = EventHolder(events: [], incoming: [test_event])
