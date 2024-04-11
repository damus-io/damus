//
//  VideoCacheTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2024-04-03.
//

import Foundation
import XCTest
@testable import damus

// TODO: Reduce test dependency on external factors such as external URLs.
let TEST_VIDEO_URL = "http://cdn.jb55.com/s/zaps-build.mp4"
let LONG_TEST_EXPIRY_TIME: TimeInterval = 60 * 60 * 24    // A long expiry time for a video (in seconds).
let SHORT_TEST_EXPIRY_TIME: TimeInterval = 15             // A short expiry time for a video (in seconds). Must be as short as possible but large enough to allow some test operations to occur
let CACHE_SAVE_TIME_TIMEOUT: TimeInterval = 8             // How long the test will wait for the cache to save a file (in seconds)
let EXPIRY_TIME_MARGIN: TimeInterval = 3                  // The extra time we will wait after expected expiry, to avoid test timing issues. (in seconds)

final class VideoCacheTests: XCTestCase {
    
    func testCachedURLForExistingVideo() throws {
        // Create a temporary directory for the cache
        let test_cache_directory = FileManager.default.temporaryDirectory.appendingPathComponent("test_video_cache")
        
        // Create a test video file
        let original_video_url = URL(string: TEST_VIDEO_URL)!
        FileManager.default.createFile(atPath: original_video_url.path, contents: Data(), attributes: nil)
        
        // Create a VideoCache instance with the temporary cache directory
        let test_expiry_time: TimeInterval = 10
        let video_cache = try VideoCache(cache_url: test_cache_directory, expiry_time: test_expiry_time)!
        
        // Call the maybe_cached_url_for method with the test video URL
        let expected_cache_url = video_cache.url_to_cached_url(url: original_video_url)
        let maybe_cached_url = try video_cache.maybe_cached_url_for(video_url: original_video_url)
        
        // Assert that the returned URL is the same as the original
        XCTAssertEqual(maybe_cached_url, original_video_url, "Returned URL should be the same as the original video URL on the first time we download it")

        // Check that next time we get this video, we get the cached URL.
        let cached_url_expectation = XCTestExpectation(description: "On second time we get a video, the cached URL should be returned")
        let start_time = Date()
        while Date().timeIntervalSince(start_time) < CACHE_SAVE_TIME_TIMEOUT {
            let maybe_cached_url = try video_cache.maybe_cached_url_for(video_url: original_video_url)
            if maybe_cached_url == expected_cache_url {
                cached_url_expectation.fulfill()
                break
            }
            sleep(1)
        }
        wait(for: [cached_url_expectation], timeout: CACHE_SAVE_TIME_TIMEOUT)

        // Now wait for the remaining time until the expiry time + a margin
        let remaining_time = test_expiry_time + EXPIRY_TIME_MARGIN - Date().timeIntervalSince(start_time)

        // Wait for the expiry time to pass
        sleep(UInt32(max(remaining_time, 0)))
        
        // Call the periodic_purge method to purge expired video items
        video_cache.periodic_purge()

        // Call the maybe_cached_url_for method again
        let maybe_cached_url_after_expiry = try video_cache.maybe_cached_url_for(video_url: original_video_url)

        // Assert that the returned URL is the same as the original video URL, since the cache should have expired.
        XCTAssertEqual(maybe_cached_url_after_expiry, original_video_url, "Video cache should expire after expiry time")
        
        // Clean up the temporary files and directory
        try FileManager.default.removeItem(at: test_cache_directory)
    }
    
    func testClearCache() throws {
        // Create a temporary directory for the cache
        let test_cache_directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("test_video_cache")
        try FileManager.default.createDirectory(at: test_cache_directory, withIntermediateDirectories: true, attributes: nil)
        
        // Create a test video file
        let original_video_url = URL(string: TEST_VIDEO_URL)!
        FileManager.default.createFile(atPath: original_video_url.path, contents: Data(), attributes: nil)
        
        // Create a VideoCache instance with the temporary cache directory and a longer expiry time
        let expiry_time: TimeInterval = LONG_TEST_EXPIRY_TIME
        let video_cache = try VideoCache(cache_url: test_cache_directory, expiry_time: expiry_time)!

        // Request the cached URL for the test video to create the cached file
        let expected_cache_url = video_cache.url_to_cached_url(url: original_video_url)
        let _ = try video_cache.maybe_cached_url_for(video_url: original_video_url)

        // Check that next time we get this video, we get the cached URL.
        let cached_url_expectation = XCTestExpectation(description: "On second time we get a video, the cached URL should be returned")
        let start_time = Date()
        while Date().timeIntervalSince(start_time) < CACHE_SAVE_TIME_TIMEOUT {
            let maybe_cached_url = try video_cache.maybe_cached_url_for(video_url: original_video_url)
            if maybe_cached_url == expected_cache_url {
                cached_url_expectation.fulfill()
                break
            }
            sleep(1)
        }
        wait(for: [cached_url_expectation], timeout: CACHE_SAVE_TIME_TIMEOUT)

        // Call the periodic_purge method
        DamusCacheManager.shared.clear_cache(damus_state: test_damus_state, completion: {
            // Assert that fetching the cached URL after clearing cache will
            let maybe_cached_url_after_purge = try? video_cache.maybe_cached_url_for(video_url: original_video_url)
            XCTAssertEqual(maybe_cached_url_after_purge, original_video_url)
            
            // Clean up the temporary directory
            try? FileManager.default.removeItem(at: test_cache_directory)
        })
    }
}
