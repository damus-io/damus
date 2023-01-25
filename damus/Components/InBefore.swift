//
//  InBefore.swift
//  damus
//
//  Created by eric on 1/24/23.
//

import SwiftUI

struct InBefore: View {
    @Binding var events: [NostrEvent]

    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(.gray)
                .font(.footnote)
            
            Text(in_before_text(events: events))
                    .font(.footnote)
                    .foregroundColor(.gray)
        }
    }
    
    func in_before_text(events: [NostrEvent]) -> String {
        let dateFormatter = DateFormatter()
        let currentDate = Int64(Date().timeIntervalSince1970)
        let oldestEvent = Date(timeIntervalSince1970: TimeInterval(events.last?.created_at ?? currentDate))
        dateFormatter.dateFormat = "LLLL"
        let monthString = dateFormatter.string(from: oldestEvent)
        dateFormatter.dateFormat = "yyyy"
        let yearString = dateFormatter.string(from: oldestEvent)
        return "In before \(monthString) \(yearString)"
    }
}

struct InBefore_Previews: PreviewProvider {
    static var previews: some View {
        InBefore(events: .constant(Constants.EXAMPLE_EVENTS))
    }
}
