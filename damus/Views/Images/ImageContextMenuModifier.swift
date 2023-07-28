//
//  ImageContextMenuModifier.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import Foundation
import SwiftUI
import UIKit
import PhotosUI

struct ImageContextMenuModifier: ViewModifier {
    let url: URL?
    let image: UIImage?
    let imageSaver: ImageSaver
    @Binding var showShareSheet: Bool
    
    func body(content: Content) -> some View {
        return content.contextMenu {
            Button {
                UIPasteboard.general.url = url
            } label: {
                Label(NSLocalizedString("Copy Image URL", comment: "Context menu option to copy the URL of an image into clipboard."), image: "copy2")
            }
            if let someImage = image {
                Button {
                    UIPasteboard.general.image = someImage
                } label: {
                    Label(NSLocalizedString("Copy Image", comment: "Context menu option to copy an image into clipboard."), image: "copy2.fill")
                }
                Button {
                    // Request permission to access photo library
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                        DispatchQueue.main.async {
                            switch status {
                            case .denied:
                                imageSaver.error = true
                                imageSaver.errorType = .permissions
                                imageSaver.errorTitle = "Save Photo"
                                imageSaver.errorMessage = "Please check the photo permissions for Damus in Settings.app."
                            default:
                                imageSaver.writeToPhotoAlbum(image: someImage)
                            }
                        }
                    }
                } label: {
                    Label(NSLocalizedString("Save Image", comment: "Context menu option to save an image."), image: "download")
                }
            }
            Button {
                showShareSheet = true
            } label: {
                Label(NSLocalizedString("Share", comment: "Button to share an image."), image: "upload")
            }
        }
    }
}
