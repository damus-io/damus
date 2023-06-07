//
//  QRScannerView.swift
//  damus
//
//  Created by William Casarin on 2023-05-09.
//

import SwiftUI

enum WalletScanResult: Equatable {
    static func == (lhs: WalletScanResult, rhs: WalletScanResult) -> Bool {
        switch lhs {
        case .success(let a):
            switch rhs {
            case .success(let b):
                return a == b
            case .failed:
                return false
            case .scanning:
                return false
            }
        case .failed:
            switch rhs {
            case .success:
                return false
            case .failed:
                return true
            case .scanning:
                return false
            }
        case .scanning:
            switch rhs {
            case .success:
                return false
            case .failed:
                return false
            case .scanning:
                return true
            }
        }
    }
    
    case success(WalletConnectURL)
    case failed
    case scanning
}

struct NWCPaste: View {
    @Binding var result: WalletScanResult
    
    @Environment(\.colorScheme) var colorScheme

    init(result: Binding<WalletScanResult>) {
        self._result = result
    }

    var body: some View {
        Button(action: {
            if let pasted_nwc = UIPasteboard.general.string {
                guard let url = WalletConnectURL(str: pasted_nwc) else {
                    self.result = .failed
                    return
                }
                
                self.result = .success(url)
            }
        }) {
            HStack {
                Image(systemName: "doc.on.clipboard")
                Text("Paste", comment: "Button to paste a Nostr Wallet Connect string to connect the wallet for use in Damus for zaps.")
            }
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .center)
            .foregroundColor(colorScheme == .light ? DamusColors.black : DamusColors.white)
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(colorScheme == .light ? DamusColors.black : DamusColors.white, lineWidth: 2)
            }
            .padding(EdgeInsets(top: 10, leading: 50, bottom: 25, trailing: 50))
        }
    }
}

struct WalletScannerView: View {
    @Binding var result: WalletScanResult
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            CodeScannerView(codeTypes: [.qr]) { res in
                switch res {
                case .success(let success):
                    guard let url = WalletConnectURL(str: success.string) else {
                        result = .failed
                        return
                    }
                    
                    result = .success(url)
                case .failure:
                    result = .failed
                }
                
                dismiss()
            }
            NWCPaste(result: $result)
                .padding(.vertical)
        }
    }
}

struct QRScannerView_Previews: PreviewProvider {
    @State static var result: WalletScanResult = .scanning
    static var previews: some View {
        WalletScannerView(result: $result)
    }
}
