//
//  ProfileEditButton.swift
//  damus
//
//  Created by William Casarin on 2023-07-17.
//

import SwiftUI

struct ProfileEditButton: View {
    let damus_state: DamusState

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationLink(value: Route.EditMetadata) {
            Text("Edit", comment: "Button to edit user's profile.")
                .frame(height: 30)
                .padding(.horizontal,25)
                .font(.caption.weight(.bold))
                .foregroundColor(fillColor())
                .cornerRadius(24)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(borderColor(), lineWidth: 1)
                }
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    func fillColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }

    func borderColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
}


struct ProfileEditButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ProfileEditButton(damus_state: test_damus_state)
        }
    }
}


