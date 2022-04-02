//
//  Connection.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import Foundation
import Starscream

class WSConnection: WebSocketDelegate {
    var isConnected: Bool = false
    var socket: WebSocket
    var handleEvent: (WebSocketEvent) -> ()
    
    init(url: URL, handleEvent: @escaping (WebSocketEvent) -> ()) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        self.socket = WebSocket(request: req)
        self.handleEvent = handleEvent
        
        socket.delegate = self
    }
    
    func connect(){
        socket.connect()
    }
    
    func disconnect() {
        socket.disconnect()
    }
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected:
            self.isConnected = true
            
        case .disconnected: fallthrough
        case .cancelled: fallthrough
        case .error:
            self.isConnected = false
            
        default:
            break
        }
        
        handleEvent(event)
    }
    
}
