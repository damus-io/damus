//
//  PurpleViewPrimitives.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-02-09.
//

import Foundation
import SwiftUI

struct PurpleViewPrimitives {
    struct IconOnBoxView: View {
        var name: String

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 20.0)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20.0))
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(LinearGradient(
                                colors: [DamusColors.pink, .white.opacity(0), .white.opacity(0.5), .white.opacity(0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing), lineWidth: 1)
                    )

                            Image(name)
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.white)
            }
        }
    }

    struct IconView: View {
        var name: String

        var body: some View {
            Image(name)
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.white)
        }
    }

    struct TitleView: View {
        var text: String

        var body: some View {
            Text(text)
                .font(.title3)
                .bold()
                .foregroundColor(.white)
                .padding(.bottom, 3)
        }
    }

    struct SubtitleView: View {
        var text: String

        var body: some View {
            Text(text)
                .foregroundColor(.white.opacity(0.65))
        }
    }

    struct ProductLoadErrorView: View {
        var body: some View {
            Text(NSLocalizedString("Subscription Error", comment: "Ah dang there was an error loading subscription information from the AppStore. Please try again later :("))
                .foregroundColor(.white)
        }
    }

    struct SaveTextView: View {
        var body: some View {
            Text(NSLocalizedString("Save 14%", comment: "Percentage of purchase price the user will save"))
                .font(.callout)
                .italic()
                .foregroundColor(DamusColors.green)
        }
    }
}

struct IconOnBoxView_Previews: PreviewProvider {
    static var previews: some View {
        PurpleViewPrimitives.IconOnBoxView(name: "badge")
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}

struct IconView_Previews: PreviewProvider {
    static var previews: some View {
        PurpleViewPrimitives.IconView(name: "badge")
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}

struct TitleView_Previews: PreviewProvider {
    static var previews: some View {
        PurpleViewPrimitives.TitleView(text: "Title Text")
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}

struct SubtitleView_Previews: PreviewProvider {
    static var previews: some View {
        PurpleViewPrimitives.SubtitleView(text: "Subtitle Text")
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}

struct ProductLoadErrorView_Previews: PreviewProvider {
    static var previews: some View {
        PurpleViewPrimitives.ProductLoadErrorView()
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}

struct SaveTextView_Previews: PreviewProvider {
    static var previews: some View {
        PurpleViewPrimitives.SaveTextView()
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}
