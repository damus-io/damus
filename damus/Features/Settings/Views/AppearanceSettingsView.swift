//
//  TextFormattingSettings.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI

fileprivate let CACHE_CLEAR_BUTTON_RESET_TIME_IN_SECONDS: Double = 60
fileprivate let MINIMUM_CACHE_CLEAR_BUTTON_DELAY_IN_SECONDS: Double = 1

/// A simple type to keep track of the cache clearing state
fileprivate enum CacheClearingState {
    case not_cleared
    case clearing
    case cleared
}

struct ResizedEventPreview: View {
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore

    var body: some View {
        EventView(damus: damus_state, event: test_note, pubkey: test_note.pubkey, options: [.wide, .no_action_bar])
    }
}

struct AppearanceSettingsView: View {
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @Environment(\.dismiss) var dismiss
    @State fileprivate var cache_clearing_state: CacheClearingState = .not_cleared
    @State var showing_cache_clear_alert: Bool = false
    
    @State var showing_enable_animation_alert: Bool = false
    @State var enable_animation_toggle_is_user_initiated: Bool = true

    var FontSize: some View {
        VStack(alignment: .leading) {
            Slider(value: $settings.font_size, in: 0.5...2.0, step: 0.1)
                .padding()

            // Sample text to show how the font size would look
            ResizedEventPreview(damus_state: damus_state, settings: settings)

        }
    }

