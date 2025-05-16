//
//  OnboardingContentSettings.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-19.
//
import SwiftUI

extension OnboardingSuggestionsView {
    struct OnboardingContentSettings: View {
        var model: SuggestedUsersViewModel
        var next_page: (() -> Void)
        @ObservedObject var settings: UserSettingsStore

        @Binding var selectedInterests: Set<Interest>

        private var isNextEnabled: Bool { true }

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    Text(NSLocalizedString("Other preferences", comment: "Screen title for content preferences screen during onboarding"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                    
                    // Instruction subtitle
                    Text(NSLocalizedString("Tweak these settings to better match your preferences", comment: "Instructions for content preferences screen during onboarding"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Content preferences section with toggles
                    Section() {
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle(NSLocalizedString("Hide notes with #nsfw tags", comment: "Setting to hide notes with not safe for work tags"), isOn: $settings.hide_nsfw_tagged_content)
                                .toggleStyle(.switch)
                            
                            Text(NSLocalizedString("Notes with the #nsfw tag usually contains adult content or other \"Not safe for work\" content", comment: "Explanation of what NSFW means"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 10)
                            
                            if !selectedInterests.contains(.bitcoin) {
                                Toggle(
                                    NSLocalizedString("Show Bitcoin-heavy profile suggestions", comment: "Setting label during onboarding"),
                                    isOn: Binding(get: { !model.reduceBitcoinContent }, set: { model.reduceBitcoinContent = !$0 })
                                )
                                .toggleStyle(.switch)
                                
                                Text(NSLocalizedString("Some profiles tend to have a lot of Bitcoin-related content alongside their topics of interest. Disable this setting if you prefer to filter out follow suggestions that frequently talk about Bitcoin.", comment: "Explanation label for the 'Show Bitcoin-heavy profile suggestions' onboarding toggle setting"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        self.next_page()
                    }, label: {
                        Text(NSLocalizedString("Next", comment: "Next button title"))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                    })
                    .buttonStyle(GradientButtonStyle())
                    .disabled(!isNextEnabled)
                    .opacity(isNextEnabled ? 1.0 : 0.5)
                    .padding([.leading, .trailing, .bottom])
                }
                .padding()
            }
        }
    }
}
