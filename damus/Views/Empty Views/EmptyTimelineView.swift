//
//  EmptyNotificationsView.swift
//  damus
//
//  Created by Sam DuBois on 12/17/22.
//

import SwiftUI

struct EmptyTimelineView: View {
    var body: some View {
        VStack {
            Image(systemName: "tray.fill")
                .font(.system(size: 35))
                .padding()
            Text("Nothing to see here. Check back later!", comment: "Indicates that there are no notes in the timeline to view.")
                .multilineTextAlignment(.center)
                .font(.callout.weight(.medium))
        }
        .foregroundColor(.gray)
        .padding()
    }
}

struct EmptyTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        EmptyTimelineView()
    }
}
