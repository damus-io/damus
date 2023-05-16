//
//  GiphyView.swift
//  damus
//
//  Created by Swift on 5/10/23.
//

import SwiftUI
import GiphyUISDK

struct GiphyPicker: UIViewControllerRepresentable {
    class Coordinator: NSObject, GiphyDelegate {
        func didDismiss(controller: GiphyUISDK.GiphyViewController?) {
        }

        var parent: GiphyPicker

        init(_ parent: GiphyPicker) {
            self.parent = parent
        }

        func didSelectMedia(giphyViewController: GiphyViewController, media: GPHMedia) {
            parent.selectedURL = "https://media.giphy.com/media/\(media.id)/giphy.gif"
            parent.isPresented = false
        }
    }

    @Binding var isPresented: Bool
    @Binding var selectedURL: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<GiphyPicker>) -> GiphyViewController {
        Giphy.configure(apiKey: UserSettingsStore.shared?.giphy_api_key ?? "")
        let giphy = GiphyViewController()
        giphy.delegate = context.coordinator
        GiphyViewController.trayHeightMultiplier = 1.0
        giphy.swiftUIEnabled = true
        giphy.shouldLocalizeSearch = true
        giphy.dimBackground = true
        giphy.modalPresentationStyle = .currentContext
        return giphy
    }

    func updateUIViewController(_ uiViewController: GiphyViewController, context: UIViewControllerRepresentableContext<GiphyPicker>) {
    }
}
