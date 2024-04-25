//
//  PurpleBackdrop.swift
//  damus
//
//  Created by William Casarin on 2024-03-04.
//

import SwiftUI

struct PurpleBackdrop<T: View>: View {
    @ViewBuilder let content: () -> T
    var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            Image("purple-blue-gradient-1")
                .resizable()
                .edgesIgnoringSafeArea(.all)

            content()
        }
    }
}

#Preview {
    PurpleBackdrop {
        Text(verbatim: "Hello, World")
    }
}
