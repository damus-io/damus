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
    private var payloadToWrite: String?

    func beginSession() {
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Hold your iPhone near the NFC tag to write data."
        session?.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Handle detected messages if needed
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first, let payload = payloadToWrite else {
            session.invalidate(errorMessage: "Failed to detect a valid tag or payload is empty.")
            return
        }

        session.connect(to: tag) { (error) in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                session.invalidate(errorMessage: "Failed to connect to the tag.")
                return
            }

            tag.queryNDEFStatus { (status, capacity, error) in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                    session.invalidate(errorMessage: "Failed to query NDEF status.")
                    return
                }

                let textPayload = NFCNDEFPayload.wellKnownTypeTextPayload(string: payload, locale: Locale.current)!
                let message = NFCNDEFMessage(records: [textPayload])

                if message.length > capacity {
                    session.invalidate(errorMessage: "The payload is too large for the tag.")
                    return
                }

                tag.writeNDEF(message) { (error) in
                    if let error = error {
                        print("Error: \(error.localizedDescription)")
                        session.invalidate(errorMessage: "Failed to write to the tag.")
                        return
                    }

                    print("NFC message written successfully!")
                    session.invalidate()
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        print("Error: \(error.localizedDescription)")
    }

    func writeNDEFMessage(payload: String) {
        payloadToWrite = payload
    }
}
