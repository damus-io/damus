//
//  ThreadView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI


struct EventDetailView: View {
    var body: some View {
        Text(verbatim: "EventDetailView")
    }
}

func scroll_after_load(thread: ThreadModel, proxy: ScrollViewProxy) {
    if !thread.loading {
        let id = thread.initial_event.id
        scroll_to_event(scroller: proxy, id: id, delay: 0.1, animate: false)
    }
}

struct EventDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let _ = test_damus_state()
        EventDetailView()
    }
}


func print_event(_ ev: NostrEvent) {
    print(ev.description)
}

func scroll_to_event(scroller: ScrollViewProxy, id: String, delay: Double, animate: Bool, anchor: UnitPoint = .bottom) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        if animate {
            withAnimation {
                scroller.scrollTo(id, anchor: anchor)
            }
        } else {
            scroller.scrollTo(id, anchor: anchor)
        }
    }
}

extension Collection {

    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
