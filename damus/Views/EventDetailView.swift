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

struct EventDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let _ = test_damus_state()
        EventDetailView()
    }
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
