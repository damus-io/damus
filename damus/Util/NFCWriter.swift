//
//  NFCWriter.swift
//  damus
//
//  Created by Ben Weeks on 24/04/2023.
//

import Foundation
import CoreNFC

class NFCWriter: NSObject, NFCNDEFReaderSessionDelegate {
    private var session: NFCNDEFReaderSession?
    private var payloadToWrite: URLComponents?

    func beginSession() {
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Hold your iPhone near the NFC tag to write data."
        session?.begin()
        print("NFCWriter: NFC session started.")
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        print("NFCWriter: NDEF messages detected: \(messages)")
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first, let _ = self.payloadToWrite else {
            print("NFCWriter: Failed to detect a valid tag or payload is empty.")
            session.invalidate(errorMessage: "Failed to detect a valid tag or payload is empty.")
            return
        }

        session.connect(to: tag) { [weak self] (error) in
            if let error = error {
                print("NFCWriter: Error connecting to the tag: \(error.localizedDescription)")
                session.invalidate(errorMessage: "Failed to connect to the tag.")
                return
            }

            tag.queryNDEFStatus { (status, capacity, error) in
                if let error = error {
                    print("NFCWriter: Error querying NDEF status: \(error.localizedDescription)")
                    session.invalidate(errorMessage: "Failed to query NDEF status.")
                    return
                }

                guard let urlPayload = self?.payloadToWrite?.url,
                      let textPayload = NFCNDEFPayload.wellKnownTypeURIPayload(url: urlPayload) else {
                    print("NFCWriter: Failed to create a valid URL payload.")
                    session.invalidate(errorMessage: "Failed to create a valid URL payload.")
                    return
                }

                let message = NFCNDEFMessage(records: [textPayload])

                if message.length > capacity {
                    print("NFCWriter: Payload is too large for the tag.")
                    session.invalidate(errorMessage: "The payload is too large for the tag.")
                    return
                }

                tag.writeNDEF(message) { (error) in
                    if let error = error {
                        print("NFCWriter: Error writing to the tag: \(error.localizedDescription)")
                        session.invalidate(errorMessage: "Failed to write to the tag.")
                        return
                    }

                    print("NFCWriter: NFC message written successfully!")
                    session.invalidate()
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        print("NFCWriter: Session invalidated with error: \(error.localizedDescription)")
    }

    func writeNDEFMessage(payload: URLComponents) {
        print("NFCWriter: Writing: \(payload)")
        payloadToWrite = payload
    }
    
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Perform any actions you need when the session becomes active.
        print("NFCWriter: readerSessionDidBecomeActive is not yet implemented.")
    }
}
