//
//  EventActionBar.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

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
            /*
            EventActionButton(img: "square.and.arrow.up") {
                print("share")
            }

            Spacer()
            
             */
            EventActionButton(img: "bubble.left") {
                notify(.reply, event)
            }
            .padding([.trailing], 40)

            EventActionButton(img: "arrow.2.squarepath") {
                notify(.boost, event)
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

