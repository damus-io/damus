//
//  EventProfile.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

func eventview_pfp_size(_ size: EventViewKind) -> CGFloat {
    switch size {
    case .small:
        return PFP_SIZE * 0.5
    case .normal:
        return PFP_SIZE
    case .selected:
        return PFP_SIZE
    case .title:
        return PFP_SIZE
    case .subheadline:
        return PFP_SIZE * 0.5
    }
}

struct EventProfile: View {
    let damus_state: DamusState
    let pubkey: Pubkey
    let size: EventViewKind
    
    var pfp_size: CGFloat {
        eventview_pfp_size(size)
    }
    
    var disable_animation: Bool {
        damus_state.settings.disable_animation
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ProfilePicView(pubkey: pubkey, size: pfp_size, highlight: .none, profiles: damus_state.profiles, disable_animation: disable_animation, show_zappability: true)
                .onTapGesture {
                    show_profile_action_sheet_if_enabled(damus_state: damus_state, pubkey: pubkey)
                }
                .onLongPressGesture(minimumDuration: 0.1) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    damus_state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                }

            VStack(alignment: .leading, spacing: 0) {
                EventProfileName(pubkey: pubkey, damus: damus_state, size: size)

                UserStatusView(status: damus_state.profiles.profile_data(pubkey).status, show_general: damus_state.settings.show_general_statuses, show_music: damus_state.settings.show_music_statuses)
            }
        }
    }
}

struct EventProfile_Previews: PreviewProvider {
    static var previews: some View {
        EventProfile(damus_state: test_damus_state, pubkey: test_note.pubkey, size: .normal)
    }
}
