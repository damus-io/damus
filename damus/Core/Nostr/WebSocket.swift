//
//  WebSocket.swift
//  damus
//
//  Created by Bryan Montz on 4/13/23.
//

import Combine
import Foundation

enum WebSocketEvent {
    case connected
    case message(URLSessionWebSocketTask.Message)
    case disconnected(URLSessionWebSocketTask.CloseCode, String?)
    case error(Error)
    
    var description: String? {
        switch self {
        case .connected:
            return "Connected"
        case .message:
            return nil  // adding this to the RelayLog was too noisy
        case .disconnected(let close_code, let reason):
            return "Disconnected: Close code: \(close_code), reason: \(reason ?? "unknown")"
        case .error(let error):
            return "Error: \(error)"
        }
    }
}

final class WebSocket: NSObject, URLSessionWebSocketDelegate {

    private let url: URL
    private let session: URLSession

    /// Lock protecting webSocketTask initialization and reassignment.
    /// Required because lazy vars are not thread-safe and disconnect() reassigns the task.
    private let taskLock = NSLock()
    private var _webSocketTask: URLSessionWebSocketTask?

    /// Thread-safe accessor for the WebSocket task. Creates task on first access.
    private var webSocketTask: URLSessionWebSocketTask {
        taskLock.lock()
        defer { taskLock.unlock() }
        if let task = _webSocketTask {
            return task
        }
        let task = session.webSocketTask(with: url)
        task.delegate = self
        _webSocketTask = task
        return task
    }

    let subject = PassthroughSubject<WebSocketEvent, Never>()
    
    init(_ url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }
    
    func ping(receiveHandler: @escaping (Error?) -> Void) {
        self.webSocketTask.sendPing(pongReceiveHandler: receiveHandler)
    }
    
    func connect() {
        resume()
    }
    
    /// Disconnects the WebSocket and prepares a new task for potential reconnection.
    ///
    /// This method acquires `taskLock` to safely read and replace `_webSocketTask` with a
    /// newly created `session.webSocketTask(with:)`. The new task's delegate is set to `self`
    /// while still holding the lock. After releasing the lock, the previous task is cancelled
    /// with the specified close code and reason.
    ///
    /// - Parameters:
    ///   - closeCode: The WebSocket close code to send. Defaults to `.normalClosure`.
    ///   - reason: Optional data explaining the disconnection reason.
    ///
    /// - Note: The previous task is cancelled outside the lock to avoid holding the lock
    ///   during potentially blocking I/O operations. A new task is created immediately
    ///   (before cancelling the old one) to ensure the socket is ready for reconnection.
    ///
    /// - Thread Safety: All access to `_webSocketTask` is protected by `taskLock`.
    func disconnect(closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) {
        // Acquire lock to safely access and reassign the task
        taskLock.lock()
        let currentTask = _webSocketTask
        // Create new task for potential reconnection while still holding lock
        let newTask = session.webSocketTask(with: url)
        newTask.delegate = self
        _webSocketTask = newTask
        taskLock.unlock()

        // Cancel the old task outside the lock to avoid holding it during I/O
        currentTask?.cancel(with: closeCode, reason: reason)

        let reason_str: String?
        if let reason {
            reason_str = String(data: reason, encoding: .utf8)
        } else {
            reason_str = nil
        }
        subject.send(.disconnected(closeCode, reason_str))
    }
    
    func send(_ message: URLSessionWebSocketTask.Message) {
        webSocketTask.send(message) { [weak self] error in
            if let error {
                self?.subject.send(.error(error))
            }
        }
    }
    
    private func resume() {
        // Capture task reference once to ensure receive handler and resume()
        // are called on the same task. Without this, disconnect() could swap
        // the task between the two calls, causing the new task to resume
        // without a receive handler.
        let task = webSocketTask
        task.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.subject.send(.message(message))
                self?.resume()
            case .failure(let error):
                self?.subject.send(.error(error))
            }
        }

        task.resume()
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol theProtocol: String?) {
        subject.send(.connected)
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        disconnect(closeCode: closeCode, reason: reason)
    }
}
