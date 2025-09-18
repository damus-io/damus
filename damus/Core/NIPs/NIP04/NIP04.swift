//
//  NIP04.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-10.
//
import Foundation

/// Functions and utilities for the NIP-04 spec
struct NIP04 {}

extension NIP04 {
    /// Encrypts a message using NIP-04.
    static func encrypt_message(message: String, privkey: Privkey, to_pk: Pubkey, encoding: EncEncoding = .base64) -> String? {
        let iv = random_bytes(count: 16).byteArray
        guard let shared_sec = get_shared_secret(privkey: privkey, pubkey: to_pk) else {
            return nil
        }
        let utf8_message = Data(message.utf8).byteArray
        guard let enc_message = aes_encrypt(data: utf8_message, iv: iv, shared_sec: shared_sec) else {
            return nil
        }
        
        switch encoding {
        case .base64:
            return encode_dm_base64(content: enc_message.bytes, iv: iv)
        case .bech32:
            return encode_dm_bech32(content: enc_message.bytes, iv: iv)
        }
        
    }
    
    /// Creates an event with encrypted `contents` field, using NIP-04
    static func create_encrypted_event(_ message: String, to_pk: Pubkey, tags: [[String]], keypair: FullKeypair, created_at: UInt32, kind: UInt32) -> NostrEvent? {
        let privkey = keypair.privkey
        
        guard let enc_content = encrypt_message(message: message, privkey: privkey, to_pk: to_pk) else {
            return nil
        }
        
        return NostrEvent(content: enc_content, keypair: keypair.to_keypair(), kind: kind, tags: tags, createdAt: created_at)
    }
    
    /// Creates a NIP-04 style direct message event
    static func create_dm(_ message: String, to_pk: Pubkey, tags: [[String]], keypair: Keypair, created_at: UInt32? = nil) -> NostrEvent?
    {
        let created = created_at ?? UInt32(Date().timeIntervalSince1970)
        
        guard let keypair = keypair.to_full() else {
            return nil
        }
        
        return create_encrypted_event(message, to_pk: to_pk, tags: tags, keypair: keypair, created_at: created, kind: 4)
    }
    
    /// Decrypts string content
    static func decryptContent(recipientPrivateKey: Privkey, senderPubkey: Pubkey, content: String, encoding: EncEncoding) throws(NIP04DecryptionError) -> String {
        guard let shared_sec = get_shared_secret(privkey: recipientPrivateKey, pubkey: senderPubkey) else {
            throw .failedToComputeSharedSecret
        }
        guard let dat = (encoding == .base64 ? decode_dm_base64(content) : decode_dm_bech32(content)) else {
            throw .failedToDecodeEncryptedContent
        }
        guard let dat = aes_decrypt(data: dat.content, iv: dat.iv, shared_sec: shared_sec) else {
            throw .failedToDecryptAES
        }
        guard let decryptedString = String(data: dat, encoding: .utf8) else {
            throw .utf8DecodingFailedOnDecryptedPayload
        }
        return decryptedString
    }
    
    enum NIP04DecryptionError: Error {
        case failedToComputeSharedSecret
        case failedToDecodeEncryptedContent
        case failedToDecryptAES
        case utf8DecodingFailedOnDecryptedPayload
    }
}
