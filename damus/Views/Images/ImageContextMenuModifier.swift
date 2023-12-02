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
    
    @State var qrCodeValue: String = ""
    @State var open_link_confirm: Bool = false
    @State var open_wallet_confirm: Bool = false
    @State var not_found: Bool = false
    
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
                    qrCodeValue = ""
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
                                qrCodeValue = msgStr
                            }
                        }
                    }
                    
                    if qrCodeValue == "" {
                        not_found.toggle()
                    } else {
                        if qrCodeValue.localizedCaseInsensitiveContains("lnurl") || qrCodeValue.localizedCaseInsensitiveContains("lnbc") {
                            open_wallet_confirm.toggle()
                            open_link_confirm.toggle()
                        } else if let _ = URL(string: qrCodeValue) {
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
        .alert(NSLocalizedString("Found\n \(qrCodeValue)", comment: "Alert message asking if the user wants to open the link.").truncate(maxLength: 50), isPresented: $open_link_confirm) {
            if open_wallet_confirm {
                Button(NSLocalizedString("Open in wallet", comment: "Button to open the value found in browser."), role: .none) {
                    do {
                        try open_with_wallet(wallet: settings.default_wallet.model, invoice: qrCodeValue)
                    }
                    catch {
                        present_sheet(.select_wallet(invoice: qrCodeValue))
                    }
                }
            } else {
                Button(NSLocalizedString("Open in browser", comment: "Button to open the value found in browser."), role: .none) {
                    if let url = URL(string: qrCodeValue) {
                        openURL(url)
                    }
                }
            }
            Button(NSLocalizedString("Copy", comment: "Button to copy the value found."), role: .none) {
                UIPasteboard.general.string = qrCodeValue
            }
            Button(NSLocalizedString("Cancel", comment: "Button to cancel any interaction with the QRCode link."), role: .cancel) {}
        }
        .alert(NSLocalizedString("Unable to find a QR Code", comment: "Alert message letting user know a QR Code was not found."), isPresented: $not_found) {
            Button(NSLocalizedString("Dismiss", comment: "Button to dismiss alert"), role: .cancel) {}
        }
    }
}
