//
//  WalletPickerView.swift
//  damus
//
//  Created by Lee Salminen on 12/24/22.
//

import Foundation
import SwiftUI

func WalletButton(url: URL, wallet_name: String, image_name: String, prefix: String, dismiss: DismissAction) -> some View {
    HStack {
        Image(image_name)
            .resizable()
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        Text(wallet_name)
        Spacer()
    }
    .frame(height: 50)
    .contentShape(Rectangle())
    .onTapGesture {
        if let prefixedUrl = URL(string: "\(prefix)\(url)") {
            UIApplication.shared.open(prefixedUrl)
        }
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
                WalletButton(url: self.url, wallet_name: "Breez", image_name: "breez", prefix: "breez:",  dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Phoenix", image_name: "phoenix", prefix:"phoenix://", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Wallet of Satoshi", image_name: "wos", prefix: "walletofsatoshi:lightning:",  dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Bitcoin Beach", image_name: "bbw", prefix: "bitcoinbeach://", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Bitcoin Jungle", image_name: "bj", prefix: "bitcoinjungle://", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Zeus", image_name: "zeusln", prefix: "zeusln:lightning:", dismiss: dismiss)
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
