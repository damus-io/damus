//
//  Interests.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-06-25.
//

import Foundation

struct DIP06 {
    /// Standard general interest topics.
    /// See https://github.com/damus-io/dips/pull/3
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
}