    var body: some View {
        Form {
            Section(NSLocalizedString("Font Size", comment: "Section label for font size settings.")) {
                FontSize
            }

            // MARK: - Text Truncation
            Section(header: Text("Text Truncation", comment: "Section header for damus text truncation user configuration")) {
                Toggle(NSLocalizedString("Truncate timeline text", comment: "Setting to truncate text in timeline"), isOn: $settings.truncate_timeline_text)
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Truncate notification mention text", comment: "Setting to truncate text in mention notifications"), isOn: $settings.truncate_mention_text)
                    .toggleStyle(.switch)
            }

            Section(header: Text("User Statuses", comment: "Section header for user profile status settings.")) {
                Toggle(NSLocalizedString("Show general statuses", comment: "Settings toggle for enabling general user statuses"), isOn: $settings.show_general_statuses)
                    .toggleStyle(.switch)

                Toggle(NSLocalizedString("Show music statuses", comment: "Settings toggle for enabling now playing music statuses"), isOn: $settings.show_music_statuses)
                    .toggleStyle(.switch)
            }

            // MARK: - Accessibility
            Section(header: Text("Accessibility", comment: "Section header for accessibility settings")) {
                Toggle(NSLocalizedString("Left Handed", comment: "Moves the post button to the left side of the screen"), isOn: $settings.left_handed)
                    .toggleStyle(.switch)
            }
            
            // MARK: - Images
            Section(NSLocalizedString("Images", comment: "Section title for images configuration.")) {
                self.EnableAnimationsToggle
                Toggle(NSLocalizedString("Blur images", comment: "Setting to blur images"), isOn: $settings.blur_images)
                    .toggleStyle(.switch)
                
                Toggle(NSLocalizedString("Media previews", comment: "Setting to show media"), isOn: $settings.media_previews)
                    .toggleStyle(.switch)
                
                Picker(NSLocalizedString("Image uploader", comment: "Prompt selection of user's image uploader"),
                       selection: $settings.default_media_uploader) {
                    ForEach(MediaUploader.allCases, id: \.self) { uploader in
                        Text(uploader.model.displayName)
                            .tag(uploader.model.tag)
                    }
                }

                self.ClearCacheButton
            }
            
            // MARK: - Content filters and moderation
            Section(
                header: Text("Content filters", comment: "Section title for content filtering/moderation configuration."),
                footer: Text("Notes with the #nsfw tag usually contains adult content or other \"Not safe for work\" content", comment: "Section footer clarifying what #nsfw (not safe for work) tags mean")
            ) {
                Toggle(NSLocalizedString("Show replies from your trusted network first", comment: "Setting to show replies in threads from the current user's trusted network first."), isOn: $settings.show_trusted_replies_first)
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Hide notes with #nsfw tags", comment: "Setting to hide notes with the #nsfw (not safe for work) tags"), isOn: $settings.hide_nsfw_tagged_content)
                    .toggleStyle(.switch)
            }
            
            Section(header: Text("Privacy", comment: "Section header for privacy related settings")) {
                Toggle(NSLocalizedString("Share Damus client tag", comment: "Setting to publish a client tag indicating Damus posted the note"), isOn: $settings.publish_client_tag)
                    .toggleStyle(.switch)
                Text("Client tags can help other apps understand new kinds of events. Turn this off if you prefer not to identify Damus when posting.", comment: "Description for the client tag privacy toggle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            // MARK: - Profiles
            Section(
                header: Text("Profiles", comment: "Section title for profile view configuration."),
                footer: Text("Profile action sheets allow you to follow, zap, or DM profiles more quickly without having to view their full profile", comment: "Section footer clarifying what the profile action sheet feature does")
                    .padding(.bottom, tabHeight + getSafeAreaBottom())
            ) {
                Toggle(NSLocalizedString("Show profile action sheets", comment: "Setting to show profile action sheets when clicking on a user's profile picture"), isOn: $settings.show_profile_action_sheet_on_pfp_click)
                    .toggleStyle(.switch)
            }
                

        }
        .navigationTitle(NSLocalizedString("Appearance", comment: "Navigation title for text and appearance settings."))
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
    
    func clear_cache_button_action() {
        cache_clearing_state = .clearing
        
        let group = DispatchGroup()
        
        group.enter()
        DamusCacheManager.shared.clear_cache(damus_state: self.damus_state, completion: {
            group.leave()
        })
        
        // Make clear cache button take at least a second or so to avoid issues with labor perception bias (https://growth.design/case-studies/labor-perception-bias)
        group.enter()
        DispatchQueue.main.asyncAfter(deadline: .now() + MINIMUM_CACHE_CLEAR_BUTTON_DELAY_IN_SECONDS) {
            group.leave()
        }
        
        group.notify(queue: .main) {
            cache_clearing_state = .cleared
            DispatchQueue.main.asyncAfter(deadline: .now() + CACHE_CLEAR_BUTTON_RESET_TIME_IN_SECONDS) {
                cache_clearing_state = .not_cleared
            }
        }
    }
    
    var EnableAnimationsToggle: some View {
        Toggle(NSLocalizedString("Animations", comment: "Toggle to enable or disable image animation"), isOn: $settings.enable_animation)
            .toggleStyle(.switch)
            .onChange(of: settings.enable_animation) { _ in
                if self.enable_animation_toggle_is_user_initiated {
                    self.showing_enable_animation_alert = true
                }
                else {
                    self.enable_animation_toggle_is_user_initiated = true
                }
            }
            .alert(isPresented: $showing_enable_animation_alert) {
                Alert(title: Text("Confirmation", comment: "Confirmation dialog title"),
                      message: Text("Changing this setting will cause the cache to be cleared. This will free space, but images may take longer to load again. Are you sure you want to proceed?", comment: "Message explaining consequences of changing the 'enable animation' setting"),
                      primaryButton: .default(Text("OK", comment: "Button label indicating user wants to proceed.")) {
                          self.clear_cache_button_action()
                      },
                      secondaryButton: .cancel() {
                          // Toggle back if user cancels action
                          self.enable_animation_toggle_is_user_initiated = false
                          settings.enable_animation.toggle()
                      }
                )
            }
    }
    
    var ClearCacheButton: some View {
        Button(action: { self.showing_cache_clear_alert = true }, label: {
            HStack(spacing: 6) {
                switch cache_clearing_state {
                    case .not_cleared:
                        Text("Clear Cache", comment: "Button to clear image cache.")
                    case .clearing:
                        ProgressView()
                        Text("Clearing Cache", comment: "Loading message indicating that the cache is being cleared.")
                    case .cleared:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Cache has been cleared", comment: "Message indicating that the cache was successfully cleared.")
                }
            }
        })
        .disabled(self.cache_clearing_state != .not_cleared)
        .alert(isPresented: $showing_cache_clear_alert) {
            Alert(title: Text("Confirmation", comment: "Confirmation dialog title"),
                  message: Text("Are you sure you want to clear the cache? This will free space, but images may take longer to load again.", comment: "Message explaining what it means to clear the cache, asking if user wants to proceed."),
                  primaryButton: .default(Text("OK", comment: "Button label indicating user wants to proceed.")) {
                      self.clear_cache_button_action()
                  },
                  secondaryButton: .cancel())
        }
    }
}


struct TextFormattingSettings_Previews: PreviewProvider {
    static var previews: some View {
        AppearanceSettingsView(damus_state: test_damus_state, settings: UserSettingsStore())
    }
}
