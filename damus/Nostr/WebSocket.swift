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
}

final class WebSocket: NSObject, URLSessionWebSocketDelegate {
    
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
    
    func connect() {
        resume()
    }
    
    func disconnect() {
        webSocketTask.cancel(with: .normalClosure, reason: nil)
        
        // need to reset after cancelling
        let task = session.webSocketTask(with: url)
        task.delegate = self
        webSocketTask = task
    }
    
    func send(_ message: URLSessionWebSocketTask.Message) {
        webSocketTask.send(message) { [weak self] error in
            guard let self, let error else {
                return
            }
            print("⚠️ Warning: WebSocket: (\(self.url)) message failed to send: \(error)")
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
        let reason_str: String?
        if let reason {
            reason_str = String(data: reason, encoding: .utf8)
        } else {
            reason_str = nil
        }
        subject.send(.disconnected(closeCode, reason_str))
        disconnect()
    }
}
