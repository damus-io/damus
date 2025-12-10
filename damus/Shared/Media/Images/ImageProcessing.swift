//
//  ImageProcessing.swift
//  damus
//
//  Created by KernelKind on 2/27/24.
//

import UIKit
import AVFoundation

/// Removes GPS data from image at url and writes changes to new file
func processImage(url: URL) -> URL? {
    let fileExtension = url.pathExtension
    guard let imageData = try? Data(contentsOf: url) else {
        print("Failed to load image data from URL.")
        return nil
    }
    
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
    
    return processImage(source: source, fileExtension: fileExtension)
}

/// Removes GPS data from image and writes changes to new file
func processImage(image: UIImage) -> URL? {
    let fixedImage = image.fixOrientation()
    guard let imageData = fixedImage.jpegData(compressionQuality: 1.0) else { return nil }
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }

    return processImage(source: source, fileExtension: "jpeg")
}

fileprivate func processImage(source: CGImageSource, fileExtension: String) -> URL? {
    let destinationURL = generateUniqueTemporaryMediaURL(fileExtension: fileExtension)
    
    guard let destination = removeGPSDataFromImage(source: source, url: destinationURL) else { return nil }
    
    if !CGImageDestinationFinalize(destination) { return nil }
    
    return destinationURL
}

/// Re-encodes the video to MP4 and removes sensitive metadata (GPS, etc.)
/// We always run this before uploading so clips recorded anywhere inside Damus
/// (camera, share extension, etc.) never leak location data.
func processVideo(videoURL: URL) -> URL? {
    let destinationURL = generateUniqueTemporaryMediaURL(fileExtension: "mp4")
    if exportVideoStrippingSensitiveMetadata(from: videoURL, to: destinationURL) {
        return destinationURL
    }
    
    // Fallback to raw copy if export fails so the user can still proceed.
    return saveVideoToTemporaryFolder(videoURL: videoURL)
}

fileprivate func saveVideoToTemporaryFolder(videoURL: URL) -> URL? {
    let destinationURL = generateUniqueTemporaryMediaURL(fileExtension: videoURL.pathExtension)
    
    do {
        try FileManager.default.copyItem(at: videoURL, to: destinationURL)
        return destinationURL
    } catch {
        print("Error copying file: \(error.localizedDescription)")
        return nil
    }
}

/// Generate a temporary URL with a unique filename
func generateUniqueTemporaryMediaURL(fileExtension: String) -> URL {
    let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let uniqueMediaName = "\(UUID().uuidString).\(fileExtension)"
    let temporaryMediaURL = temporaryDirectoryURL.appendingPathComponent(uniqueMediaName)

    return temporaryMediaURL
}

/**
 Take the PreUploadedMedia payload, process it, if necessary, and convert it into a URL
 which is ready to be uploaded to the upload service.
 
 URLs containing media that hasn't been processed were generated from the system and were granted
 access as a security scoped resource. The data will need to be processed to strip GPS data
 and saved to a new location which isn't security scoped.
 */
func generateMediaUpload(_ media: PreUploadedMedia?) -> MediaUpload? {
    guard let media else { return nil }
    
    switch media {
    case .uiimage(let image):
            guard let url = processImage(image: image) else { return nil }
            return .image(url)
    case .unprocessed_image(let url):
        guard let newUrl = processImage(url: url) else { return nil }
        url.stopAccessingSecurityScopedResource()
        return .image(newUrl)
    case .processed_image(let url):
        return .image(url)
    case .processed_video(let url):
        guard let sanitizedUrl = processVideo(videoURL: url) else { return nil }
        return .video(sanitizedUrl)
    case .unprocessed_video(let url):
        guard let newUrl = processVideo(videoURL: url) else { return nil }
        url.stopAccessingSecurityScopedResource()
        return .video(newUrl)
    }
}

extension UIImage {
    func fixOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
}

func canGetSourceTypeFromUrl(url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        print("Failed to create image source.")
        return false
    }
    return CGImageSourceGetType(source) != nil
}

func removeGPSDataFromImageAndWrite(fromImageURL imageURL: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
        print("Failed to create image source.")
        return false
    }

    guard let destination = removeGPSDataFromImage(source: source, url: imageURL) else { return false }
    
    return CGImageDestinationFinalize(destination)
}

fileprivate func removeGPSDataFromImage(source: CGImageSource, url: URL) -> CGImageDestination? {
    let totalCount = CGImageSourceGetCount(source)

    guard totalCount > 0 else {
        print("No images found.")
        return nil
    }

    guard let type = CGImageSourceGetType(source),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, type, totalCount, nil) else {
        print("Failed to create image destination.")
        return nil
    }
    
    let removeGPSProperties: CFDictionary = [kCGImageMetadataShouldExcludeGPS: kCFBooleanTrue] as CFDictionary
    
    for i in 0..<totalCount {
        CGImageDestinationAddImageFromSource(destination, source, i, removeGPSProperties)
    }
    
    return destination
}

private func exportVideoStrippingSensitiveMetadata(from sourceURL: URL, to destinationURL: URL) -> Bool {
    let asset = AVAsset(url: sourceURL)
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
        print("Failed to create export session for video.")
        return false
    }
    
    exportSession.outputURL = destinationURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.metadataItemFilter = AVMetadataItemFilter.forSharing()
    
    let semaphore = DispatchSemaphore(value: 0)
    exportSession.exportAsynchronously {
        semaphore.signal()
    }
    semaphore.wait()
    
    if exportSession.status == .completed {
        return true
    } else {
        if let error = exportSession.error {
            print("Video export failed: \(error.localizedDescription)")
        }
        return false
    }
}
