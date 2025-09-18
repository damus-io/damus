//
//  NIP44v2EncryptionTests.swift
//  damus
//
//  Based on NIP44v2EncryptingTests.swift, taken from https://github.com/nostr-sdk/nostr-sdk-ios under the MIT license:
//
//    MIT License
//
//    Copyright (c) 2023 Nostr SDK
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.
//
//
//  Adapted by Daniel D’Aquino for damus on 2025-02-10.
//
import XCTest
import CryptoKit
@testable import damus

final class NIP44v2EncryptingTests: XCTestCase {

    private lazy var vectors: NIP44Vectors = try! decodeFixture(filename: "nip44.vectors")  // swiftlint:disable:this force_try

    /// Calculate the conversation key from secret key, sec1, and public key, pub2.
    func testValidConversationKey() throws {
        let conversationKeyVectors = try XCTUnwrap(vectors.v2.valid.getConversationKey)

        try conversationKeyVectors.forEach { vector in
            let expectedConversationKey = try XCTUnwrap(vector.conversationKey)
            let privateKeyA = try XCTUnwrap(Privkey(hex: vector.sec1))
            let publicKeyB = try XCTUnwrap(Pubkey(hex: vector.pub2))
            let conversationKeyBytes = try NIP44v2Encryption.conversationKey(
                privateKeyA: privateKeyA,
                publicKeyB: publicKeyB
            ).bytes
            let conversationKey = Data(conversationKeyBytes).hexString
            XCTAssertEqual(conversationKey, expectedConversationKey)
        }
    }

    /// Calculate ChaCha key, ChaCha nonce, and HMAC key from conversation key and nonce.
    func testValidMessageKeys() throws {
        let messageKeyVectors = try XCTUnwrap(vectors.v2.valid.getMessageKeys)
        let conversationKey = messageKeyVectors.conversationKey
        let conversationKeyBytes = try XCTUnwrap(conversationKey.hexDecoded?.bytes)
        let keys = messageKeyVectors.keys

        try keys.forEach { vector in
            let nonce = try XCTUnwrap(vector.nonce.hexDecoded)
            let messageKeys = try NIP44v2Encryption.messageKeys(conversationKey: conversationKeyBytes, nonce: nonce)
            XCTAssertEqual(messageKeys.chaChaKey.hexString, vector.chaChaKey)
            XCTAssertEqual(messageKeys.chaChaNonce.hexString, vector.chaChaNonce)
            XCTAssertEqual(messageKeys.hmacKey.hexString, vector.hmacKey)
        }
    }

    /// Take unpadded length (first value), calculate padded length (second value).
    func testValidCalculatePaddedLength() throws {
        let calculatePaddedLengthVectors = try XCTUnwrap(vectors.v2.valid.calculatePaddedLength)
        try calculatePaddedLengthVectors.forEach { vector in
            XCTAssertEqual(vector.count, 2)
            let paddedLength = try NIP44v2Encryption.calculatePaddedLength(vector[0])
            XCTAssertEqual(paddedLength, vector[1])
        }
    }

