//
//  MuteDurationMenu.swift
//  damus
//
//  Created by Charlie Fish on 1/14/24.
//

import SwiftUI

struct MuteDurationMenu<T: View>: View {
    var action: (DamusDuration?) -> Void
    @ViewBuilder var label: () -> T

    var body: some View {
        Menu {
            Button {
                action(nil)
            } label: {
                Text("Indefinite", comment: "Mute a given item indefinitly (until user unmutes it). As opposed to muting the item for a given period of time.")
            }
            ForEach(DamusDuration.allCases, id: \.self) { duration in
                Button {
                    action(duration)
                } label: {
                    Text("\(duration.title)")
                }
            }
        } label: {
            self.label()
        }
    }
}

#Preview {
    MuteDurationMenu { _ in

    } label: {
        Text("Mute hashtag")
    }
}
