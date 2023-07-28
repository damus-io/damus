// ImageSaver.swift

import UIKit

enum ImageSaverError {
    case permissions
    case unknown
}

class ImageSaver: NSObject, ObservableObject {
    var errorTitle: String = "Failed to save"
    var errorMessage: String = "Unable to save the photo."
    var errorType: ImageSaverError = .unknown
    @Published var error = false

    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted), nil)
    }

    @objc func saveCompleted(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeRawPointer
    ) {
        self.error = error != nil
    }
}
