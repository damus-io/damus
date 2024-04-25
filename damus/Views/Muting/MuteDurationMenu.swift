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
            ForEach(DamusDuration.allCases, id: \.self) { duration in
                Button {
                    action(duration)
                } label: {
                    Text(duration.title)
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
        Text(verbatim: "Mute hashtag")
    }
}
