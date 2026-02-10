//
//  FriendIcon.swift
//  damus
//
//  Created by William Casarin on 2023-04-20.
//

import SwiftUI

/// Pre-rendered friend icons to avoid per-frame gradient mask compositing.
/// The gradient mask + SF Symbol composition is expensive in Core Animation,
/// so we render once into a UIImage and blit the bitmap on each cell.
private let _friendIcon: UIImage = {
    let size = CGSize(width: 20, height: 14)
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { rendererCtx in
        let rect = CGRect(origin: .zero, size: size)
        let cg = rendererCtx.cgContext

        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let symbol = UIImage(systemName: "person.fill.checkmark", withConfiguration: config) else { return }

        // Draw symbol into the context (acts as mask source)
        symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: rect)

        // Composite gradient using sourceIn so it only fills where the symbol was drawn
        cg.saveGState()
        cg.setBlendMode(.sourceIn)
        let colors: [CGColor] = [
            UIColor(red: 204/255.0, green: 67/255.0, blue: 197/255.0, alpha: 1).cgColor,  // DamusPurple
            UIColor(red: 75/255.0, green: 77/255.0, blue: 255/255.0, alpha: 1).cgColor     // DamusBlue
        ]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) else {
            cg.restoreGState()
            return
        }
        // topTrailing → bottomTrailing to match LINEAR_GRADIENT
        cg.drawLinearGradient(gradient, start: CGPoint(x: rect.maxX, y: 0), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        cg.restoreGState()
    }
}()

private let _fofIcon: UIImage = {
    let size = CGSize(width: 21, height: 14)
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { _ in
        let rect = CGRect(origin: .zero, size: size)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let symbol = UIImage(systemName: "person.fill.and.arrow.left.and.arrow.right", withConfiguration: config) else { return }
        symbol.withTintColor(.gray, renderingMode: .alwaysOriginal).draw(in: rect)
    }
}()

struct FriendIcon: View {
    let friend: FriendType

    var body: some View {
        switch friend {
        case .friend:
            Image(uiImage: _friendIcon)
                .frame(width: 20, height: 14)
        case .fof:
            Image(uiImage: _fofIcon)
                .frame(width: 21, height: 14)
        }
    }
}

struct FriendIcon_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            FriendIcon(friend: .friend)

            FriendIcon(friend: .fof)
        }
    }
}
