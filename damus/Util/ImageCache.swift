//
//  ImageCache.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import Foundation
import SwiftUI

extension UIImage {
    func decodedImage(_ size: Int) -> UIImage {
        guard let cgImage = cgImage else { return self }
        let scale = UIScreen.main.scale
        let pix_size = CGFloat(size) * scale
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        //let cgsize = CGSize(width: size, height: size)
        
        let context = CGContext(data: nil, width: Int(pix_size), height: Int(pix_size), bitsPerComponent: 8, bytesPerRow: cgImage.bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        //UIGraphicsBeginImageContextWithOptions(cgsize, true, 0)
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: pix_size, height: pix_size))
        //UIGraphicsEndImageContext()

        guard let decodedImage = context?.makeImage() else { return self }
        return UIImage(cgImage: decodedImage, scale: scale, orientation: .up)
    }
}