    /// Emulate real conversation with a hardcoded nonce.
    /// Calculate pub2 from sec2, verify conversation key from (sec1, pub2), encrypt, verify payload.
    /// Then calculate pub1 from sec1, verify conversation key from (sec2, pub1), decrypt, verify plaintext.
    func testValidEncryptDecrypt() throws {
        let encryptDecryptVectors = try XCTUnwrap(vectors.v2.valid.encryptDecrypt)
        try encryptDecryptVectors.forEach { vector in
            let sec1 = vector.sec1
            let sec2 = vector.sec2
            let expectedConversationKey = vector.conversationKey
            let nonce = try XCTUnwrap(vector.nonce.hexDecoded)
            let plaintext = vector.plaintext
            let payload = vector.payload

            let privateKeyA = try XCTUnwrap(Privkey(hex: vector.sec1))
            let privateKeyB = try XCTUnwrap(Privkey(hex: vector.sec2))
            let keypair1 = try XCTUnwrap(FullKeypair(privkey: privateKeyA))
            let keypair2 = try XCTUnwrap(FullKeypair(privkey: privateKeyB))

            // Conversation key from sec1 and pub2.
            let conversationKey1Bytes = try NIP44v2Encryption.conversationKey(
                privateKeyA: keypair1.privkey,
                publicKeyB: keypair2.pubkey
            ).bytes
            XCTAssertEqual(expectedConversationKey, Data(conversationKey1Bytes).hexString)

            // Verify payload.
            let ciphertext = try NIP44v2Encryption.encrypt(
                plaintext: plaintext,
                conversationKey: conversationKey1Bytes,
                nonce: nonce
            )
            XCTAssertEqual(payload, ciphertext)

            // Conversation key from sec2 and pub1.
            let conversationKey2Bytes = try NIP44v2Encryption.conversationKey(
                privateKeyA: keypair2.privkey,
                publicKeyB: keypair1.pubkey
            ).bytes
            XCTAssertEqual(expectedConversationKey, Data(conversationKey2Bytes).hexString)

            // Verify that decrypted data equals the plaintext that we started off with.
            let decrypted = try NIP44v2Encryption.decrypt(payload: payload, conversationKey: conversationKey2Bytes)
            XCTAssertEqual(decrypted, plaintext)
        }
    }

    /// Same as previous step, but instead of a full plaintext and payload, their checksum is provided.
    func testValidEncryptDecryptLongMessage() throws {
        let encryptDecryptVectors = try XCTUnwrap(vectors.v2.valid.encryptDecryptLongMessage)
        try encryptDecryptVectors.forEach { vector in
            let conversationKey = vector.conversationKey
            let conversationKeyData = try XCTUnwrap(conversationKey.hexDecoded)
            let conversationKeyBytes = conversationKeyData.byteArray

            let nonce = try XCTUnwrap(vector.nonce.hexDecoded)
            let expectedPlaintextSHA256 = vector.plaintextSHA256

            let plaintext = String(repeating: vector.pattern, count: vector.repeatCount)
            let plaintextData = try XCTUnwrap(plaintext.data(using: .utf8))
            let plaintextSHA256 = plaintextData.sha256()

            XCTAssertEqual(plaintextSHA256.hexString, expectedPlaintextSHA256)

            let payloadSHA256 = vector.payloadSHA256

            let ciphertext = try NIP44v2Encryption.encrypt(
                plaintext: plaintext,
                conversationKey: conversationKeyBytes,
                nonce: nonce
            )
            let ciphertextData = try XCTUnwrap(ciphertext.data(using: .utf8))
            let ciphertextSHA256 = ciphertextData.sha256().hexString
            XCTAssertEqual(ciphertextSHA256, payloadSHA256)

            let decrypted = try NIP44v2Encryption.decrypt(payload: ciphertext, conversationKey: conversationKeyBytes)
            XCTAssertEqual(decrypted, plaintext)
        }
    }

    /// Emulate real conversation with only the public encrypt and decrypt functions,
    /// where the nonce used for encryption is a cryptographically secure pseudorandom generated series of bytes.
    func testValidEncryptDecryptRandomNonce() throws {
        let encryptDecryptVectors = try XCTUnwrap(vectors.v2.valid.encryptDecrypt)
        try encryptDecryptVectors.forEach { vector in
            let sec1 = vector.sec1
            let sec2 = vector.sec2
            let plaintext = vector.plaintext

            let privateKeyA = try XCTUnwrap(Privkey(hex: vector.sec1))
            let privateKeyB = try XCTUnwrap(Privkey(hex: vector.sec2))
            
            let keypair1 = try XCTUnwrap(FullKeypair(privkey: privateKeyA))
            let keypair2 = try XCTUnwrap(FullKeypair(privkey: privateKeyB))

            // Encrypt plaintext with user A's private key and user B's public key.
            let ciphertext = try NIP44v2Encryption.encrypt(
                plaintext: plaintext,
                privateKeyA: keypair1.privkey,
                publicKeyB: keypair2.pubkey
            )

            // Decrypt ciphertext with user B's private key and user A's public key.
            let decrypted = try NIP44v2Encryption.decrypt(payload: ciphertext, privateKeyA: keypair2.privkey, publicKeyB: keypair1.pubkey)
            XCTAssertEqual(decrypted, plaintext)
        }
    }

