//
//  WalletPickerView.swift
//  damus
//
//  Created by Lee Salminen on 12/24/22.
//

import Foundation
import SwiftUI

func WalletButton(url: URL, wallet_name: String, dismiss: DismissAction) -> some View {
    HStack {
        Image(systemName: "bolt.circle")
            .resizable()
            .frame(width: 30, height: 30)
        Text(wallet_name)
        Spacer()
    }
    .frame(height: 50)
    .contentShape(Rectangle())
    .onTapGesture {
        UIApplication.shared.open(url)
        dismiss()
        
    }
}

struct WalletPickerView: View {
    @Environment(\.dismiss) var dismiss
    @State var url: URL
    
    var body: some View {
        VStack {
            List {
                HStack {
                    Button(action: {
                        UIApplication.shared.open(url)
                        self.dismiss()
                    }) {
                        Image(systemName: "bolt.circle")
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("Default Wallet")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    Spacer()
                    Divider()
                    Spacer()
                    Button(action: {
                        UIPasteboard.general.url = self.url
                        self.dismiss()
                    }) {
                        Image(systemName: "clipboard")
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("Copy Address")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                WalletButton(url: self.url, wallet_name: "Breez", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Muun", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Phoenix", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Wallet of Satoshi", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Bitcoin Beach", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Bitcoin Jungle", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Zeus", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Strike", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Cash App", dismiss: dismiss)
            }
            .navigationTitle("Select a Lightning Wallet")
            
            Button("Cancel") {
                dismiss()
            }
        }
        
    }
}

struct WalletPickerView_Previews: PreviewProvider {
    @State static var url = URL(string: "jb55@sendsats.lol")
    
    static var previews: some View {
        WalletPickerView(url: url!)
    }
}
