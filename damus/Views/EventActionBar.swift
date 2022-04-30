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
    @StateObject var bar: ActionBarModel = ActionBarModel()
    
    var body: some View {
        HStack {
            /*
            EventActionButton(img: "square.and.arrow.up") {
                print("share")
            }

            Spacer()
            
             */
            EventActionButton(img: "bubble.left", col: nil) {
                notify(.reply, event)
            }
            .padding([.trailing], 40)

            EventActionButton(img: bar.liked ? "heart.fill" : "heart", col: bar.liked ? Color.red : nil) {
                if bar.liked {
                    notify(.delete, bar.our_like_event)
                } else {
                    notify(.like, event)
                }
            }
            .padding([.trailing], 40)

            EventActionButton(img: "arrow.2.squarepath", col: bar.boosted ? Color.green : nil) {
                if bar.boosted {
                    notify(.delete, bar.our_boost_event)
                } else {
                    notify(.boost, event)
                }
            }

        }
    }
}


func EventActionButton(img: String, col: Color?, action: @escaping () -> ()) -> some View {
    Button(action: action) {
        Label("", systemImage: img)
            .font(.footnote)
            .foregroundColor(col == nil ? Color.gray : col!)
    }
}

