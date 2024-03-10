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
                        dismiss()
                        return
                    }
                    
                    result = .success(url)
                case .failure:
                    result = .failed
                }
                
                dismiss()
            }
        }
    }
}

struct QRScannerView_Previews: PreviewProvider {
    @State static var result: WalletScanResult = .scanning
    static var previews: some View {
        WalletScannerView(result: $result)
    }
}
