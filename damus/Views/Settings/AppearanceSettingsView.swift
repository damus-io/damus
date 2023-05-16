//
//  TextFormattingSettings.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI


struct AppearanceSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text(NSLocalizedString("Text Truncation", comment: "Section header for damus text truncation user configuration"))) {
                Toggle(NSLocalizedString("Truncate timeline text", comment: "Setting to truncate text in timeline"), isOn: $settings.truncate_timeline_text)
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Truncate notification mention text", comment: "Setting to truncate text in mention notifications"), isOn: $settings.truncate_mention_text)
                    .toggleStyle(.switch)
            }
            
            Section(header: Text(NSLocalizedString("Accessibility", comment: "Section header for accessibility settings"))) {
                Toggle(NSLocalizedString("Left Handed", comment: "Moves the post button to the left side of the screen"), isOn: $settings.left_handed)
                    .toggleStyle(.switch)
            }

            Section(NSLocalizedString("GIF Attachment", comment: "Section for GIF Attachment configuration.")) {
                Picker(NSLocalizedString("GIF source", comment: "Prompt selection of GIF Source."), selection: $settings.gif_source) {
                    ForEach(GIFSource.allCases, id: \.self) { source in
                        Text(source.model.displayName)
                            .tag(source.model.tag)
                    }
                }
                
                if settings.gif_source == .giphy {
                    SecureField(NSLocalizedString("API Key (required)", comment: "Prompt selection of GIF Source API."), text: $settings.giphy_api_key)
                        .disableAutocorrection(true)
                        .disabled(settings.gif_source != .giphy)
                        .autocapitalization(UITextAutocapitalizationType.none)
                    
                }

                if settings.giphy_api_key == "" && settings.gif_source == .giphy {
                    Link(NSLocalizedString("Get API Key", comment: "Button to navigate to Giphy website to get an API key."), destination: URL(string: "https://developers.giphy.com/docs/api")!)
                }
            }

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
                

        }
        .navigationTitle(NSLocalizedString("Appearance", comment: "Navigation title for text and appearance settings."))
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
}


struct TextFormattingSettings_Previews: PreviewProvider {
    static var previews: some View {
        AppearanceSettingsView(settings: UserSettingsStore())
    }
}
