//
//  RelayLog.swift
//  damus
//
//  Created by Bryan Montz on 6/1/23.
//

import Combine
import Foundation
import UIKit

/// Stores a running list of events and state changes related to a relay, so that users
/// will have information to help developers debug issues.
final class RelayLog: ObservableObject {
    private static let line_limit = 250
    private let relay_url: URL?
    private lazy var formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
    
    private(set) var lines = [String]()
    
    private var notification_token: AnyCancellable?
    
    /// Creates a RelayLog
    /// - Parameter relay_url: the relay url the log represents. Pass nil for the url to create
    /// a RelayLog that does nothing. This is required to allow RelayLog to be used as a StateObject,
    /// because they cannot be Optional.
    init(_ relay_url: URL? = nil) {
        self.relay_url = relay_url
        
        setUp()
    }
    
    private var log_files_directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("RelayLogs", isDirectory: true)
    }
    
    private var log_file_url: URL? {
        guard let file_name = relay_url?.absoluteString.data(using: .utf8) else {
            return nil
        }
        return log_files_directory.appendingPathComponent(file_name.base64EncodedString())
    }
    
    /// Sets up the log file and prepares to listen to app state changes
    private func setUp() {
        guard let log_file_url else {
            return
        }
        
        try? FileManager.default.createDirectory(at: log_files_directory, withIntermediateDirectories: false)
        
        if !FileManager.default.fileExists(atPath: log_file_url.path) {
            // create the log file if it doesn't exist yet
            FileManager.default.createFile(atPath: log_file_url.path, contents: nil)
        } else {
            // otherwise load it into memory
            readFromDisk()
        }
        
        let willResignPublisher = NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
        let willTerminatePublisher = NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
        notification_token = Publishers.Merge(willResignPublisher, willTerminatePublisher)
            .sink { [weak self] _ in
                self?.writeToDisk()
            }
    }
    
    /// The current contents of the log
    var contents: String? {
        guard !lines.isEmpty else {
            return nil
        }
        return lines.joined(separator: "\n")
    }
    
    /// Adds content to the log
    /// - Parameter content: what to add to the log. The date and time are prepended to the content.
    func add(_ content: String) {
        Task {
            await addLine(content)
            await publishChanges()
        }
    }
    
    @MainActor private func addLine(_ line: String) {
        let line = "\(formatter.string(from: .now)) - \(line)"
        lines.insert(line, at: 0)
        truncateLines()
    }
    
    /// Tells views that our log has been updated
    @MainActor private func publishChanges() {
        objectWillChange.send()
    }
    
    private func truncateLines() {
        lines = Array(lines.prefix(RelayLog.line_limit))
    }
    
    /// Reads the contents of the log file from disk into memory
    private func readFromDisk() {
        guard let log_file_url else {
            return
        }
        
        do {
            let handle = try FileHandle(forReadingFrom: log_file_url)
            let data = try handle.readToEnd()
            try handle.close()
            
            guard let data, let content = String(data: data, encoding: .utf8) else {
                return
            }
            
            lines = content.components(separatedBy: "\n")
            
            truncateLines()
        } catch {
            print("⚠️ Warning: RelayLog failed to read from \(log_file_url)")
        }
    }
    
    /// Writes the contents of the lines in memory to disk
    private func writeToDisk() {
        guard let log_file_url, let relay_url,
              !lines.isEmpty,
              let content = lines.joined(separator: "\n").data(using: .utf8) else {
            return
        }
        
        do {
            let handle = try FileHandle(forWritingTo: log_file_url)
            
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: content)
            try handle.close()
        } catch {
            print("⚠️ Warning: RelayLog(\(relay_url)) failed to write to file: \(error)")
        }
    }
}