    /// Encrypting a plaintext message that is not at a minimum of 1 byte and maximum of 65535 bytes must throw an error.
    func testInvalidEncryptMessageLengths() throws {
        let encryptMessageLengthsVectors = try XCTUnwrap(vectors.v2.invalid.encryptMessageLengths)
        try encryptMessageLengthsVectors.forEach { length in
            let randomBytes = Data.secureRandomBytes(count: 32)
            XCTAssertThrowsError(try NIP44v2Encryption.encrypt(plaintext: String(repeating: "a", count: length), conversationKey: randomBytes))
        }
    }

    /// Calculating conversation key must throw an error.
    func testInvalidConversationKey() throws {
        let conversationKeyVectors = try XCTUnwrap(vectors.v2.invalid.getConversationKey)

        try conversationKeyVectors.forEach { vector in
            let privateKeyA = try XCTUnwrap(Privkey(hex: vector.sec1))
            let publicKeyB = try XCTUnwrap(Pubkey(hex: vector.pub2))
            XCTAssertThrowsError(try NIP44v2Encryption.conversationKey(privateKeyA: privateKeyA, publicKeyB: publicKeyB), vector.note ?? "")
        }
    }

    /// Decrypting message content must throw an error
    func testInvalidDecrypt() throws {
        let decryptVectors = try XCTUnwrap(vectors.v2.invalid.decrypt)
        try decryptVectors.forEach { vector in
            let conversationKey = try XCTUnwrap(vector.conversationKey.hexDecoded).byteArray
            let payload = vector.payload
            XCTAssertThrowsError(try NIP44v2Encryption.decrypt(payload: payload, conversationKey: conversationKey), vector.note)
        }
    }

}


struct NIP44Vectors: Decodable {
    let v2: NIP44VectorsV2

    private enum CodingKeys: String, CodingKey {
        case v2
    }
}

struct NIP44VectorsV2: Decodable {
    let valid: NIP44VectorsV2Valid
    let invalid: NIP44VectorsV2Invalid

    private enum CodingKeys: String, CodingKey {
        case valid
        case invalid
    }
}

struct NIP44VectorsV2Valid: Decodable {
    let getConversationKey: [NIP44VectorsV2GetConversationKey]
    let getMessageKeys: NIP44VectorsV2GetMessageKeys
    let calculatePaddedLength: [[Int]]
    let encryptDecrypt: [NIP44VectorsV2EncryptDecrypt]
    let encryptDecryptLongMessage: [NIP44VectorsV2EncryptDecryptLongMessage]

    private enum CodingKeys: String, CodingKey {
        case getConversationKey = "get_conversation_key"
        case getMessageKeys = "get_message_keys"
        case calculatePaddedLength = "calc_padded_len"
        case encryptDecrypt = "encrypt_decrypt"
        case encryptDecryptLongMessage = "encrypt_decrypt_long_msg"
    }
}

struct NIP44VectorsV2Invalid: Decodable {
    let encryptMessageLengths: [Int]
    let getConversationKey: [NIP44VectorsV2GetConversationKey]
    let decrypt: [NIP44VectorsDecrypt]

    private enum CodingKeys: String, CodingKey {
        case encryptMessageLengths = "encrypt_msg_lengths"
        case getConversationKey = "get_conversation_key"
        case decrypt
    }
}

struct NIP44VectorsDecrypt: Decodable {
    let conversationKey: String
    let nonce: String
    let plaintext: String
    let payload: String
    let note: String

