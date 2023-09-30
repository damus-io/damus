//
//  TextFormattingSettings.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI


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
            Section(header: Text(NSLocalizedString("Text Truncation", comment: "Section header for damus text truncation user configuration"))) {
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
            Section(header: Text(NSLocalizedString("Accessibility", comment: "Section header for accessibility settings"))) {
                Toggle(NSLocalizedString("Left Handed", comment: "Moves the post button to the left side of the screen"), isOn: $settings.left_handed)
                    .toggleStyle(.switch)
            }
            
            // MARK: - Images
            Section(NSLocalizedString("Images", comment: "Section title for images configuration.")) {
                Toggle(NSLocalizedString("Animations", comment: "Toggle to enable or disable image animation"), isOn: $settings.enable_animation)
                    .toggleStyle(.switch)
                    .onChange(of: settings.enable_animation) { _ in
                        clear_kingfisher_cache()
                    }
                Toggle(NSLocalizedString("Always show images", comment: "Setting to always show and never blur images"), isOn: $settings.always_show_images)
                    .toggleStyle(.switch)
                
                Picker(NSLocalizedString("Image uploader", comment: "Prompt selection of user's image uploader"),
                       selection: $settings.default_media_uploader) {
                    ForEach(MediaUploader.allCases, id: \.self) { uploader in
                        Text(uploader.model.displayName)
                            .tag(uploader.model.tag)
                    }
                }

                Button(NSLocalizedString("Clear Cache", comment: "Button to clear image cache.")) {
                    clear_kingfisher_cache()
                }
            }
            
            // MARK: - Content filters and moderation
            Section(
                header: Text(NSLocalizedString("Content filters", comment: "Section title for content filtering/moderation configuration.")),
                footer: Text(NSLocalizedString("Notes with the #nsfw tag usually contains adult content or other \"Not safe for work\" content", comment: "Section footer clarifying what #nsfw (not safe for work) tags mean"))
            ) {
                Toggle(NSLocalizedString("Hide notes with #nsfw tags", comment: "Setting to hide notes with the #nsfw (not safe for work) tags"), isOn: $settings.hide_nsfw_tagged_content)
                    .toggleStyle(.switch)
            }
                

        }
        .navigationTitle(NSLocalizedString("Appearance", comment: "Navigation title for text and appearance settings."))
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
}


struct TextFormattingSettings_Previews: PreviewProvider {
    static var previews: some View {
        AppearanceSettingsView(damus_state: test_damus_state, settings: UserSettingsStore())
    }
}
