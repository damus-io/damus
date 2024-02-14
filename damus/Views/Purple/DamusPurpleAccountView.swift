//
//  DamusPurpleAccountView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-01-26.
//

import SwiftUI

struct DamusPurpleAccountView: View {
    var colorScheme: ColorScheme = .dark
    let damus_state: DamusState
    let account: DamusPurple.Account
    let pfp_size: CGFloat = 90.0
    
    var body: some View {
        VStack {
            ProfilePicView(pubkey: account.pubkey, size: pfp_size, highlight: .custom(Color.black.opacity(0.4), 1.0), profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                .background(Color.black.opacity(0.4).clipShape(Circle()))
                .shadow(color: .black, radius: 10, x: 0.0, y: 5)
            
            profile_name
            
            if account.active {
                active_account_badge
            }
            else {
                inactive_account_badge
            }
            
            // TODO: Generalize this view instead of setting up dividers and paddings manually
            VStack {
                HStack {
                    Text(NSLocalizedString("Expiry date", comment: "Label for Purple subscription expiry date"))
                    Spacer()
                    Text(DateFormatter.localizedString(from: account.expiry, dateStyle: .short, timeStyle: .none))
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                Divider()
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                
                HStack {
                    Text(NSLocalizedString("Account creation", comment: "Label for Purple account creation date"))
                    Spacer()
                    Text(DateFormatter.localizedString(from: account.created_at, dateStyle: .short, timeStyle: .none))
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                
                HStack {
                    Text(NSLocalizedString("Subscriber number", comment: "Label for Purple account subscriber number"))
                    Spacer()
                    Text(verbatim: "#\(account.subscriber_number)")
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .foregroundColor(.white.opacity(0.8))
            .preferredColorScheme(.dark)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding()
        }
    }
    
    var profile_name: some View {
        let display_name = self.profile_display_name()
        return HStack(alignment: .center, spacing: 5) {
            Text(display_name)
                .font(.title)
                .bold()
                .foregroundStyle(.white)
            
            SupporterBadge(
                percent: nil,
                purple_account: account,
                style: .full
            )
        }
    }
    
    var active_account_badge: some View {
        HStack(spacing: 3) {
            Image("check-circle.fill")
                .resizable()
                .frame(width: 15, height: 15)
            
            Text(NSLocalizedString("Active account", comment: "Badge indicating user has an active Damus Purple account"))
                .font(.caption)
                .bold()
        }
        .foregroundColor(Color.white)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(PinkGradient)
        .cornerRadius(30.0)
    }
    
    var inactive_account_badge: some View {
        HStack(spacing: 3) {
            Image("warning")
                .resizable()
                .frame(width: 15, height: 15)
            
            Text(NSLocalizedString("Expired account", comment: "Badge indicating user has an expired Damus Purple account"))
                .font(.caption)
                .bold()
        }
        .foregroundColor(DamusColors.danger)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(DamusColors.dangerTertiary)
        .cornerRadius(30.0)
    }
    
    func profile_display_name() -> String {
        let profile_txn: NdbTxn<ProfileRecord?>? = damus_state.profiles.lookup_with_timestamp(account.pubkey)
        let profile: NdbProfile? = profile_txn?.unsafeUnownedValue?.profile
        let display_name = parse_display_name(profile: profile, pubkey: account.pubkey).displayName
        return display_name
    }
}

#Preview("Active") {
    DamusPurpleAccountView(
        damus_state: test_damus_state,
        account: DamusPurple.Account(
            pubkey: test_pubkey,
            created_at: Date.now,
            expiry: Date.init(timeIntervalSinceNow: 60 * 60 * 24 * 30),
            subscriber_number: 7,
            active: true
        )
    )
}

#Preview("Expired") {
    DamusPurpleAccountView(
        damus_state: test_damus_state,
        account: DamusPurple.Account(
            pubkey: test_pubkey,
            created_at: Date.init(timeIntervalSinceNow: -60 * 60 * 24 * 37),
            expiry: Date.init(timeIntervalSinceNow: -60 * 60 * 24 * 7),
            subscriber_number: 7,
            active: false
        )
    )
}
