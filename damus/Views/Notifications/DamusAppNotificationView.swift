//
//  DamusAppNotificationView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-02-23.
//

import SwiftUI

fileprivate let DEEP_WEBSITE_LINK = false

// TODO: Load products in a more dynamic way (if we move forward with checkout deep linking)
fileprivate let PURPLE_ONE_MONTH = "purple_one_month"
fileprivate let PURPLE_ONE_YEAR = "purple_one_year"

struct DamusAppNotificationView: View {
    let damus_state: DamusState
    let notification: DamusAppNotification
    var relative_date: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if abs(notification.notification_timestamp.timeIntervalSinceNow) > 60 {
            return formatter.localizedString(for: notification.notification_timestamp, relativeTo: Date.now)
        }
        else {
            return NSLocalizedString("now", comment: "Relative time label that indicates a notification happened now")
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 15) {
                    AppIcon()
                        .frame(width: 50, height: 50)
                        .clipShape(.rect(cornerSize: CGSize(width: 10.0, height: 10.0)))
                        .shadow(radius: 5, y: 5)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .center, spacing: 3) {
                            Text("Damus", comment: "Name of the app for the title of an internal notification")
                                .font(.body.weight(.bold))
                            Text(verbatim: "·")
                                .foregroundStyle(.secondary)
                            Text(relative_date)
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        HStack(spacing: 3) {
                            Image("check-circle.fill")
                                .resizable()
                                .frame(width: 15, height: 15)
                            Text("Internal app notification", comment: "Badge indicating that a notification is an official internal app notification")
                                .font(.caption2)
                                .bold()
                        }
                        .foregroundColor(Color.white)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(PinkGradient)
                        .cornerRadius(30.0)
                    }
                    Spacer()
                }
                .padding(.bottom, 2)
                switch notification.content {
                    case .purple_impending_expiration(let days_remaining, _):
                        PurpleExpiryNotificationView(damus_state: self.damus_state, days_remaining: days_remaining, expired: false)
                    case .purple_expired(expiry_date: _):
                        PurpleExpiryNotificationView(damus_state: self.damus_state, days_remaining: 0, expired: true)
                }
            }
            .padding(.horizontal)
            .padding(.top, 5)
            .padding(.bottom, 15)
            
            ThiccDivider()
        }
    }
    
    struct PurpleExpiryNotificationView: View {
        let damus_state: DamusState
        let days_remaining: Int
        let expired: Bool
        
        func try_to_open_verified_checkout(product_template_name: String) {
            Task {
                do {
                    let url = try await damus_state.purple.generate_verified_ln_checkout_link(product_template_name: product_template_name)
                    await self.open_url(url: url)
                }
                catch {
                    await self.open_url(url: damus_state.purple.environment.purple_landing_page_url().appendingPathComponent("checkout"))
                }
            }
        }
        
        @MainActor
        func open_url(url: URL) {
            this_app.open(url)
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(self.message())
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(eventviewsize_to_font(.normal, font_size: damus_state.settings.font_size))
                if DEEP_WEBSITE_LINK {
                    // TODO: It might be better to fetch products from the server instead of hardcoding them here. As of writing this is disabled, so not a big concern.
                    HStack {
                        Button(action: {
                            self.try_to_open_verified_checkout(product_template_name: "purple_one_month")
                        }, label: {
                            Text("Renew (1 mo)", comment: "Button to take user to renew subscription for one month")
                        })
                        .buttonStyle(GradientButtonStyle())
                        Button(action: {
                            self.try_to_open_verified_checkout(product_template_name: "purple_one_year")
                        }, label: {
                            Text("Renew (1 yr)", comment: "Button to take user to renew subscription for one year")
                        })
                        .buttonStyle(GradientButtonStyle())
                    }
                }
                else {
                    NavigationLink(destination: DamusPurpleView(damus_state: damus_state), label: {
                        HStack {
                            Text("Manage subscription", comment: "Button to take user to manage Damus Purple subscription")
                                .font(eventviewsize_to_font(.normal, font_size: damus_state.settings.font_size))
                            Image("arrow-right")
                                .font(eventviewsize_to_font(.normal, font_size: damus_state.settings.font_size))
                        }
                    })
                }
            }
        }
        
        func message() -> String {
            if expired == true {
                return NSLocalizedString("Your Purple subscription has expired. Renew?", comment: "A notification message explaining to the user that their Damus Purple Subscription has expired, prompting them to renew.")
            }
            if days_remaining == 1 {
                return NSLocalizedString("Your Purple subscription expires in 1 day. Renew?", comment: "A notification message explaining to the user that their Damus Purple Subscription is expiring in one day, prompting them to renew.")
            }
            let message_format = NSLocalizedString("Your Purple subscription expires in %@ days. Renew?", comment: "A notification message explaining to the user that their Damus Purple Subscription is expiring soon, prompting them to renew.")
            return String(format: message_format, String(days_remaining))
        }
    }
}

// `AppIcon` code from: https://stackoverflow.com/a/65153628 and licensed with CC BY-SA 4.0 with the following modifications:
// - Made image resizable using `.resizable()`
extension Bundle {
    var iconFileName: String? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconFileName = iconFiles.last
        else { return nil }
        return iconFileName
    }
}

fileprivate struct AppIcon: View {
    var body: some View {
        Bundle.main.iconFileName
            .flatMap { UIImage(named: $0) }
            .map { Image(uiImage: $0).resizable() }
    }
}

#Preview {
    VStack {
        ThiccDivider()
        DamusAppNotificationView(damus_state: test_damus_state, notification: .init(content: .purple_impending_expiration(days_remaining: 3, expiry_date: 1709156602), timestamp: Date.now))
    }
}

#Preview {
    DamusAppNotificationView(damus_state: test_damus_state, notification: .init(content: .purple_expired(expiry_date: 1709156602), timestamp: Date.now))
}
