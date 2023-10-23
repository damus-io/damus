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
    let settings: UserSettingsStore
    
    @State var qrCodeLink: String = ""
    @State var open_link_confirm: Bool = false
    @State var no_link_found: Bool = false
    
    @Binding var showShareSheet: Bool
    
    @Environment(\.openURL) var openURL
    
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
                    UIImageWriteToSavedPhotosAlbum(someImage, nil, nil, nil)
                } label: {
                    Label(NSLocalizedString("Save Image", comment: "Context menu option to save an image."), image: "download")
                }
                Button {
                    qrCodeLink = ""
                    guard let detector:CIDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh]) else {
                        return
                    }
                    guard let ciImage = CIImage(image:someImage) else {
                        return
                    }
                    let features = detector.features(in: ciImage)
                    if let qrfeatures = features as? [CIQRCodeFeature] {
                        for feature in qrfeatures {
                            if let msgStr = feature.messageString {
                                qrCodeLink += msgStr
                            }
                        }
                    }
                    
                    if qrCodeLink == "" {
                        no_link_found.toggle()
                    } else {
                        if qrCodeLink.contains("lnurl") {
                            do {
                                try open_with_wallet(wallet: settings.default_wallet.model, invoice: qrCodeLink)
                            }
                            catch {
                                present_sheet(.select_wallet(invoice: qrCodeLink))
                            }
                        } else if let _ = URL(string: qrCodeLink) {
                            open_link_confirm.toggle()
                        }
                    }
                } label: {
                    Label(NSLocalizedString("Scan for QR Code", comment: "Context menu option to scan image for a QR Code."), image: "qr-code.fill")
                }
            }
            Button {
                showShareSheet = true
            } label: {
                Label(NSLocalizedString("Share", comment: "Button to share an image."), image: "upload")
            }
        }
        .alert(NSLocalizedString("Found \(qrCodeLink).\nOpen link?", comment: "Alert message asking if the user wants to open the link."), isPresented: $open_link_confirm) {
            Button(NSLocalizedString("Open", comment: "Button to proceed with opening link."), role: .none) {
                if let url = URL(string: qrCodeLink) {
                    openURL(url)
                }
            }
            Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
        }
        .alert(NSLocalizedString("Unable to find a QR Code", comment: "Alert message letting user know a link was not found."), isPresented: $no_link_found) {
            Button(NSLocalizedString("Dismiss", comment: "Button to dismiss alert"), role: .cancel) {}
        }
    }
}
