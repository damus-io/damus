//
//  ProfileZapLinkView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-10-20.
//

import SwiftUI

struct ProfileZapLinkView<Content: View>: View {
    typealias ContentViewFunction = (_ reactions_enabled: Bool, _ lud16: String?, _ lnurl: String?) -> Content
    typealias ActionFunction = () -> Void
    
    let pubkey: Pubkey
    @ViewBuilder let label: ContentViewFunction
    let action: ActionFunction?
    
    let reactions_enabled: Bool
    let lud16: String?
    let lnurl: String?
    
    init(pubkey: Pubkey, reactions_enabled: Bool, lud16: String?, lnurl: String?, action: ActionFunction? = nil, @ViewBuilder label: @escaping ContentViewFunction) {
        self.pubkey = pubkey
        self.label = label
        self.action = action
        self.reactions_enabled = reactions_enabled
        self.lud16 = lud16?.trimmingCharacters(in: .whitespaces)
        self.lnurl = lnurl?.trimmingCharacters(in: .whitespaces)
    }
    
    init(damus_state: DamusState, pubkey: Pubkey, action: ActionFunction? = nil, @ViewBuilder label: @escaping ContentViewFunction) {
        self.pubkey = pubkey
        self.label = label
        self.action = action
        
        let profile = damus_state.profiles.lookup(id: pubkey)
        let lnurl = damus_state.profiles.lookup_with_timestamp(pubkey, borrow: { pr -> String? in
            switch pr {
            case .some(let pr): return pr.lnurl
            case .none: return nil
            }
        })
        self.reactions_enabled = profile?.reactions ?? true
        self.lud16 = profile?.lud06?.trimmingCharacters(in: .whitespaces)
        self.lnurl = lnurl?.trimmingCharacters(in: .whitespaces)
    }
    
    init(profile: Profile?, lnurl: String?, profileModel: ProfileModel, action: ActionFunction? = nil, @ViewBuilder label: @escaping ContentViewFunction) {
        self.pubkey = profileModel.pubkey
        self.label = label
        self.action = action
        
        self.reactions_enabled = profile?.reactions ?? true
        self.lud16 = profile?.lud16?.trimmingCharacters(in: .whitespaces)
        self.lnurl = lnurl?.trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        Button(
            action: {
                if let lnurl {
                    present_sheet(.zap(target: .profile(self.pubkey), lnurl: lnurl))
                }
                action?()
            },
            label: {
                self.label(self.reactions_enabled, self.lud16, self.lnurl)
            }
        )
        .contextMenu {
            if self.reactions_enabled == false {
                Text("OnlyZaps Enabled", comment: "Non-tappable text in context menu that shows up when the zap button on profile is long pressed to indicate that the user has enabled OnlyZaps, meaning that they would like to be only zapped and not accept reactions to their notes.")
            }

            if let lud16 {
                Button {
                    UIPasteboard.general.string = lud16
                } label: {
                    Label(lud16, image: "copy2")
                }
            } else {
                Button {
                    UIPasteboard.general.string = lnurl
                } label: {
                    Label(NSLocalizedString("Copy LNURL", comment: "Context menu option for copying a user's Lightning URL."), image: "copy")
                }
            }
        }
        .disabled(lnurl == nil && lud16 == nil)
    }
}

#Preview {
    let profile = make_test_profile()
    ProfileZapLinkView(pubkey: test_pubkey, reactions_enabled: true, lud16: profile.lud16, lnurl: profile.lud06, label: { reactions_enabled, lud16, lnurl in
        Image("zap.fill")
    })
}
