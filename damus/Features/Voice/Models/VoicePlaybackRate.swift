/// Nosis-compatible speed labels and their deliberately gentler playback rates.
/// Keep labels separate from rates: the 2x and 3x controls mean 1.4 and 1.7.
enum VoicePlaybackRate: CaseIterable {
    case x1
    case x2
    case x3

    var label: String {
        switch self {
        case .x1: return "1x"
        case .x2: return "2x"
        case .x3: return "3x"
        }
    }

    var playerRate: Float {
        switch self {
        case .x1: return 1.0
        case .x2: return 1.4
        case .x3: return 1.7
        }
    }

    mutating func cycle() {
        switch self {
        case .x1: self = .x2
        case .x2: self = .x3
        case .x3: self = .x1
        }
    }
}
