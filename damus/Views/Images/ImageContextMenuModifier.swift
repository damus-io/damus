//
//  ImageContextMenuModifier.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import Foundation
import SwiftUI
import UIKit

struct ImageContextMenuModifier: ViewModifier {
    let url: URL?
    let image: UIImage?
    @Binding var showShareSheet: Bool
    
    func body(content: Content) -> some View {
        return content.contextMenu {
            Button {
                UIPasteboard.general.url = url
            } label: {
                Label(NSLocalizedString("Copy Image URL", comment: "Context menu option to copy the URL of an image into clipboard."), systemImage: "doc.on.doc")
            }
            if let someImage = image {
                Button {
                    UIPasteboard.general.image = someImage
                } label: {
                    Label(NSLocalizedString("Copy Image", comment: "Context menu option to copy an image into clipboard."), systemImage: "photo.on.rectangle")
                }
                Button {
                    UIImageWriteToSavedPhotosAlbum(someImage, nil, nil, nil)
                } label: {
                    Label(NSLocalizedString("Save Image", comment: "Context menu option to save an image."), systemImage: "square.and.arrow.down")
                }
            }
            Button {
                showShareSheet = true
            } label: {
                Label(NSLocalizedString("Share", comment: "Button to share an image."), systemImage: "square.and.arrow.up")
            }
        }
    }
}
