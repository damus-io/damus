//
//  UserStatusSheet.swift
//  damus
//
//  Created by William Casarin on 2023-08-23.
//

import SwiftUI

enum StatusDuration: String, CaseIterable {
    case never = "Never"
    case thirty_mins = "30 Minutes"
    case hour = "1 Hour"
    case four_hours = "4 Hours"
    case day = "1 Day"
    case week = "1 Week"

    var expiration: Date? {
        switch self {
        case .never:
            return nil
        case .thirty_mins:
            return Date.now.addingTimeInterval(60 * 30)
        case .hour:
            return Date.now.addingTimeInterval(60 * 60)
        case .four_hours:
            return Date.now.addingTimeInterval(60 * 60 * 4)
        case .day:
            return Date.now.addingTimeInterval(60 * 60 * 24)
        case .week:
            return Date.now.addingTimeInterval(60 * 60 * 24 * 7)
        }
    }
}

struct UserStatusSheet: View {
    let postbox: PostBox
    let keypair: Keypair

    @State var duration: StatusDuration = .never
    @ObservedObject var status: UserStatusModel
    @Environment(\.dismiss) var dismiss

    var status_binding: Binding<String> {
        Binding(get: {
            status.general?.content ?? ""
        }, set: { v in
            status.general = UserStatus(type: .general, expires_at: duration.expiration, content: v, created_at: UInt32(Date.now.timeIntervalSince1970))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set Status")
                .font(.largeTitle)

            TextField(text: status_binding, label: {
                Text("📋 Working")
            })

            HStack {
                Text("Clear status")

                Spacer()

                Picker("Duration", selection: $duration) {
                    ForEach(StatusDuration.allCases, id: \.self) { d in
                        Text("\(d.rawValue)")
                            .tag(d)
                    }
                }
            }

            Toggle(isOn: $status.playing_enabled, label: {
                Text("Broadcast music playing on Apple Music")
            })

            HStack(alignment: .center) {
                Button(action: {
                    dismiss()
                }, label: {
                    Text("Cancel")
                })

                Spacer()

                Button(action: {
                    guard let status = self.status.general,
                          let kp = keypair.to_full(),
                          let ev = make_user_status_note(status: status, keypair: kp, expiry: duration.expiration)
                    else {
                        return
                    }

                    postbox.send(ev)

                    dismiss()
                }, label: {
                    Text("Save")
                })
                .buttonStyle(GradientButtonStyle())
            }
            .padding([.top], 30)

            Spacer()
        }
        .padding(30)
    }
}


struct UserStatusSheet_Previews: PreviewProvider {
    static var previews: some View {
        UserStatusSheet(postbox: PostBox(pool: RelayPool()), keypair: Keypair(pubkey: .empty, privkey: nil), status: .init())
    }
}
