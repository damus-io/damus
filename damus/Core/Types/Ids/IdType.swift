//
//  IdType.swift
//  damus
//
//  Created by William Casarin on 2023-07-28.
//

import Foundation

protocol IdType: Codable, CustomStringConvertible, Hashable, Equatable {
    var id: Data { get }

    init(_ data: Data)
    init(from decoder: Decoder) throws
    func encode(to encoder: Encoder) throws
}


extension IdType {
    func hex() -> String {
        hex_encode(self.id)
    }

    var bytes: [UInt8] {
        self.id.bytes
    }

    static var empty: Self {
        return Self.init(Data(repeating: 0, count: 32))
    }

    var description: String {
        self.hex()
    }

    init(from decoder: Decoder) throws {
        self.init(try hex_decoder(decoder))
    }

    func encode(to encoder: Encoder) throws {
        try hex_encoder(to: encoder, data: self.id)
    }
}

func hex_decoder(_ decoder: Decoder, expected_len: Int = 32) throws -> Data {
    let container = try decoder.singleValueContainer()
    guard let arr = hex_decode(try container.decode(String.self)) else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "hex string"))
    }

    if arr.count != expected_len {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "too long"))
    }

    return Data(bytes: arr, count: arr.count)
}

func hex_encoder(to encoder: Encoder, data: Data) throws {
    var container = encoder.singleValueContainer()
    try container.encode(hex_encode(data))
}

