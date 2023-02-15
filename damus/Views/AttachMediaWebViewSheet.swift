//
//  AttachMediaWebViewSheet.swift
//  damus
//
//  Created by Swift on 2/14/23.
//

import SwiftUI
import WebKit

struct AttachMediaWebViewSheet: View {
    @Binding var post: String
    @Environment(\.presentationMode) var presentationMode
    @State var active_sheet: Bool = false

    func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }

    var body: some View {
        VStack {
            HStack {
                Button(NSLocalizedString("Cancel", comment: "Button to cancel out of attaching a media.")) {
                    dismiss()
                }
                .foregroundColor(.primary)

                Spacer()

                Button(NSLocalizedString("Clip URL", comment: "Button to paste the media url.")) {
                    post = post + " " + (UIPasteboard.general.string ?? "") + " "
                    dismiss()
                }
            }
            .padding([.top, .bottom], 4)

            ZStack(alignment: .topLeading) {
                SwiftUIWebView()
            }
        }
        .sheet(isPresented: $active_sheet) {
            SwiftUIWebView()
        }
        .padding()
    }
}

struct SwiftUIWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    let webView: WKWebView

    init() {
        webView = WKWebView(frame: .zero)
        webView.load(URLRequest(url: URL(string: "https://nostr.build/")!))
    }

    func makeUIView(context: Context) -> WKWebView {
        webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
}
