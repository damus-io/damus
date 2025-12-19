//
//  PostingTimelineSwitcherView.swift
//  damus
//
//  Created by Askia Linder on 2025-09-06.
//

import SwiftUI
import TipKit

struct PostingTimelineSwitcherView: View {
    let damusState: DamusState
    @Binding var timelineSource: TimelineSource

    init(damusState: DamusState, timelineSource: Binding<TimelineSource>) {
        self.damusState = damusState
        self._timelineSource = timelineSource
    }

    var body: some View {
        Menu {
            Picker(selection: $timelineSource) {
                Label(TimelineSource.follows.description, image: "user-added")
                    .tag(TimelineSource.follows)
                Label(TimelineSource.favorites.description, image: "heart")
                    .tag(TimelineSource.favorites)
            } label: {
                EmptyView()
            }
            .onAppear() {
                if #available(iOS 17.0, *) {
                    TimelineSwitcherTip.shared.invalidate(reason: .actionPerformed)
                }
            }
        } label: {
            Color.clear
        }
        .frame(width: 50, height: 35)
        .menuOrder(.fixed)
        .accessibilityLabel(NSLocalizedString("Timeline switcher, select \(TimelineSource.follows.description) or \(TimelineSource.favorites.description)", comment: "Accessibility label for the timeline switcher button at the topbar"))
    }

    @available(iOS 17, *)
    struct TimelineSwitcherTip: Tip {
        static let shared = TimelineSwitcherTip()

        var title: Text {
            Text("Timeline switcher", comment: "Title of tip that informs users that they can switch timelines.")
        }

        var message: Text? {
            Text("Switch between posts from your follows or your favorites.", comment: "Description of the tip that informs users that they can switch between posts from your follows or your favorites.")
        }

        var image: Image? {
            Image(systemName: "square.stack")
        }
    }
}

struct PostingTimelineSwitcherView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PostingTimelineSwitcherView(
                damusState: test_damus_state,
                timelineSource: .constant(.follows)
            )
            Spacer()
        }
    }
}

