//
//  WalletPickerView.swift
//  damus
//
//  Created by Lee Salminen on 12/24/22.
//

import Foundation
import SwiftUI

func WalletButton(url: URL, wallet_name: String, image_name: String, dismiss: DismissAction) -> some View {
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
                WalletButton(url: self.url, wallet_name: "Breez", image_name: "breez", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Muun", image_name: "muun", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Phoenix", image_name: "phoenix", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Wallet of Satoshi", image_name: "wos", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Bitcoin Beach", image_name: "bbw", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Bitcoin Jungle", image_name: "bj", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Zeus", image_name: "zeusln", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Strike", image_name: "strike", dismiss: dismiss)
                WalletButton(url: self.url, wallet_name: "Cash App", image_name: "cashapp", dismiss: dismiss)
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
