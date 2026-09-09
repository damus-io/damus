import Foundation

/// Coordinates are relative to the 76-point microphone; the trash center is 96 points left.
struct VoiceRecordingGesture {
    enum Release: Equatable { case finish, discard }
    static let trashCenter = CGPoint(x: -58, y: 38)
    static let trashRadius: CGFloat = 40
    private(set) var isActive = false
    private(set) var isOverTrash = false

    static func containsTrash(_ location: CGPoint) -> Bool {
        let dx = location.x - trashCenter.x, dy = location.y - trashCenter.y
        return dx * dx + dy * dy <= trashRadius * trashRadius
    }

    mutating func begin() {
        isActive = true
        isOverTrash = false
    }

    mutating func move(to location: CGPoint) {
        guard isActive else { return }
        isOverTrash = Self.containsTrash(location)
    }

    /// Sample the final position, not a stale hover flag. Each touch has exactly one release.
    mutating func end(at location: CGPoint, cancelled: Bool = false) -> Release? {
        guard isActive else { return nil }
        let result: Release = cancelled || Self.containsTrash(location) ? .discard : .finish
        isActive = false
        isOverTrash = false
        return result
    }
}
