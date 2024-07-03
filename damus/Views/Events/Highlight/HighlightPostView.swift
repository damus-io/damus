//
//  HighlightPostView.swift
//  damus
//
//  Created by eric on 5/26/24.
//

import SwiftUI

struct HighlightPostView: View {
    let damus_state: DamusState
    let event: NostrEvent
    @Binding var selectedText: String

    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack {
                HStack(spacing: 5.0) {
                    Button(action: {
                        dismiss()
                    }, label: {
                        Text("Cancel", comment: "Button to cancel out of highlighting a note.")
                            .padding(10)
                    })
                    .buttonStyle(NeutralButtonStyle())

                    Spacer()

                    Button(NSLocalizedString("Post", comment: "Button to post a highlight.")) {
                        let tags: [[String]] = [ ["e", "\(self.event.id)"] ]

                        let kind = NostrKind.highlight.rawValue
                        guard let ev = NostrEvent(content: selectedText, keypair: damus_state.keypair, kind: kind, tags: tags) else {
                            return
                        }
                        damus_state.postbox.send(ev)
                        dismiss()
                    }
                    .bold()
                    .buttonStyle(GradientButtonStyle(padding: 10))
                }

                Divider()
                    .foregroundColor(DamusColors.neutral3)
                    .padding(.top, 5)
            }
            .frame(height: 30)
            .padding()
            .padding(.top, 15)

            HStack {
                var attributedString: AttributedString {
                    var attributedString = AttributedString(selectedText)

                    if let range = attributedString.range(of: selectedText) {
                        attributedString[range].backgroundColor = DamusColors.highlight
                    }

                    return attributedString
                }

                Text(attributedString)
                    .lineSpacing(5)
                    .padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 25).fill(DamusColors.highlight).frame(width: 4),
                alignment: .leading
            )
            .padding()

            Spacer()
        }
    }
}
