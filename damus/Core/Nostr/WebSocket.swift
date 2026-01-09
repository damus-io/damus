//
//  WebSocket.swift
//  damus
//
//  Created by Bryan Montz on 4/13/23.
//

import Combine
import Foundation

// MARK: - WebSocketProtocol

/// Protocol defining the WebSocket interface for dependency injection and testing.
///
/// This protocol enables mocking WebSocket connections in unit tests to simulate
/// various network conditions (disconnects, errors, slow responses) without
/// requiring real network connections.
protocol WebSocketProtocol: AnyObject {
    /// Publisher for WebSocket events (connected, disconnected, message, error)
    var subject: PassthroughSubject<WebSocketEvent, Never> { get }

    /// Initiates the WebSocket connection
    func connect()

    /// Closes the WebSocket connection
    /// - Parameters:
    ///   - closeCode: The close code to send to the server
    ///   - reason: Optional data explaining the close reason
    func disconnect(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)

    /// Sends a message through the WebSocket
    /// - Parameter message: The message to send (string or data)
    func send(_ message: URLSessionWebSocketTask.Message)

    /// Sends a ping to verify the connection is alive
    /// - Parameter receiveHandler: Callback with nil on success, error on failure
    func ping(receiveHandler: @escaping (Error?) -> Void)
}

// MARK: - WebSocketEvent

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

final class WebSocket: NSObject, URLSessionWebSocketDelegate, WebSocketProtocol {
    
    private let url: URL
    private let session: URLSession
    private lazy var webSocketTask: URLSessionWebSocketTask = {
        let task = session.webSocketTask(with: url)
        task.delegate = self
        return task
    }()
    
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
    
    func disconnect(closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) {
        webSocketTask.cancel(with: closeCode, reason: reason)
        
        // reset after disconnecting to be ready for reconnecting
        let task = session.webSocketTask(with: url)
        task.delegate = self
        webSocketTask = task
        
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
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.subject.send(.message(message))
                self?.resume()
            case .failure(let error):
                self?.subject.send(.error(error))
            }
        }
        
        webSocketTask.resume()
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol theProtocol: String?) {
        subject.send(.connected)
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        disconnect(closeCode: closeCode, reason: reason)
    }
}
