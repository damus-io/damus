//
//  EventActionBar.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI


struct EventActionBar: View {
    let event: NostrEvent

    var body: some View {
        HStack {
            EventActionButton(img: "bubble.left") {
                print("reply")
            }
            Spacer()
            EventActionButton(img: "square.and.arrow.up") {
                print("share")
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
