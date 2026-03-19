//
//  BlossomTypes.swift
//  damus
//
//  Created by Claude on 2026-03-18.
//

import Foundation

/// A validated Blossom server URL (HTTPS-only per BUD-01).
struct BlossomServerURL: Equatable, Hashable, Codable {
    let url: URL

    init?(string: String) {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host != nil
        else {
            return nil
        }
        self.url = url
    }

    /// Upload endpoint: PUT /upload
    var uploadURL: URL {
        url.appendingPathComponent("upload")
    }

    /// Media optimization endpoint: PUT /media (BUD-05)
    var mediaURL: URL {
        url.appendingPathComponent("media")
    }

    /// Mirror endpoint: PUT /mirror (BUD-04)
    var mirrorURL: URL {
        url.appendingPathComponent("mirror")
    }

    /// Blob download URL for a given SHA-256 hash
    func blobURL(sha256 hash: String, fileExtension ext: String? = nil) -> URL {
        if let ext {
            return url.appendingPathComponent("\(hash).\(ext)")
        }
        return url.appendingPathComponent(hash)
    }
}

/// Response from a Blossom upload (BUD-02).
struct BlossomBlobDescriptor: Codable, Equatable {
    let url: String
    let sha256: String
    let size: Int64
    let type: String?
    let uploaded: Int64?
}

enum BlossomError: Error, LocalizedError {
    case invalidServerURL
    case hashMismatch(expected: String, got: String)
    case uploadFailed(statusCode: Int)
    case invalidResponse
    case fileReadError(Error)
    case authError(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return NSLocalizedString("Invalid Blossom server URL", comment: "Error for bad Blossom server URL")
        case .hashMismatch(let expected, let got):
            return String(format: NSLocalizedString("File hash mismatch: expected %@, got %@", comment: "Error for Blossom hash mismatch"), expected, got)
        case .uploadFailed(let code):
            return String(format: NSLocalizedString("Upload failed with status %d", comment: "Error for Blossom upload failure"), code)
        case .invalidResponse:
            return NSLocalizedString("Invalid response from Blossom server", comment: "Error for bad Blossom response")
        case .fileReadError(let error):
            return error.localizedDescription
        case .authError(let msg):
            return msg
        }
    }
}
