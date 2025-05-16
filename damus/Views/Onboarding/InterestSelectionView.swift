//
//  InterestSelectionView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-16.
//
import SwiftUI

extension OnboardingSuggestionsView {
    
    struct InterestSelectionView: View {
        var next_page: (() -> Void)
        
        // Track selected interests using a Set
        @Binding var selectedInterests: Set<Interest>
        // Track navigation for the next step
        @State private var isNavigating = false
        
        // Validate that the user has selected between up to 5 interests
        private var isNextEnabled: Bool {
            let count = selectedInterests.count
            return count <= 5 && count > 0
        }
        
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
                    Text(NSLocalizedString("Please pick up to 5 interests. This will help us recommend accounts to follow.", comment: "Instruction for interest selection"))
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
                }
                .padding()
            }
        }
    }
    
    // A grid view to display interest options
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
                    let disabled = !selectedInterests.contains(interest) && selectedInterests.count >= 4
                    InterestButton(interest: interest,
                                   isSelected: selectedInterests.contains(interest)) {
                        // Toggle selection
                        if selectedInterests.contains(interest) {
                            selectedInterests.remove(interest)
                        } else if selectedInterests.count < 4 {
                            selectedInterests.insert(interest)
                        }
                    }
                    .disabled(disabled)
                    .opacity(disabled ? 0.5 : 1.0)
                }
            }
        }
    }
    
    // A button view representing a single interest option
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

enum Interest: String, CaseIterable {
    /// Bitcoin-related topics (e.g. Bitcoin, Lightning, e-cash etc)
    case bitcoin = "bitcoin"
    /// Any non-Bitcoin technology-related topic (e.g. Linux, new releases, software development, supersonic flight, etc)
    case technology = "technology"
    /// Any science-related topic (e.g. astronomy, biology, physics, etc)
    case science = "science"
    /// Lifestyle topics (e.g. Worldschooling, Digital nomading, vagabonding, homesteading, digital minimalism, life hacks, etc)
    case lifestyle = "lifestyle"
    /// Travel-related topics (e.g. Information about locations to visit, travel logs, etc)
    case travel = "travel"
    /// Any art-related topic (e.g. poetry, painting, sculpting, photography, etc)
    case art = "art"
    /// Topics focused on improving human health (e.g. advances in medicine, exercising, nutrition, meditation, sleep, etc)
    case health = "health"
    /// Any music-related topic (e.g. Bands, fan pages, instruments, classical music theory, etc)
    case music = "music"
    /// Any topic related to food (e.g. Cooking, recipes, meal planning, nutrition)
    case food = "food"
    /// Any topic related to sports (e.g. Athlete fan pages, general sports information, sports news, sports equipment, etc)
    case sports = "sports"
    /// Any topic related to religion, spirituality, or faith (e.g. Christianity, Judaism, Buddhism, Islamism, Hinduism, Taoism, general meditation practice, etc)
    case religionSpirituality = "religion-spirituality"
    /// General humanities topics (e.g. philosophy, sociology, culture, etc)
    case humanities = "humanities"
    /// General topics about politics
    case politics = "politics"
    /// Other miscellaneous topics that do not fit in any of the previous items of the list
    case other = "other"
    
    var label: String {
        switch self {
        case .bitcoin:
            return NSLocalizedString("₿ Bitcoin", comment: "Interest topic label")
        case .technology:
            return NSLocalizedString("💻 Tech", comment: "Interest topic label")
        case .science:
            return NSLocalizedString("🔭 Science", comment: "Interest topic label")
        case .lifestyle:
            return NSLocalizedString("🏝️ Lifestyle", comment: "Interest topic label")
        case .travel:
            return NSLocalizedString("✈️ Travel", comment: "Interest topic label")
        case .art:
            return NSLocalizedString("🎨 Art", comment: "Interest topic label")
        case .health:
            return NSLocalizedString("🏃 Health", comment: "Interest topic label")
        case .music:
            return NSLocalizedString("🎶 Music", comment: "Interest topic label")
        case .food:
            return NSLocalizedString("🍱 Food", comment: "Interest topic label")
        case .sports:
            return NSLocalizedString("⚾️ Sports", comment: "Interest topic label")
        case .religionSpirituality:
            return NSLocalizedString("🛐 Religion", comment: "Interest topic label")
        case .humanities:
            return NSLocalizedString("📚 Humanities", comment: "Interest topic label")
        case .politics:
            return NSLocalizedString("🏛️ Politics", comment: "Interest topic label")
        case .other:
            return NSLocalizedString("♾️ Other", comment: "Interest topic label")
        }
    }
}

struct InterestSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingSuggestionsView.InterestSelectionView(
            next_page: { print("next") },
            selectedInterests: Binding.constant(Set([Interest.art, Interest.music]))
        )
    }
}
