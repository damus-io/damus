//
//  DamusVideoPlayerFallbackTests.swift
//  damusTests
//
//  Tests for KSMEPlayer fallback integration.
//

import XCTest
import AVFoundation
@testable import damus

#if KSPLAYER_ENABLED
import KSPlayer
#endif

// MARK: - Error Classification Tests (no KSPlayer dependency needed)

final class DamusVideoPlayerErrorClassificationTests: XCTestCase {

    @MainActor
    private func makePlayer() -> DamusVideoPlayer {
        // Use a dummy URL — we're testing error classification, not playback
        return DamusVideoPlayer(url: URL(string: "https://example.com/test.mp4")!)
    }

    @MainActor
    func test_network_error_does_not_trigger_fallback() {
        let player = makePlayer()
        let error = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: nil) // Not connected to internet
        XCTAssertFalse(player.isLikelyDecodeError(error))
    }

    @MainActor
    func test_decode_error_triggers_fallback() {
        let player = makePlayer()
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.decoderNotFound.rawValue, userInfo: nil)
        XCTAssertTrue(player.isLikelyDecodeError(error))
    }

    @MainActor
    func test_unknown_avfoundation_error_triggers_fallback() {
        let player = makePlayer()
        let error = NSError(domain: AVFoundationErrorDomain, code: -99999, userInfo: nil)
        XCTAssertTrue(player.isLikelyDecodeError(error))
    }

    @MainActor
    func test_drm_error_does_not_trigger_fallback() {
        let player = makePlayer()
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.contentIsProtected.rawValue, userInfo: nil)
        XCTAssertFalse(player.isLikelyDecodeError(error))
    }

    @MainActor
    func test_server_error_does_not_trigger_fallback() {
        let player = makePlayer()
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.serverIncorrectlyConfigured.rawValue, userInfo: nil)
        XCTAssertFalse(player.isLikelyDecodeError(error))
    }

    @MainActor
    func test_not_authorized_error_does_not_trigger_fallback() {
        let player = makePlayer()
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.contentIsNotAuthorized.rawValue, userInfo: nil)
        XCTAssertFalse(player.isLikelyDecodeError(error))
    }

    @MainActor
    func test_no_longer_playable_error_does_not_trigger_fallback() {
        let player = makePlayer()
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.noLongerPlayable.rawValue, userInfo: nil)
        XCTAssertFalse(player.isLikelyDecodeError(error))
    }

    @MainActor
    func test_wrapped_network_error_does_not_trigger_fallback() {
        let player = makePlayer()
        let networkError = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: nil)
        let wrappedError = NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [
            NSUnderlyingErrorKey: networkError
        ])
        XCTAssertFalse(player.isLikelyDecodeError(wrappedError))
    }

    @MainActor
    func test_wrapped_decode_error_triggers_fallback() {
        let player = makePlayer()
        let coreMediaError = NSError(domain: "CoreMediaErrorDomain", code: -12909, userInfo: nil)
        let wrappedError = NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [
            NSUnderlyingErrorKey: coreMediaError
        ])
        XCTAssertTrue(player.isLikelyDecodeError(wrappedError))
    }

    @MainActor
    func test_core_media_error_triggers_fallback() {
        let player = makePlayer()
        let error = NSError(domain: "CoreMediaErrorDomain", code: -12345, userInfo: nil)
        XCTAssertTrue(player.isLikelyDecodeError(error))
    }

    @MainActor
    func test_osstatus_error_triggers_fallback() {
        let player = makePlayer()
        let error = NSError(domain: NSOSStatusErrorDomain, code: -12909, userInfo: nil)
        XCTAssertTrue(player.isLikelyDecodeError(error))
    }

    @MainActor
    func test_nil_error_triggers_fallback() {
        let player = makePlayer()
        XCTAssertTrue(player.isLikelyDecodeError(nil))
    }

    @MainActor
    func test_unknown_domain_does_not_trigger_fallback() {
        let player = makePlayer()
        let error = NSError(domain: "com.apple.coreaudio.avfaudio", code: 1, userInfo: nil)
        XCTAssertFalse(player.isLikelyDecodeError(error))
    }
}

// MARK: - classify_url extension tests

