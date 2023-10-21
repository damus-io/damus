//
//  PubkeyView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI

struct PubkeyView: View {
    let pubkey: Pubkey
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isCopied = false
    
    func keyColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
    
    private func copyPubkey(_ pubkey: String) {
        UIPasteboard.general.string = pubkey
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation {
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    isCopied = false
                }
            }
        }
    }
    
    func pubkey_context_menu(pubkey: Pubkey) -> some View {
        return self.contextMenu {
            Button {
                UIPasteboard.general.string = pubkey.npub
            } label: {
                Label(NSLocalizedString("Copy Account ID", comment: "Context menu option for copying the ID of the account that created the note."), image: "copy2")
            }
        }
    }
    
    var body: some View {
        let bech32 = pubkey.npub
        
        HStack {
            Text(verbatim: "\(abbrev_pubkey(bech32, amount: 16))")
                .font(.footnote)
                .foregroundColor(keyColor())
                .padding(5)
                .padding([.leading], 5)
            
            HStack {
                if isCopied {
                    Image("check-circle")
                        .resizable()
                        .foregroundColor(DamusColors.green)
                        .frame(width: 20, height: 20)
                    Text(NSLocalizedString("Copied", comment: "Label indicating that a user's key was copied."))
                        .font(.footnote)
                        .layoutPriority(1)
                        .foregroundColor(DamusColors.green)
                } else {
                    Button {
                        copyPubkey(bech32)
                    } label: {
                        Label {
                            Text("Public key", comment: "Label indicating that the text is a user's public account key.")
                        } icon: {
                            Image("copy2")
                                .resizable()
                                .contentShape(Rectangle())
                                .foregroundColor(colorScheme == .light ? DamusColors.darkGrey : DamusColors.lightGrey)
                                .frame(width: 20, height: 20)
                        }
                        .labelStyle(IconOnlyLabelStyle())
                        .symbolRenderingMode(.hierarchical)
                        
                    }
                }
            }
            .padding([.trailing], 10)
        }
        .background(RoundedRectangle(cornerRadius: 11).foregroundColor(colorScheme == .light ? DamusColors.adaptableGrey : DamusColors.neutral1))
    }
}

#Preview {
    PubkeyView(pubkey: test_pubkey)
}

func abbrev_pubkey(_ pubkey: String, amount: Int = 8) -> String {
    return pubkey.prefix(amount) + ":" + pubkey.suffix(amount)
}
