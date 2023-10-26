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

enum Fields{
    case status
    case link
}

struct UserStatusSheet: View {
    let damus_state: DamusState
    let postbox: PostBox
    let keypair: Keypair

    @State var duration: StatusDuration = .never
    @State var show_link: Bool = false
    
    @ObservedObject var status: UserStatusModel
    @Environment(\.colorScheme) var colorScheme
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
        // This is needed to prevent the view from being moved when the keyboard is shown
        GeometryReader { geometry in
            VStack {
                HStack {
                    Button(action: {
                        dismiss()
                    }, label: {
                        Text("Cancel", comment: "Cancel button text for dismissing profile status settings view.")
                            .padding(10)
                    })
                    .buttonStyle(NeutralButtonStyle())
                    
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
                        Text("Share", comment: "Save button text for saving profile status settings.")
                    })
                    .buttonStyle(GradientButtonStyle(padding: 10))
                }
                .padding(5)
                
                Divider()
                
                ZStack(alignment: .top) {
                    ProfilePicView(pubkey: keypair.pubkey, size: 120.0, highlight: .custom(DamusColors.white, 3.0), profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                        .padding(.top, 30)
                    
                    VStack(spacing: 0) {
                        HStack {
                            TextField(NSLocalizedString("Staying humble...", comment: "Placeholder as an example of what the user could set as their profile status."), text: status_binding, axis: .vertical)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .lineLimit(3)
                                .frame(width: 175)
                            
                        }
                        .padding(10)
                        .background(colorScheme == .light ? .white : DamusColors.neutral3)
                        .cornerRadius(15)
                        .shadow(color: colorScheme == .light ? DamusColors.neutral3 : .clear, radius: 15)
                        
                        Circle()
                            .fill(colorScheme == .light ? .white : DamusColors.neutral3)
                            .frame(width: 12, height: 12)
                            .padding(.trailing, 140)
                        
                        Circle()
                            .fill(colorScheme == .light ? .white : DamusColors.neutral3)
                            .frame(width: 7, height: 7)
                            .padding(.trailing, 120)
                        
                    }
                    .padding(.leading, 60)
                }
                
                VStack {
                    HStack {
                        Image("link")
                            .foregroundColor(DamusColors.neutral3)
                        
                        TextField(text: url_binding, label: {
                            Text("Add an external link", comment: "Placeholder as an example of what the user could set so that the link is opened when the status is tapped.")
                        })
                        .autocorrectionDisabled(true)
                    }
                    .padding(10)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DamusColors.neutral3, lineWidth: 1)
                    )
                }
                .padding()
                
                Toggle(isOn: $status.playing_enabled, label: {
                    Text("Broadcast music playing on Apple Music", comment: "Toggle to enable or disable broadcasting what music is being played on Apple Music in their profile status.")
                })
                .tint(DamusColors.purple)
                .padding(.horizontal)
                
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
                .padding()
                
                Spacer()
                
            }
            .padding(.top)
            .background(DamusColors.adaptableWhite.edgesIgnoringSafeArea(.all))
        }
        .dismissKeyboardOnTap()
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}


struct UserStatusSheet_Previews: PreviewProvider {
    static var previews: some View {
        UserStatusSheet(damus_state: test_damus_state, postbox: test_damus_state.postbox, keypair: test_keypair, status: .init())
    }
}
