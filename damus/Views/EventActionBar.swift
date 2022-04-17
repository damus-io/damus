//
//  EventActionBar.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

extension Notification.Name {
    static var thread_focus: Notification.Name {
        return Notification.Name("thread focus")
    }
}

enum ActionBarSheet: Identifiable {
    case reply

    var id: String {
        switch self {
        case .reply: return "reply"
        }
    }
}

struct EventActionBar: View {
    let event: NostrEvent

    @State var sheet: ActionBarSheet? = nil
    @EnvironmentObject var profiles: Profiles

    var body: some View {
        HStack {
            EventActionButton(img: "bubble.left") {
                self.sheet = .reply
            }

            Spacer()

            EventActionButton(img: "square.and.arrow.up") {
                print("share")
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .reply:
                ReplyView(replying_to: event)
            }
        }
    }
}


func EventActionButton(img: String, action: @escaping () -> ()) -> some View {
    Button(action: action) {
        Label("", systemImage: img)
            .font(.footnote)
            .foregroundColor(.gray)
    }
}