final class ClassifyUrlVideoExtensionTests: XCTestCase {

    func test_classify_url_webm() {
        let url = URL(string: "https://example.com/video.webm")!
        let result = classify_url(url)
        if case .media(.video(let classifiedUrl)) = result {
            XCTAssertEqual(classifiedUrl, url)
        } else {
            XCTFail("Expected .media(.video) for .webm URL, got \(result)")
        }
    }

    func test_classify_url_mkv() {
        let url = URL(string: "https://example.com/video.mkv")!
        let result = classify_url(url)
        if case .media(.video(let classifiedUrl)) = result {
            XCTAssertEqual(classifiedUrl, url)
        } else {
            XCTFail("Expected .media(.video) for .mkv URL, got \(result)")
        }
    }

    func test_classify_url_mp4_still_works() {
        let url = URL(string: "https://example.com/video.mp4")!
        let result = classify_url(url)
        if case .media(.video(let classifiedUrl)) = result {
            XCTAssertEqual(classifiedUrl, url)
        } else {
            XCTFail("Expected .media(.video) for .mp4 URL, got \(result)")
        }
    }
}

// MARK: - Fallback Integration Tests (KSPlayer required)
//
// These tests are gated behind KSPLAYER_ENABLED because they depend on
// KSPlayer types (MediaPlayerProtocol, KSOptions, etc.).
//
// damusTests does NOT link KSPlayer and does NOT define KSPLAYER_ENABLED,
// so this block compiles out in CI. This is due to an FFmpegKit packaging
// issue: its xcframework is missing libzvbi symbols when the SPM build
// system links KSPlayer as a separate test-bundle framework.
//
// To run these tests locally:
//   1. Open damus.xcodeproj in Xcode
//   2. Add KSPlayer to damusTests target's package dependencies
//   3. Add KSPLAYER_ENABLED to damusTests build settings
//      (SWIFT_ACTIVE_COMPILATION_CONDITIONS)
//   4. Build and run tests on a physical device (not simulator)

#if KSPLAYER_ENABLED

/// Stub player conforming to MediaPlayerProtocol for testing.
final class StubFallbackPlayer: NSObject, MediaPlayerProtocol {
    weak var delegate: (any MediaPlayerDelegate)?
    var view: UIView? = UIView()
    var playableTime: TimeInterval = 0
    var isReadyToPlay: Bool = false
    var playbackState: MediaPlaybackState = .stopped
    var loadState: MediaLoadState = .idle
    var isPlaying: Bool = false
    var seekable: Bool = true
    var isMuted: Bool = false
    var allowsExternalPlayback: Bool = false
    var usesExternalPlaybackWhileExternalScreenIsActive: Bool = false
    var isExternalPlaybackActive: Bool = false
    var playbackRate: Float = 1.0
    var playbackVolume: Float = 1.0
    var contentMode: UIViewContentMode = .scaleAspectFit
    var subtitleDataSouce: (any SubtitleDataSouce)? = nil
    var dynamicInfo: DynamicInfo? = nil

    // MediaPlayback
    var duration: TimeInterval = 120
    var fileSize: Double = 0
    var naturalSize: CGSize = CGSize(width: 1920, height: 1080)
    var chapters: [Chapter] = []
    var currentPlaybackTime: TimeInterval = 0

    // Track recording
    var prepareToPlayCalled = false
    var playCalled = false
    var pauseCalled = false
    var shutdownCalled = false
    var seekTime: TimeInterval?

    required init(url: URL, options: KSOptions) {
        super.init()
    }

    override init() {
        super.init()
    }

    func replace(url: URL, options: KSOptions) {}
    func play() { playCalled = true; isPlaying = true }
    func pause() { pauseCalled = true; isPlaying = false }
    func prepareToPlay() { prepareToPlayCalled = true }
    func shutdown() { shutdownCalled = true }
    func enterBackground() {}
    func enterForeground() {}
    func thumbnailImageAtCurrentTime() async -> CGImage? { nil }

    private var audioTracks: [any MediaPlayerTrack] = []
    func setAudioTracks(_ tracks: [any MediaPlayerTrack]) {
        audioTracks = tracks
    }

    func tracks(mediaType: AVMediaType) -> [any MediaPlayerTrack] {
        if mediaType == .audio { return audioTracks }
        return []
    }

