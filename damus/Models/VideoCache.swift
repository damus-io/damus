//
//  VideoCache.swift
//  damus
//
//  Created by Daniel D'Aquino on 2024-04-01.
//
import Foundation
import CryptoKit
import AVKit

// Default expiry time of only 1 day to prevent using too much storage
fileprivate let DEFAULT_EXPIRY_TIME: TimeInterval = 60*60*24
// Default cache directory is in the system-provided caches directory, so that the operating system can delete files when it needs storage space
// (https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)
fileprivate let DEFAULT_CACHE_DIRECTORY_PATH: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("video_cache")

struct VideoCache {
    private let cache_url: URL
    private let expiry_time: TimeInterval
    private var loader_queue: DispatchQueue
    static var standard: VideoCache? = try? VideoCache()
    
    init?(cache_url: URL? = nil, expiry_time: TimeInterval = DEFAULT_EXPIRY_TIME) throws {
        guard let cache_url_to_apply = cache_url ?? DEFAULT_CACHE_DIRECTORY_PATH else { return nil }
        self.cache_url = cache_url_to_apply
        self.expiry_time = expiry_time
        self.loader_queue = DispatchQueue.init(
            label: "com.damus.video_loader",
            qos: .utility,
            attributes: []
        )
        
        // Create the cache directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: self.cache_url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Log.error("Could not create cache directory: %s", for: .storage, error.localizedDescription)
            throw error
        }
    }
    
    /// Checks for a cached video and returns its URL if available, otherwise downloads and caches the video.
    func maybe_cached_url_for(video_url: URL) throws -> URL {
        let cached_url = url_to_cached_url(url: video_url)
        
        if FileManager.default.fileExists(atPath: cached_url.path) {
            // Check if the cached video has expired
            let file_attributes = try FileManager.default.attributesOfItem(atPath: cached_url.path)
            if let modification_date = file_attributes[.modificationDate] as? Date, Date().timeIntervalSince(modification_date) <= expiry_time {
                // Video is not expired
                return cached_url
            } else {
                return video_url
            }
        } else {
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
    
    /// Returns an asset that may be cached (or not)
    /// - Parameter video_url: The video URL to load
    /// - Returns: An AVAsset + loader delegate wrapped together. The AVAsset can be used with AVPlayer. The loader delegate does not need to be used. Just keep it around to avoid it from being garbage collected
    mutating func maybe_cached_asset_for(video_url: URL) throws -> MaybeCachedAVAsset? {
        let maybe_cached_url = try self.maybe_cached_url_for(video_url: video_url)
        if maybe_cached_url.isFileURL {
            // We have this video cached. Return the cached asset
            return MaybeCachedAVAsset(av_asset: AVAsset(url: maybe_cached_url), loader: nil)
        }
        // If we get here, we do not have the video cached yet.
        // Load the video asset using our custom loader delegate, which will give us control over how video data is loaded, and allows us to cache it
        guard let loader_delegate = LoaderDelegate(url: video_url, video_cache: self) else { return nil }
        let video_asset = AVURLAsset(url: loader_delegate.streaming_url)    // Get the modified URL that forces the AVAsset to use our loader delegate
        video_asset.resourceLoader.setDelegate(loader_delegate, queue: self.loader_queue)
        
        // Return the video asset to the player who is requesting this. Loading and caching will take place as AVPlayer makes loading requests
        return MaybeCachedAVAsset(av_asset: video_asset, loader: loader_delegate)
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
    
    /// Caches a video to storage with a given data
    func save(data video_data: Data, for video_url: URL) throws {
        if video_url.isFileURL {
            return
        }
        Log.info("Caching video for: %s", for: .storage, video_url.absoluteString)
        let cache_destination_url: URL = self.url_to_cached_url(url: video_url)
        
        if FileManager.default.fileExists(atPath: cache_destination_url.path) {
            try FileManager.default.removeItem(at: cache_destination_url)
        }

        try video_data.write(to: cache_destination_url)
    }
    
    /// Hashes the URL using SHA-256
    private func hash_url(_ url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hashed_data = SHA256.hash(data: data)
        return hashed_data.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    struct MaybeCachedAVAsset {
        let av_asset: AVAsset
        let loader: LoaderDelegate?
    }
    
    
    // MARK: - Resource loader delegate
    
    /// This handles the nitty gritty of loading data for a particular video for the AVPlayer, and saves up that data to the cache.
    class LoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
        // MARK: Constants
        
        static let protocol_suffix = "cache"
        
        
        // MARK: Stored properties
        
        /// The video cache to use when saving data
        let cache: VideoCache
        /// Video URL to be loaded
        let url: URL
        /// The URL to be used as a parameter to AVURLAsset, which forces it to use our delegate for data loading
        let streaming_url: URL
        /// The data loading requests we must fulfill
        private var loading_requests = [AVAssetResourceLoadingRequest]()
        /// The URL session we will use for handling video data loading
        var url_session: URLSession? = nil
        /// The video download task
        var loading_task: URLSessionDataTask? = nil
        /// The latest information response we received whilst downloading the video
        var latest_info_response: URLResponse?
        /// All of the video data we got so far from the download
        var downloaded_video_data = Data()
        /// Whether the download is successfully completed
        var download_completed: Bool = false
        /// Semaphore to avoid race conditions
        let semaphore = DispatchSemaphore(value: 1)
        
        
        // MARK: Initializer
        
        init?(url: URL, video_cache: VideoCache) {
            self.cache = video_cache
            self.url = url
            guard let streaming_url = Self.streaming_url(from: url) else { return nil }
            self.streaming_url = streaming_url
        }
        
        
        // MARK: AVAssetResourceLoaderDelegate protocol implementation
        // This allows us to handle the data loading for the AVPlayer
        
        // This is called when our AVPlayer wants to load some video data. Here we need to do two things:
        // - just respond whether or not we can handle the request
        // - Queue up the load request so that we can work on it on the background
        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            Log.debug("Receiving load request for: %s", for: .storage, self.url.absoluteString)
            
            // Use semaphore to avoid race condition
            semaphore.wait()
            defer { semaphore.signal() }    // Use defer to avoid forgetting to signal and causing deadlocks
            
            self.start_downloading_video_if_not_already()   // Start downloading data if we have not started
            self.loading_requests.append(loadingRequest)    // Add this loading request to our queue
            return true                                     // Yes Mr. AVPlayer, we can handle this loading request for you.
        }

        // This is called when our AVPlayer wants to cancel a loading request.
        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
            Log.debug("Receiving load request cancellation for: %s", for: .storage, self.url.absoluteString)
            
            // Use semaphore to avoid race condition
            semaphore.wait()
            defer { semaphore.signal() }    // Use defer to avoid forgetting to signal and causing deadlocks
            
            self.remove(loading_request: loadingRequest)
            
            // Pause downloading if we have no loading requests from our AVPlayer
            if loading_requests.isEmpty {
                loading_task?.suspend()
            }
        }
        
        
        // MARK: URLSessionDataDelegate
        // This helps us receive updates from our URL download session as we download the video
        // This enables us to progressively serve AV loading requests we have on our queue
        
        // Our URLSession (which is downloading the video) will call this function when we receive a URL response
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            Log.debug("Receiving URL response for: %s", for: .storage, self.url.absoluteString)
            
            // Use semaphore to avoid race condition
            semaphore.wait()
            defer { semaphore.signal() }    // Use defer to avoid forgetting to signal and causing deadlocks
            
            self.latest_info_response = response
            self.process_loading_requests()
            
            completionHandler(.allow)
        }
        
        // Our URLSession (which is downloading the video) will call this function when we receive some video data
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            Log.debug("Receiving data (%d bytes) for: %s", for: .storage, data.count, self.url.absoluteString)
            
            // Use semaphore to avoid race condition
            semaphore.wait()
            defer { semaphore.signal() }    // Use defer to avoid forgetting to signal and causing deadlocks
            
            self.downloaded_video_data.append(data)
            self.process_loading_requests()
        }

        
        
        // MARK: Internal methods
        // Were we do some heavy lifting
        
        /// Goes through the loading requests we received from the AVPlayer and respond to them if we can. This is called when we get updates from our download operation.
        private func process_loading_requests() {
            Log.debug("Processing loading requests for: %s", for: .storage, self.url.absoluteString)
            var served_loading_requests = 0
            for loading_request in loading_requests {
                if loading_request.isCancelled {
                    self.remove(loading_request: loading_request)
                }
                
                if let content_info_request = loading_request.contentInformationRequest,
                   let latest_info_response {
                    self.respond(to: content_info_request, with: latest_info_response)
                }
                
                if let data_request = loading_request.dataRequest, self.respond_if_possible(to: data_request) == true {
                    served_loading_requests += 1
                    loading_request.finishLoading()
                    self.remove(loading_request: loading_request)
                }
            }
            Log.debug("Served %d loading requests for: %s", for: .storage, served_loading_requests, self.url.absoluteString)
        }
        
        private func respond(to info_request: AVAssetResourceLoadingContentInformationRequest, with response: URLResponse) {
            info_request.isByteRangeAccessSupported = true
            info_request.contentType = response.mimeType
            info_request.contentLength = response.expectedContentLength
        }
        
        private func respond_if_possible(to data_request: AVAssetResourceLoadingDataRequest) -> Bool {
            let bytes_downloaded = Int64(self.downloaded_video_data.count)
            let bytes_requested  = Int64(data_request.requestedLength)
            
            if bytes_downloaded < data_request.currentOffset {
                return false    // We do not have enough bytes to respond to this request
            }
            
            let bytes_downloaded_but_unread = bytes_downloaded - data_request.currentOffset
            let bytes_requested_and_unread = data_request.requestedOffset + bytes_requested - data_request.currentOffset
            let bytes_to_respond = min(bytes_requested_and_unread, bytes_downloaded_but_unread)
            
            guard let byte_range = Range(NSMakeRange(Int(data_request.currentOffset), Int(bytes_to_respond))) else { return false }

            data_request.respond(with: self.downloaded_video_data.subdata(in: byte_range))
            
            let request_end_offset = data_request.requestedOffset + bytes_requested
            
            return data_request.currentOffset >= request_end_offset
        }
        
        private func start_downloading_video_if_not_already() {
            if self.download_completed {
                Log.info("Already downloaded video data for: %s. Won't start downloading again", for: .storage, self.url.absoluteString)
                return
            }
            if self.url_session == nil {
                self.downloaded_video_data = Data() // We are starting from scratch, so make sure we don't add corrupt data to the mix
                let new_url_session = self.create_url_session()
                let loading_task = new_url_session.dataTask(with: self.url)
                loading_task.resume()
                
                Log.info("Started downloading video data for: %s", for: .storage, self.url.absoluteString)
                
                self.url_session = new_url_session
                self.loading_task = loading_task
            }
        }
        
        
        // MARK: URLSessionTaskDelegate
        
        // Called when we are finished downloading the video
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            
            // Use semaphore to avoid race condition
            semaphore.wait()
            defer { semaphore.signal() }    // Use defer to avoid forgetting to signal and causing deadlocks
            
            if let error {
                Log.info("Error on downloading '%s'. Error: %s", for: .storage, self.url.absoluteString, error.localizedDescription)
                self.download_completed = false
                self.url_session?.invalidateAndCancel()
                self.url_session = nil
                self.loading_task = nil
                self.start_downloading_video_if_not_already()
                return
            }
            Log.info("Finished downloading data for '%s' without errors", for: .storage, self.url.absoluteString)
            self.download_completed = true
            do {
                try self.cache.save(data: self.downloaded_video_data, for: self.url)
                Log.info("Saved cache video data for: %s", for: .storage, self.url.absoluteString)
                self.url_session?.invalidateAndCancel()
                self.url_session = nil
                self.loading_task = nil
            }
            catch {
                Log.error("Failed to save cache video data for: %s", for: .storage, self.url.absoluteString)
            }
        }
        
        
        // MARK: Utility functions
        
        /// Modifies the url to change its protocol and force AV loaders to use our delegate for data loading.
        /// - Parameter url: The URL to be modified
        /// - Returns: The modified URL with custom scheme
        private static func streaming_url(from url: URL) -> URL? {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            components.scheme = (components.scheme ?? "") + protocol_suffix
            return components.url
        }

        private func create_url_session() -> URLSession {
            let config = URLSessionConfiguration.default
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = 1
            return URLSession(
                configuration: config,
                delegate: self,     // Set ourselves as the delegate, so that we can receive updates and use them to serve our AV Loading requests.
                delegateQueue: operationQueue
            )
        }
        
        /// Removes a loading request from our queue
        /// - Parameter loading_request: The loading request object to be removed
        private func remove(loading_request: AVAssetResourceLoadingRequest) {
            self.loading_requests.removeAll(where: { $0 == loading_request })
        }
    }
}
