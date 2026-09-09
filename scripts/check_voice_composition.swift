import Foundation

/// Compiled with the actual platform-independent production sources, without app/framework stubs.
/// This verifies gesture, playback-rate and media-tag rules, not UIKit delivery or iOS lifecycle.
@main
enum VoiceCompositionChecks {
    /// Exercise the actual read-side parser with NIP-808/NIP-92 wire fields.
    static func checkAttachments() throws {
        let recording = URL(string: "https://media.example/recording.mp4?token=A%2FB")!
        let alias = URL(string: "https://MEDIA.example:443/recording.mp4?token=A%2FB#display")!
        let photo = URL(string: "https://media.example/photo?token=AbC%2F123")!
        let secondPhoto = URL(string: "https://media.example/second-photo")!
        let video = URL(string: "https://media.example/video?token=KeepCase")!
        let inlineVideo = URL(string: "https://media.example/inline.mp4")!
        let article = URL(string: "https://example.com/route")!
        let extraAudio = URL(string: "https://media.example/extra.mp4")!
        let tags = [
            ["url", recording.absoluteString],
            ["imeta", "url " + recording.absoluteString, "m audio/mp4"],
            ["imeta", "url " + photo.absoluteString, "m image/JPEG; charset=utf-8", "alt Map of the walking route", "dim 1200x800"],
            ["imeta", "url " + secondPhoto.absoluteString, "alt The footbridge where the walk starts"],
            ["imeta", "url " + video.absoluteString, "m VIDEO/MP4"],
            ["r", article.absoluteString, "Riverside walking route"],
            ["imeta", "url " + extraAudio.absoluteString, "m audio/mp4"],
            ["r", photo.absoluteString],
            ["r", alias.absoluteString]
        ]
        let wireTags = try JSONDecoder().decode([[String]].self, from: JSONEncoder().encode(tags))
        // VoiceIntegrationTests exercises nostrdb blocks and attributed-link extraction on iOS.
        // Keep this executable portable across Foundation implementations.
        let contentURLs = [photo, inlineVideo, alias, recording]
        let parsed = VoiceAttachmentReferences(tags: wireTags, contentURLs: contentURLs).attachments
        precondition(parsed.map(\.url) == [photo, inlineVideo, secondPhoto, video, article, extraAudio])
        precondition(parsed.map(\.kind) == [.image, .video, .image, .video, .link, .link])
        precondition(parsed[4].title == "Riverside walking route")
        precondition(parsed[0].url.absoluteString == photo.absoluteString)

        let oldCache = parsed.filter { $0.kind != .video }.map(\.url)
        let recovered = VoiceAttachmentReferences(tags: wireTags, contentURLs: contentURLs, cachedURLs: oldCache).attachments
        precondition(recovered == parsed)
        precondition(VoiceAttachmentReferences(tags: wireTags, contentURLs: contentURLs, cachedURLs: recovered.map(\.url)).attachments == parsed)
        let tagsOnly = VoiceAttachmentReferences(tags: wireTags).attachments
        precondition(tagsOnly.map(\.url) == [photo, secondPhoto, video, article, extraAudio])

        let queryVariant = URL(string: "https://media.example/recording.mp4?token=a%2Fb")!
        precondition(VoiceAttachmentReferences(tags: [["url", recording.absoluteString]],
            contentURLs: [recording, alias, queryVariant]).attachments.map(\.url) == [queryVariant])
        precondition(VoiceAttachmentReferences(tags: [["url", recording.absoluteString], ["url", inlineVideo.absoluteString]],
            contentURLs: [recording, alias, inlineVideo, photo]).attachments.map(\.url) == [photo])

        let conflict = VoiceAttachmentReferences(tags: [
            ["imeta", "url " + photo.absoluteString, "m image/jpeg"],
            ["imeta", "url " + photo.absoluteString, "m video/mp4"]
        ]).attachments
        precondition(conflict.count == 1 && conflict[0].kind == .link)
        let malformed = VoiceAttachmentReferences(tags: [
            ["imeta", "url " + photo.absoluteString, "url " + video.absoluteString],
            ["imeta", "url " + photo.absoluteString, "url file:///private/other.jpg"],
            ["imeta", "url file:///private/image.jpg", "m image/jpeg"],
            ["r", "javascript:alert(1)"],
            ["r", "wss://relay.example"],
            ["r", "https://user:password@media.example/private.jpg"]
        ]).attachments
        precondition(malformed.isEmpty)
        print("PASS: actual read-side attachments: tag-only/mixed photos, videos and links; optional MIME; exact URLs; cached order; duplicates; primary aliases/conflicts excluded.")
    }

    static func main() throws {
        try checkAttachments()
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
