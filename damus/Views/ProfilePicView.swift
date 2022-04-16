//
//  ProfilePicView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI
import CachedAsyncImage

let PFP_SIZE: CGFloat? = 64
let CORNER_RADIUS: CGFloat = 32

struct ProfilePicView: View {
    let picture: String?
    let size: CGFloat
    let highlighted: Bool

    var body: some View {
        if let pic = picture.flatMap({ URL(string: $0) }) {
            AsyncImage(url: pic) { img in
                img.resizable()
            } placeholder: {
                Color.purple.opacity(0.1)
            }
            .frame(width: PFP_SIZE, height: PFP_SIZE)
            .clipShape(Circle())
            .overlay(Circle().stroke(highlighted ? Color.red : Color.black, lineWidth: highlighted ? 4 : 0))
            .padding(2)
        } else {
            Color.purple.opacity(0.1)
                .frame(width: PFP_SIZE, height: PFP_SIZE)
                .cornerRadius(CORNER_RADIUS)
                .overlay(Circle().stroke(highlighted ? Color.red : Color.black, lineWidth: highlighted ? 4 : 0))
                .padding(2)
        }
    }
}

struct ProfilePicView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicView(picture: "http://cdn.jb55.com/img/red-me.jpg", size: 64, highlighted: false)
    }
}