    func select(track: some MediaPlayerTrack) {}
    func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void)) {
        seekTime = time
        currentPlaybackTime = time
        completion(true)
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    var playbackCoordinator: AVPlaybackCoordinator {
        fatalError("Not implemented for stub")
    }

    @available(tvOS 14.0, *)
    var pipController: KSPictureInPictureController? { nil }
}

struct StubFallbackPlayerFactory: FallbackPlayerFactory {
    let stubPlayer: StubFallbackPlayer

    func makeFallbackPlayer(url: URL, options: KSOptions) -> any MediaPlayerProtocol {
        return stubPlayer
    }
}

final class DamusVideoPlayerFallbackTests: XCTestCase {

    @MainActor
    private func makePlayerWithStub() -> (DamusVideoPlayer, StubFallbackPlayer) {
        let stub = StubFallbackPlayer()
        let factory = StubFallbackPlayerFactory(stubPlayer: stub)
        let player = DamusVideoPlayer(url: URL(string: "https://example.com/test.mp4")!, fallbackFactory: factory)
        return (player, stub)
    }

    /// Yields to the main runloop so queued DispatchQueue.main.async blocks execute
    /// before assertions. Delegate callbacks dispatch state mutations asynchronously.
    @MainActor
    private func yieldToMainRunloop() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    @MainActor
    func test_fallback_state_mapping_readyToPlay() async {
        let (player, stub) = makePlayerWithStub()

        // Fallback is not active — we're testing delegate methods in isolation
        XCTAssertFalse(player.is_using_fallback)

        // Simulate readyToPlay delegate (dispatches state mutations to main)
        player.readyToPlay(player: stub)
        await yieldToMainRunloop()

        XCTAssertFalse(player.is_loading)
        XCTAssertEqual(player.video_size, CGSize(width: 1920, height: 1080))
    }

    @MainActor
    func test_fallback_readyToPlay_clears_loading() async {
        let (player, stub) = makePlayerWithStub()

        // Before readyToPlay, is_loading should be true (default)
        XCTAssertTrue(player.is_loading)

        // Simulate delegate (dispatches state mutations to main)
        player.readyToPlay(player: stub)
        await yieldToMainRunloop()
        XCTAssertFalse(player.is_loading)
    }

    @MainActor
    func test_finish_with_error_resets_is_playing() async {
        let (player, stub) = makePlayerWithStub()

        player.is_playing = true
        let error = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        player.finish(player: stub, error: error)
        await yieldToMainRunloop()

        XCTAssertFalse(player.is_loading)
        XCTAssertFalse(player.is_playing)
    }

    @MainActor
    func test_finish_without_error_does_nothing() {
        let (player, stub) = makePlayerWithStub()

        player.is_playing = true
        player.finish(player: stub, error: nil)

        // No dispatch — guard returns early. No yield needed.
        XCTAssertTrue(player.is_playing)
    }

    @MainActor
    func test_changeLoadState_loading() async {
        let (player, stub) = makePlayerWithStub()

        stub.loadState = .loading
        player.changeLoadState(player: stub)
        await yieldToMainRunloop()
        XCTAssertTrue(player.is_loading)
    }

    @MainActor
    func test_changeLoadState_playable() async {
        let (player, stub) = makePlayerWithStub()

        stub.loadState = .playable
        player.changeLoadState(player: stub)
        await yieldToMainRunloop()
        XCTAssertFalse(player.is_loading)
    }

    @MainActor
    func test_changeBuffering_below_100() async {
        let (player, stub) = makePlayerWithStub()
        player.changeBuffering(player: stub, progress: 50)
        await yieldToMainRunloop()
        XCTAssertTrue(player.is_loading)
    }

    @MainActor
    func test_changeBuffering_at_100() async {
        let (player, stub) = makePlayerWithStub()
        player.changeBuffering(player: stub, progress: 100)
        await yieldToMainRunloop()
        XCTAssertFalse(player.is_loading)
    }

    @MainActor
    func test_audio_session_after_restore() {
        // Directly test that DamusAudioSession.restore() sets the expected category
        DamusAudioSession.restore()
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playback)
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers))
    }
}

#endif
