import Foundation

/// Compiled with the actual platform-independent production sources, without app/framework stubs.
/// This verifies gesture, playback-rate and media-tag rules, not UIKit delivery or iOS lifecycle.
@main
enum VoiceCompositionChecks {
    static func main() throws {
        precondition(VoicePlaybackRate.allCases.map(\.label) == ["1x", "2x", "3x"])
        precondition(VoicePlaybackRate.allCases.map(\.playerRate) == [Float(1.0), Float(1.4), Float(1.7)])
        var rate = VoicePlaybackRate.x1
        for _ in 0..<100 {
            rate.cycle()
            precondition(rate == .x2 && rate.playerRate == 1.4)
            rate.cycle()
            precondition(rate == .x3 && rate.playerRate == 1.7)
            rate.cycle()
            precondition(rate == .x1 && rate.playerRate == 1.0)
        }
        print("PASS: actual playback-rate source: Nosis 1x/2x/3x labels map to 1.0/1.4/1.7; 100 complete cycles.")

        var gesture = VoiceRecordingGesture()
        let mic = CGPoint(x: 38, y: 38)
        let trash = VoiceRecordingGesture.trashCenter
        precondition(gesture.end(at: mic) == nil)
        gesture.move(to: trash)
        precondition(!gesture.isOverTrash)
        gesture.begin()
        gesture.move(to: trash)
        precondition(gesture.isOverTrash)
        gesture.move(to: mic)
        precondition(!gesture.isOverTrash)
        precondition(gesture.end(at: mic) == .finish)
        precondition(gesture.end(at: trash) == nil)
        for _ in 0..<100 {
            gesture.begin()
            precondition(gesture.end(at: trash) == .discard)
            precondition(!gesture.isActive && !gesture.isOverTrash)
            precondition(gesture.end(at: mic) == nil)
            gesture.begin()
            precondition(gesture.end(at: mic, cancelled: true) == .discard)
        }
        precondition(VoiceRecordingGesture.containsTrash(CGPoint(x: -18, y: 38)))
        precondition(!VoiceRecordingGesture.containsTrash(CGPoint(x: -17.9, y: 38)))

        let primary = try VoiceMediaReference(url: "https://blossom.band/audio?exact=1",
            sha256: String(repeating: "a", count: 64), mimeType: "audio/mp4", duration: 2)
        let images = [
            ["imeta", "url https://media.example/one.jpg", "m image/jpeg", "dim 640x480"],
            ["imeta", "url https://media.example/two.jpg", "m image/jpeg", "dim 320x240"]
        ]
        let parsed = try VoiceMediaReference(tags: primary.tags + images + [["r", "https://example.com/article"]])
        precondition(parsed == primary)
        var rejectedConflict = false
        do {
            _ = try VoiceMediaReference(tags: primary.tags + [["imeta", "url " + primary.url, "m image/jpeg"]])
        } catch { rejectedConflict = true }
        precondition(rejectedConflict)
        precondition(!VoiceMediaReference.isHTTPSURL("file:///private/audio.m4a"))
        print("PASS: actual gesture source: enter/leave trash, final position, interrupted/duplicate releases, 100 repeated holds, hit boundary.")
        print("PASS: actual media parser: multiple photo tags preserve primary audio; conflicting photo/audio reference rejected.")
    }
}
