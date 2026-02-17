//
//  VideoCache.swift
//  damus
//
//  Created by Daniel D'Aquino on 2024-04-01.
//
import Foundation
import CryptoKit

// Default expiry time of only 1 day to prevent using too much storage
fileprivate let DEFAULT_EXPIRY_TIME: TimeInterval = 60*60*24
// Default cache directory is in the system-provided caches directory, so that the operating system can delete files when it needs storage space
// (https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)
fileprivate let DEFAULT_CACHE_DIRECTORY_PATH: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("video_cache")

/// Thread-safe tracker for in-flight download URLs.
/// @unchecked Sendable: NSLock protects `urls` Set from concurrent access.
private class InFlightTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var urls = Set<URL>()

    /// Returns true if the URL was not already in-flight and is now tracked.
    func tryInsert(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return urls.insert(url).inserted
    }

    func remove(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.remove(url)
    }
}

struct VideoCache {
    private let cache_url: URL
    private let expiry_time: TimeInterval
    /// Tracks URLs currently being downloaded to prevent duplicate concurrent downloads.
    private let inFlight = InFlightTracker()
    static let standard: VideoCache? = try? VideoCache()
    
    init?(cache_url: URL? = nil, expiry_time: TimeInterval = DEFAULT_EXPIRY_TIME) throws {
        guard let cache_url_to_apply = cache_url ?? DEFAULT_CACHE_DIRECTORY_PATH else { return nil }
        self.cache_url = cache_url_to_apply
        self.expiry_time = expiry_time
        
        // Create the cache directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: self.cache_url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Log.error("Could not create cache directory: %s", for: .storage, error.localizedDescription)
            throw error
        }
    }
    
    /// Checks for a cached video and returns its URL if available, otherwise downloads and caches the video.
    func maybe_cached_url_for(video_url: URL) -> URL {
        let cached_url = url_to_cached_url(url: video_url)

        // Use try? to avoid TOCTOU: instead of fileExists + attributesOfItem,
        // attempt to read attributes directly. If the file doesn't exist,
        // attributes will be nil and we fall through to download.
        let file_attributes = try? FileManager.default.attributesOfItem(atPath: cached_url.path)

        if let file_attributes,
           let modification_date = file_attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modification_date) <= expiry_time {
            // Cached and not expired
            return cached_url
        }

        // Prevent duplicate concurrent downloads for the same URL
        guard inFlight.tryInsert(video_url) else {
            return video_url
        }

        if file_attributes != nil {
            // File exists but is expired — remove and re-download
            Task.detached(priority: .background) { [self] in
                defer { inFlight.remove(video_url) }
                try? FileManager.default.removeItem(at: cached_url)
                _ = try? await download_and_cache_video(from: video_url)
            }
        } else {
            // Not cached — download
            Task.detached(priority: .background) { [self] in
                defer { inFlight.remove(video_url) }
                _ = try? await download_and_cache_video(from: video_url)
            }
        }
        return video_url
    }
    
    /// Downloads video content using URLSession and caches it to disk.
    private func download_and_cache_video(from url: URL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let http_response = response as? HTTPURLResponse,
              200..<300 ~= http_response.statusCode else {
            throw URLError(.badServerResponse)
        }
        
        let destination_url = url_to_cached_url(url: url)
        
        try data.write(to: destination_url, options: .atomic)
        return destination_url
    }

    func url_to_cached_url(url: URL) -> URL {
        let hashed_url = hash_url(url)
        let file_extension = url.pathExtension
        return self.cache_url.appendingPathComponent(hashed_url + "." + file_extension)
    }
    
    /// Deletes all cached videos older than the expiry time.
    func periodic_purge(completion: ((Error?) -> Void)? = nil) {
        DispatchQueue.global(qos: .background).async {
            Log.info("Starting periodic video cache purge", for: .storage)
            let file_manager = FileManager.default
            do {
                let cached_files = try file_manager.contentsOfDirectory(at: self.cache_url, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
                
                for file in cached_files {
                    let attributes = try file.resourceValues(forKeys: [.contentModificationDateKey])
                    if let modification_date = attributes.contentModificationDate, Date().timeIntervalSince(modification_date) > self.expiry_time {
                        try file_manager.removeItem(at: file)
                    }
                }
                DispatchQueue.main.async {
                    completion?(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion?(error)
                }
            }
        }
    }
    
    /// Hashes the URL using SHA-256
    private func hash_url(_ url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hashed_data = SHA256.hash(data: data)
        return hashed_data.compactMap { String(format: "%02x", $0) }.joined()
    }
}
