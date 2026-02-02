//
//  DamusCacheManager.swift
//  damus
//
//  Created by Daniel D'Aquino on 2023-10-04.
//

import Foundation
import Kingfisher

struct DamusCacheManager {
    static var shared: DamusCacheManager = DamusCacheManager()

    /// Formats byte counts as human-readable strings in MB/GB using file-size style.
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    /// Clears all application caches sequentially: Kingfisher, app group, cache folder, and temp directory.
    /// Invokes `completion` on the main thread after all caches are cleared.
    func clear_cache(damus_state: DamusState, completion: (() -> Void)? = nil) {
        Log.info("Clearing all caches", for: .storage)
        clear_kingfisher_cache(completion: {
            clear_app_group_cache(damus_state: damus_state, completion: {
                clear_cache_folder(completion: {
                    clear_temporary_directory(completion: {
                        Log.info("All caches cleared", for: .storage)
                        completion?()
                    })
                })
            })
        })
    }

    /// Clears Kingfisher's in-memory and disk image cache.
    /// Logs cache size before and after clearing; invokes `completion` after the disk cache callback completes.
    func clear_kingfisher_cache(completion: (() -> Void)? = nil) {
        Log.info("Clearing Kingfisher cache", for: .storage)
        KingfisherManager.shared.cache.calculateDiskStorageSize { result in
            if case .success(let size) = result {
                Log.info("Kingfisher disk cache before clear: %s", for: .storage, self.formattedByteCount(from: UInt64(max(size, 0))))
            }
            KingfisherManager.shared.cache.clearMemoryCache()
            KingfisherManager.shared.cache.clearDiskCache {
                KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                    if case .success(let size) = result {
                        Log.info("Kingfisher disk cache after clear: %s", for: .storage, self.formattedByteCount(from: UInt64(max(size, 0))))
                    }
                    Log.info("Kingfisher cache cleared", for: .storage)
                    completion?()
                }
            }
        }
    }

    /// Clears the shared app group cache including Kingfisher cache directories and database files.
    /// Dispatches heavy I/O to a background queue and invokes `completion` on the main thread.
    private func clear_app_group_cache(damus_state: DamusState, completion: (() -> Void)? = nil) {
        Log.info("Clearing shared app group cache", for: .storage)
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.DAMUS_APP_GROUP_IDENTIFIER) else {
            Log.error("App group container unavailable; skipping shared cache clear", for: .storage)
            DispatchQueue.main.async { completion?() }
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            var removedCount = 0
            var freedBytes: UInt64 = 0

            damus_state.ndb.close()

            let sharedCacheRootPath = containerURL.standardizedFileURL.path
            let kingfisherDirectories = ImageCacheMigrations.knownKingfisherCacheDirectories()
                .filter { $0.standardizedFileURL.path.hasPrefix(sharedCacheRootPath) }

            for directory in kingfisherDirectories {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }

                let directorySize = self.allocatedDirectorySize(directory)
                do {
                    try fileManager.removeItem(at: directory)
                    removedCount += 1
                    freedBytes &+= directorySize
                } catch {
                    Log.error("Failed to remove Kingfisher cache directory %s: %s", for: .storage, directory.lastPathComponent, error.localizedDescription)
                    continue
                }

                do {
                    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                } catch {
                    Log.error("Failed to recreate Kingfisher cache directory %s: %s", for: .storage, directory.lastPathComponent, error.localizedDescription)
                }
            }

            let cachePath = ImageCacheMigrations.kingfisherCachePath()
            if let cache = try? ImageCache(name: "sharedCache", cacheDirectoryURL: cachePath) {
                KingfisherManager.shared.cache = cache
            } else {
                Log.error("Failed to reset Kingfisher shared cache instance after clearing disk cache", for: .storage)
            }

            let dbFiles = ["data.mdb", "lock.mdb"].map { containerURL.appendingPathComponent($0, isDirectory: false) }
            for fileURL in dbFiles {
                guard fileManager.fileExists(atPath: fileURL.path) else { continue }

                let fileSize = self.allocatedSize(of: fileURL)
                do {
                    try fileManager.removeItem(at: fileURL)
                    removedCount += 1
                    freedBytes &+= fileSize
                    Log.info("Removed cached database file %s", for: .storage, fileURL.lastPathComponent)
                } catch {
                    Log.error("Failed to remove cached database file %s: %s", for: .storage, fileURL.lastPathComponent, error.localizedDescription)
                }
            }

            if !damus_state.ndb.reopen() {
                Log.error("Failed to reopen Nostr database after cache clear", for: .storage)
            }
            Log.info("Shared app group cache cleared. Removed %d items freeing %s", for: .storage, removedCount, self.formattedByteCount(from: freedBytes))

            DispatchQueue.main.async { completion?() }
        }
    }

    /// Clears the application's Caches directory by removing all files and subdirectories.
    /// Dispatches I/O to a background queue and invokes `completion` on the main thread.
    func clear_cache_folder(completion: (() -> Void)? = nil) {
        Log.info("Clearing entire cache folder", for: .storage)
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

        DispatchQueue.global(qos: .utility).async {
            do {
                let fileNames = try FileManager.default.contentsOfDirectory(atPath: cacheURL.path)
                let fileURLs = fileNames.map { cacheURL.appendingPathComponent($0) }
                let initialSize = self.totalAllocatedSize(of: fileURLs)
                Log.info("Cache folder contains %d items totaling %s", for: .storage, fileNames.count, self.formattedByteCount(from: initialSize))

                var removedCount = 0
                var freedBytes: UInt64 = 0
                for fileName in fileNames {
                    let filePath = cacheURL.appendingPathComponent(fileName)

                    // Prevent issues by double-checking if files are in use, and do not delete them if they are.
                    // This is not perfect. There is still a small chance for a race condition if a file is opened between this check and the file removal.
                    errno = 0
                    let isBusy = (access(filePath.path, F_OK) == -1 && errno == ETXTBSY)
                    if isBusy {
                        Log.debug("Skipping busy cache file: %s", for: .storage, filePath.lastPathComponent)
                        continue
                    }

                    let fileSize = self.allocatedSize(of: filePath)

                    try FileManager.default.removeItem(at: filePath)
                    removedCount += 1
                    freedBytes &+= fileSize
                }

                Log.info("Cache folder cleared successfully. Removed %d items freeing %s", for: .storage, removedCount, self.formattedByteCount(from: freedBytes))
                DispatchQueue.main.async { completion?() }
            } catch {
                Log.error("Could not clear cache folder", for: .storage)
                DispatchQueue.main.async { completion?() }
            }
        }
    }

    /// Clears the system temporary directory for this application.
    /// Dispatches I/O to a background queue and invokes `completion` on the main thread.
    private func clear_temporary_directory(completion: (() -> Void)? = nil) {
        let tmpPath = NSTemporaryDirectory()
        guard !tmpPath.isEmpty else {
            DispatchQueue.main.async { completion?() }
            return
        }

        let tmpURL = URL(fileURLWithPath: tmpPath, isDirectory: true)
        Log.info("Clearing temporary directory", for: .storage)

        DispatchQueue.global(qos: .utility).async {
            do {
                let itemNames = try FileManager.default.contentsOfDirectory(atPath: tmpURL.path)
                let itemURLs = itemNames.map { tmpURL.appendingPathComponent($0) }
                let initialSize = self.totalAllocatedSize(of: itemURLs)
                Log.info("Temporary directory contains %d items totaling %s", for: .storage, itemNames.count, self.formattedByteCount(from: initialSize))

                var removedCount = 0
                var freedBytes: UInt64 = 0
                for itemName in itemNames {
                    let itemURL = tmpURL.appendingPathComponent(itemName)

                    errno = 0
                    let isBusy = (access(itemURL.path, F_OK) == -1 && errno == ETXTBSY)
                    if isBusy {
                        Log.debug("Skipping busy temporary item: %s", for: .storage, itemURL.lastPathComponent)
                        continue
                    }

                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDirectory)
                    let itemSize = isDirectory.boolValue ? self.allocatedDirectorySize(itemURL) : self.allocatedSize(of: itemURL)

                    do {
                        try FileManager.default.removeItem(at: itemURL)
                        removedCount += 1
                        freedBytes &+= itemSize
                    } catch {
                        Log.error("Failed to remove temporary item %s: %s", for: .storage, itemURL.lastPathComponent, error.localizedDescription)
                    }
                }

                Log.info("Temporary directory cleared successfully. Removed %d items freeing %s", for: .storage, removedCount, self.formattedByteCount(from: freedBytes))
                DispatchQueue.main.async { completion?() }
            } catch {
                Log.error("Could not clear temporary directory", for: .storage)
                DispatchQueue.main.async { completion?() }
            }
        }
    }

    /// Formats a byte count as a human-readable string (e.g., "1.5 GB").
    private func formattedByteCount(from bytes: UInt64) -> String {
        let clamped = min(bytes, UInt64(Int64.max))
        return Self.byteCountFormatter.string(fromByteCount: Int64(clamped))
    }

    /// Returns the allocated disk size in bytes for a single file at the given URL.
    private func allocatedSize(of url: URL) -> UInt64 {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
            return 0
        }
        if let total = values.totalFileAllocatedSize {
            return UInt64(max(total, 0))
        }
        if let single = values.fileAllocatedSize {
            return UInt64(max(single, 0))
        }
        return 0
    }

    /// Returns the total allocated disk size in bytes for an array of file/directory URLs.
    private func totalAllocatedSize(of urls: [URL]) -> UInt64 {
        let fileManager = FileManager.default
        return urls.reduce(0) { partialResult, url in
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                return partialResult &+ allocatedDirectorySize(url)
            } else {
                return partialResult &+ allocatedSize(of: url)
            }
        }
    }

    /// Returns the total allocated disk size in bytes for all files within a directory, recursively.
    private func allocatedDirectorySize(_ directoryURL: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: [], errorHandler: nil) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            total &+= allocatedSize(of: fileURL)
        }
        return total
    }
}
