//
//  QRScanNSECView.swift
//  damus
//
//  Created by Jericho Hasselbush on 9/29/23.
//

import SwiftUI
import VisionKit

struct QRScanNSECView: View {
    @Binding var showQR: Bool
    @Binding var privKeyFound: Bool
    var codeScannerCompletion: (Result<ScanResult, ScanError>) -> Void
    var body: some View {
        ZStack {
            ZStack {
                DamusGradient()
            }
            VStack {
                Text("Scan Your Private Key QR",
                     comment: "Text to prompt scanning a QR code of a user's privkey to login to their profile.")
                    .padding(.top, 50)
                    .font(.system(size: 24, weight: .heavy))

                Spacer()
                CodeScannerView(codeTypes: [.qr],
                                scanMode: .continuous,
                                scanInterval: 2.0,
                                showViewfinder: false,
                                simulatedData: "",
                                shouldVibrateOnSuccess: false,
                                isTorchOn: false,
                                isGalleryPresented: .constant(false),
                                videoCaptureDevice: .default(for: .video),
                                completion: codeScannerCompletion)
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DamusColors.white, lineWidth: 5.0))
                    .shadow(radius: 10)

                Button(action: { showQR = false  }) {
                    VStack {
                        Image(systemName: privKeyFound ? "sparkle.magnifyingglass" : "magnifyingglass")
                            .font(privKeyFound ? .title : .title3)
                    }}
                .padding(.top)
                .buttonStyle(GradientButtonStyle())

                Spacer()

                Spacer()
            }
        }
    }
}

#Preview {
    @State var showQR  = true
    @State var privKeyFound = false
    @State var shouldSaveKey = true
    return QRScanNSECView(showQR: $showQR,
                          privKeyFound: $privKeyFound,
                          codeScannerCompletion: { _ in })
}
