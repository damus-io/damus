//
//  InterestSelectionView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-16.
//
import SwiftUI

extension OnboardingSuggestionsView {
    typealias Interest = DIP06.Interest
    
    struct InterestSelectionView: View {
        var damus_state: DamusState
        var next_page: (() -> Void)
        
        /// Track selected interests using a Set
        @Binding var selectedInterests: Set<Interest>
        var isNextEnabled: Bool
        
        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    Text(NSLocalizedString("Select Your Interests", comment: "Screen title for interest selection"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                    
                    // Instruction subtitle
                    Text(NSLocalizedString("Please pick your interests. This will help us recommend accounts to follow.", comment: "Instruction for interest selection"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Interests grid view
                    InterestsGridView(availableInterests: Interest.allCases,
                                      selectedInterests: $selectedInterests)
                    .padding()
                    
                    Spacer()
                    
                    // Next button wrapped inside a NavigationLink for easy transition.
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
                    .accessibilityIdentifier(AppAccessibilityIdentifiers.onboarding_interest_page_next_page.rawValue)
                }
                .padding()
            }
        }
    }
    
    /// A grid view to display interest options
    struct InterestsGridView: View {
        let availableInterests: [Interest]
        @Binding var selectedInterests: Set<Interest>
        
        // Adaptive grid layout with two columns
        private let columns = [
            GridItem(.adaptive(minimum: 120, maximum: 480)),
            GridItem(.adaptive(minimum: 120, maximum: 480)),
        ]
        
        var body: some View {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(availableInterests, id: \ .self) { interest in
                    let disabled = false
                    InterestButton(interest: interest,
                                   isSelected: selectedInterests.contains(interest)) {
                        // Toggle selection
                        if selectedInterests.contains(interest) {
                            selectedInterests.remove(interest)
                        } else {
                            selectedInterests.insert(interest)
                        }
                    }
                    .accessibilityIdentifier(AppAccessibilityIdentifiers.onboarding_interest_option_button.rawValue)
                    .disabled(disabled)
                    .opacity(disabled ? 0.5 : 1.0)
                }
            }
        }
    }
    
    /// A button view representing a single interest option
    struct InterestButton: View {
        let interest: Interest
        let isSelected: Bool
        var action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(interest.label)
                    .font(.body)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                    .foregroundColor(isSelected ? Color.white : Color.primary)
                    .cornerRadius(50)
            }
        }
    }
}

struct InterestSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingSuggestionsView.InterestSelectionView(
            damus_state: test_damus_state,
            next_page: { print("next") },
            selectedInterests: Binding.constant(Set([DIP06.Interest.art, DIP06.Interest.music])), isNextEnabled: true
        )
    }
}
