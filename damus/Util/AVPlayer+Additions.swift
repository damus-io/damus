//
//  AVPlayer+Additions.swift
//  damus
//
//  Created by Bryan Montz on 9/6/23.
//

import AVFoundation
import Foundation
import UIKit

extension AVPlayer {
#if !os(macOS)
    var currentImage: UIImage? {
        guard
            let playerItem = currentItem,
            let cgImage = try? AVAssetImageGenerator(asset: playerItem.asset).copyCGImage(at: currentTime(), actualTime: nil)
        else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
#else
    var currentImage: NSImage? {
        guard
            let playerItem = currentItem,
            let cgImage = try? AVAssetImageGenerator(asset: playerItem.asset).copyCGImage(at: currentTime(), actualTime: nil)
        else {
            return nil
        }
        let width: CGFloat = CGFloat(cgImage.width)
        let height: CGFloat = CGFloat(cgImage.height)
        return NSImage(cgImage: cgImage, size: NSMakeSize(width, height))
    }
#endif
}