    private enum CodingKeys: String, CodingKey {
        case conversationKey = "conversation_key"
        case nonce
        case plaintext
        case payload
        case note
    }
}

struct NIP44VectorsV2GetConversationKey: Decodable {
    let sec1: String
    let pub2: String
    let conversationKey: String?
    let note: String?

    private enum CodingKeys: String, CodingKey {
        case sec1
        case pub2
        case conversationKey = "conversation_key"
        case note
    }
}

struct NIP44VectorsV2GetMessageKeys: Decodable {
    let conversationKey: String
    let keys: [NIP44VectorsV2MessageKeys]

    private enum CodingKeys: String, CodingKey {
        case conversationKey = "conversation_key"
        case keys
    }
}

struct NIP44VectorsV2MessageKeys: Decodable {
    let nonce: String
    let chaChaKey: String
    let chaChaNonce: String
    let hmacKey: String

    private enum CodingKeys: String, CodingKey {
        case nonce
        case chaChaKey = "chacha_key"
        case chaChaNonce = "chacha_nonce"
        case hmacKey = "hmac_key"
    }
}

struct NIP44VectorsV2EncryptDecrypt: Decodable {
    let sec1: String
    let sec2: String
    let conversationKey: String
    let nonce: String
    let plaintext: String
    let payload: String

    private enum CodingKeys: String, CodingKey {
        case sec1
        case sec2
        case conversationKey = "conversation_key"
        case nonce
        case plaintext
        case payload
    }
}

struct NIP44VectorsV2EncryptDecryptLongMessage: Decodable {
    let conversationKey: String
    let nonce: String
    let pattern: String
    let repeatCount: Int
    let plaintextSHA256: String
    let payloadSHA256: String

    private enum CodingKeys: String, CodingKey {
        case conversationKey = "conversation_key"
        case nonce
        case pattern
        case repeatCount = "repeat"
        case plaintextSHA256 = "plaintext_sha256"
        case payloadSHA256 = "payload_sha256"
    }
}

fileprivate extension Data {
    var hexString: String {
        let hexDigits = Array("0123456789abcdef".utf16)
        var hexChars = [UTF16.CodeUnit]()
        hexChars.reserveCapacity(bytes.count * 2)
        
        for byte in self {
            let (index1, index2) = Int(byte).quotientAndRemainder(dividingBy: 16)
            hexChars.append(hexDigits[index1])
            hexChars.append(hexDigits[index2])
        }
        
        return String(utf16CodeUnits: hexChars, count: hexChars.count)
    }
}

extension String {
    var hexDecoded: Data? {
        guard self.count.isMultiple(of: 2) else { return nil }
        
        // https://stackoverflow.com/a/62517446/982195
        let stringArray = Array(self)
        var data = Data()
        for i in stride(from: 0, to: count, by: 2) {
            let pair = String(stringArray[i]) + String(stringArray[i + 1])
            if let byteNum = UInt8(pair, radix: 16) {
                let byte = Data([byteNum])
                data.append(byte)
            } else {
                return nil
            }
        }
        return data
    }
}

extension NIP44v2EncryptingTests {
    func loadFixtureString(_ filename: String) throws -> String? {
        let data = try self.loadFixtureData(filename)

        guard let originalString = String(data: data, encoding: .utf8) else {
            throw FixtureLoadingError.decodingError
        }

        let trimmedString = originalString.filter { !"\n\t\r".contains($0) }
        return trimmedString
    }
    
    func loadFixtureData(_ filename: String) throws -> Data {
        guard let bundleData = try? readBundleFile(name: filename, ext: "json") else {
            throw FixtureLoadingError.missingFile
        }
        return bundleData
    }

    func decodeFixture<T: Decodable>(filename: String) throws -> T {
        let data = try self.loadFixtureData(filename)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func readBundleFile(name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let fileURL = bundle.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        
        return try Data(contentsOf: fileURL)
    }
    
    enum FixtureLoadingError: Error {
        case missingFile
        case decodingError
    }
}
