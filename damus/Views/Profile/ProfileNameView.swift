//
//  ProfileNameView.swift
//  damus
//
//  Created by William Casarin on 2023-02-07.
//

import SwiftUI

fileprivate struct KeyView: View {
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
                .padding([.leading, .trailing], 5)
                .background(RoundedRectangle(cornerRadius: 11).foregroundColor(DamusColors.adaptableGrey))
            
            if isCopied {
                HStack {
                    Image("check-circle")
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(NSLocalizedString("Copied", comment: "Label indicating that a user's key was copied."))
                        .font(.footnote)
                        .layoutPriority(1)
                }
                .foregroundColor(DamusColors.green)
            } else {
                HStack {
                    Button {
                        copyPubkey(bech32)
                    } label: {
                        Label {
                            Text("Public key", comment: "Label indicating that the text is a user's public account key.")
                        } icon: {
                            Image("copy2")
                                .resizable()
                                .contentShape(Rectangle())
                                .foregroundColor(.accentColor)
                                .frame(width: 20, height: 20)
                        }
                        .labelStyle(IconOnlyLabelStyle())
                        .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
    }
}

struct ProfileNameView: View {
    let pubkey: Pubkey
    let damus: DamusState
    
    var spacing: CGFloat { 10.0 }
    
    var body: some View {
        Group {
            VStack(alignment: .leading) {
                let profile_txn = self.damus.profiles.lookup(id: pubkey)
                let profile = profile_txn.unsafeUnownedValue

                switch Profile.displayName(profile: profile, pubkey: pubkey) {
                case .one:
                    HStack(alignment: .center, spacing: spacing) {
                        ProfileName(pubkey: pubkey, damus: damus)
                            .font(.title3.weight(.bold))
                    }
                case .both(username: _, displayName: let displayName):
                    Text(displayName)
                        .font(.title3.weight(.bold))
                    
                    HStack(alignment: .center, spacing: spacing) {
                        ProfileName(pubkey: pubkey, prefix: "@", damus: damus)
                            .font(.callout)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                KeyView(pubkey: pubkey)
                    .pubkey_context_menu(pubkey: pubkey)
            }
        }
    }
}

struct ProfileNameView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ProfileNameView(pubkey: test_note.pubkey, damus: test_damus_state)

            ProfileNameView(pubkey: test_note.pubkey, damus: test_damus_state)
        }
    }
}
