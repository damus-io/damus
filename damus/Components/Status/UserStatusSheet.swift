//
//  UserStatusSheet.swift
//  damus
//
//  Created by William Casarin on 2023-08-23.
//

import SwiftUI

enum StatusDuration: CustomStringConvertible, CaseIterable {
    case never
    case thirty_mins
    case hour
    case four_hours
    case day
    case week

    var timeInterval: TimeInterval? {
        switch self {
        case .never:
            return nil
        case .thirty_mins:
            return 60 * 30
        case .hour:
            return 60 * 60
        case .four_hours:
            return 60 * 60 * 4
        case .day:
            return 60 * 60 * 24
        case .week:
            return 60 * 60 * 24 * 7
        }
    }

    var expiration: Date? {
        guard let timeInterval else {
            return nil
        }

        return Date.now.addingTimeInterval(timeInterval)
    }

    var description: String {
        guard let timeInterval else {
            return NSLocalizedString("Never", comment: "Profile status duration setting of never expiring.")
        }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.minute, .hour, .day, .weekOfMonth]
        return formatter.string(from: timeInterval) ?? "\(timeInterval) seconds"
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
            if let general = status.general {
                status.general = UserStatus(type: .general, expires_at: duration.expiration, content: v, created_at: UInt32(Date.now.timeIntervalSince1970), url: general.url)
            } else {
                status.general = UserStatus(type: .general, expires_at: duration.expiration, content: v, created_at: UInt32(Date.now.timeIntervalSince1970), url: nil)
            }
        })
    }

    var url_binding: Binding<String> {
        Binding(get: {
            status.general?.url?.absoluteString ?? ""
        }, set: { v in
            if let general = status.general {
                status.general = UserStatus(type: .general, expires_at: duration.expiration, content: general.content, created_at: UInt32(Date.now.timeIntervalSince1970), url: URL(string: v))
            } else {
                status.general = UserStatus(type: .general, expires_at: duration.expiration, content: "", created_at: UInt32(Date.now.timeIntervalSince1970), url: URL(string: v))
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set Status", comment: "Title of view that allows the user to set their profile status (e.g. working, studying, coding)")
                .font(.largeTitle)

            TextField(text: status_binding, label: {
                Text("📋 Working", comment: "Placeholder as an example of what the user could set as their profile status.")
            })

            HStack {
                Image("link")

                TextField(text: url_binding, label: {
                    Text("https://example.com", comment: "Placeholder as an example of what the user could set so that the link is opened when the status is tapped.")
                })
            }

            HStack {
                Text("Clear status", comment: "Label to prompt user to select an expiration time for the profile status to clear.")

                Spacer()

                Picker(NSLocalizedString("Duration", comment: "Label for profile status expiration duration picker."), selection: $duration) {
                    ForEach(StatusDuration.allCases, id: \.self) { d in
                        Text(verbatim: d.description)
                            .tag(d)
                    }
                }
            }

            Toggle(isOn: $status.playing_enabled, label: {
                Text("Broadcast music playing on Apple Music", comment: "Toggle to enable or disable broadcasting what music is being played on Apple Music in their profile status.")
            })

            HStack(alignment: .center) {
                Button(action: {
                    dismiss()
                }, label: {
                    Text("Cancel", comment: "Cancel button text for dismissing profile status settings view.")
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
                    Text("Save", comment: "Save button text for saving profile status settings.")
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
        UserStatusSheet(postbox: test_damus_state.postbox, keypair: test_keypair, status: .init())
    }
}
