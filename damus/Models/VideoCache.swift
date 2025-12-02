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
/// Maximum size (in bytes) for a single video to be eligible for caching. Anything above streams only.
fileprivate let DEFAULT_MAX_FILE_BYTES: Int64 = 50 * 1024 * 1024 // 50 MB
/// Maximum total cache size (in bytes). Evict least-recently-used cached files when exceeding this limit.
fileprivate let DEFAULT_MAX_CACHE_BYTES: Int64 = 500 * 1024 * 1024 // 500 MB

struct VideoCache {
    private let cache_url: URL
    private let expiry_time: TimeInterval
    private let max_file_bytes: Int64
    private let max_cache_bytes: Int64
    static let standard: VideoCache? = try? VideoCache()
    
    init?(cache_url: URL? = nil, expiry_time: TimeInterval = DEFAULT_EXPIRY_TIME, max_file_bytes: Int64 = DEFAULT_MAX_FILE_BYTES, max_cache_bytes: Int64 = DEFAULT_MAX_CACHE_BYTES) throws {
        guard let cache_url_to_apply = cache_url ?? DEFAULT_CACHE_DIRECTORY_PATH else { return nil }
        self.cache_url = cache_url_to_apply
        self.expiry_time = expiry_time
        self.max_file_bytes = max_file_bytes
        self.max_cache_bytes = max_cache_bytes
        
        // Create the cache directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: self.cache_url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Log.error("Could not create cache directory: %s", for: .storage, error.localizedDescription)
            throw error
        }
    }
    
    /// Checks for a cached video and returns its URL if available, otherwise downloads and caches the video.
    /// Returns the original URL if caching fails so playback can continue.
    func cached_url(for video_url: URL) async -> URL {
        let cached_url = url_to_cached_url(url: video_url)
        
        // Fast path: cached and fresh
        if FileManager.default.fileExists(atPath: cached_url.path),
           let file_attributes = try? FileManager.default.attributesOfItem(atPath: cached_url.path),
           let modification_date = file_attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modification_date) <= expiry_time {
            return cached_url
        }
        
        // Check size before attempting to cache
        var estimatedSize = max_file_bytes
        do {
            let expected_size = try await head_size(for: video_url)
            if let size = expected_size {
                estimatedSize = size
            }
            if estimatedSize > max_file_bytes {
                Log.info("VideoCache: skipping cache for %s (%.2f MB exceeds %.2f MB limit)", for: .storage, video_url.absoluteString, Double(size) / 1_048_576.0, Double(max_file_bytes) / 1_048_576.0)
                return video_url
            }
        } catch {
            Log.info("VideoCache: could not determine size for %s, proceeding with cache attempt", for: .storage, video_url.absoluteString)
        }
        
        // Expired or missing: try to refresh cache, but never block playback.
        do {
            if FileManager.default.fileExists(atPath: cached_url.path) {
                try FileManager.default.removeItem(at: cached_url)
            }
            try make_room_for_file(estimatedSize: estimatedSize)
            let downloaded = try await download_and_cache_video(from: video_url)
            return downloaded
        } catch {
            Log.error("VideoCache: failed to cache video %s: %s", for: .storage, video_url.absoluteString, error.localizedDescription)
            return video_url
        }
    }
    
    /// Downloads video content using URLSession and caches it to disk.
    private func download_and_cache_video(from url: URL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let http_response = response as? HTTPURLResponse,
              200..<300 ~= http_response.statusCode else {
            throw URLError(.badServerResponse)
        }
        
        let destination_url = url_to_cached_url(url: url)
        
        try data.write(to: destination_url)
        return destination_url
    }
    
    /// Make room for a file of the given estimated size by evicting least recently modified cache entries.
    private func make_room_for_file(estimatedSize: Int64) throws {
        let file_manager = FileManager.default
        let cached_files = try file_manager.contentsOfDirectory(at: self.cache_url, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles)
        
        var total_size: Int64 = 0
        var files_with_dates: [(url: URL, size: Int64, date: Date)] = []
        for file in cached_files {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = Int64(values.fileSize ?? 0)
            let date = values.contentModificationDate ?? Date.distantPast
            total_size += size
            files_with_dates.append((file, size, date))
        }
        
        guard total_size + estimatedSize > max_cache_bytes else { return }
        
        // Sort oldest first and evict until there is room.
        for entry in files_with_dates.sorted(by: { $0.date < $1.date }) {
            try? file_manager.removeItem(at: entry.url)
            total_size -= entry.size
            if total_size + estimatedSize <= max_cache_bytes {
                break
            }
        }
    }
    
    /// Returns the expected content length from a HEAD request, if available.
    private func head_size(for url: URL) async throws -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if let contentLengthString = http.value(forHTTPHeaderField: "Content-Length"),
           let contentLength = Int64(contentLengthString) {
            return contentLength
        }
        return nil
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
