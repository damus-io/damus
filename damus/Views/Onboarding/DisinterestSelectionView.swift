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

        // Track selected disinterests using a Set
        @Binding var selectedDisinterests: Set<Interest>

        // In this view, we assume there is no strict lower or upper bound,
        // so the Next button is always enabled.
        private var isNextEnabled: Bool {
            true
        }

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    Text(NSLocalizedString("Select Your Dislikes", comment: "Screen title for disinterest selection"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                    
                    // Instruction subtitle
                    Text(NSLocalizedString("Choose any topics you are not interested in. We will avoid recommending similar accounts.", comment: "Instruction for disinterest selection"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Disinterests grid view (leveraging the same InterestsGridView)
                    // You can reuse the InterestsGridView for simplicity since the UI component
                    // for selecting topics remains similar. Alternatively, you can create a separate
                    // grid view if you wish to apply different styling or behavior.
                    InterestsGridView(availableInterests: Interest.allCases,
                                      selectedInterests: $selectedDisinterests)
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
