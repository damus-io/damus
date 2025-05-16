//
//  DisinterestSelectionView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-19.
//
import SwiftUI

extension OnboardingSuggestionsView {
    struct DisinterestSelectionView: View {
        var next_page: (() -> Void)
        @ObservedObject var settings: UserSettingsStore

        @Binding var selectedInterests: Set<Interest>

        // In this view, we assume there is no strict lower or upper bound,
        // so the Next button is always enabled.
        private var isNextEnabled: Bool {
            true
        }

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
                                Toggle(NSLocalizedString("Reduce Bitcoin content", comment: "Setting to reduce Bitcoin-related content"), isOn: $settings.reduce_bitcoin_content)
                                    .toggleStyle(.switch)
                                
                                Text(NSLocalizedString("There tends to be a lot of Bitcoin-related discussions in the network. Enable this if you prefer to see less of that content.", comment: "Explanation for the reduce Bitcoin content toggle"))
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
                    
                    // Next button that updates the disinterests in the view model and moves to the next step.
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
