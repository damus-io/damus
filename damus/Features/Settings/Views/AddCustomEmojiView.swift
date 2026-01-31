//
//  AddCustomEmojiView.swift
//  damus
//
//  Created for NIP-30 custom emoji upload support.
//

import SwiftUI
import PhotosUI

/// View for uploading a new custom emoji.
///
/// Allows users to select an image, enter a shortcode, and upload to their preferred media server.
struct AddCustomEmojiView: View {
    let damus_state: DamusState

    @Environment(\.dismiss) var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var shortcode: String = ""
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var errorMessage: String?
    @State private var selectedUploader: MediaUploader?

    /// Size to resize emoji images to before upload.
    private let emojiSize: CGFloat = 128

    var body: some View {
        NavigationView {
            Form {
                imageSection
                shortcodeSection
                uploaderSection

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                uploadSection
            }
            .navigationTitle(NSLocalizedString("Add Custom Emoji", comment: "Title for add custom emoji view"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedItem) { newItem in
                loadImage(from: newItem)
            }
            .disabled(isUploading)
        }
    }

    // MARK: - Sections

    private var imageSection: some View {
        Section {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                if let selectedImage {
                    HStack {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("Change Image", comment: "Button to change selected image")
                            .foregroundColor(.accentColor)
                    }
                } else {
                    Label(
                        NSLocalizedString("Select Image", comment: "Button to select emoji image"),
                        systemImage: "photo.on.rectangle"
                    )
                }
            }
        } header: {
            Text("Emoji Image", comment: "Section header for emoji image selection")
        } footer: {
            Text("Image will be resized to \(Int(emojiSize))x\(Int(emojiSize)) pixels.", comment: "Footer explaining image resize")
        }
    }

    private var shortcodeSection: some View {
        Section {
            TextField(NSLocalizedString("shortcode", comment: "Placeholder for emoji shortcode"), text: $shortcode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: shortcode) { newValue in
                    shortcode = sanitizeShortcode(newValue)
                }

            if !shortcode.isEmpty {
                Text(":\(shortcode):")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Shortcode", comment: "Section header for emoji shortcode")
        } footer: {
            Text("Lowercase letters, numbers, and underscores only. 2-32 characters.", comment: "Footer explaining shortcode rules")
        }
    }

    private var uploaderSection: some View {
        Section {
            Picker(NSLocalizedString("Upload to", comment: "Label for media uploader selection"), selection: $selectedUploader) {
                Text("Default (\(effectiveUploader.model.displayName))", comment: "Default uploader option")
                    .tag(nil as MediaUploader?)

                ForEach(MediaUploader.allCases, id: \.self) { uploader in
                    Text(uploader.model.displayName)
                        .tag(uploader as MediaUploader?)
                }
            }
        } header: {
            Text("Upload Service", comment: "Section header for upload service")
        }
    }

    private var uploadSection: some View {
        Section {
            if isUploading {
                HStack {
                    ProgressView(value: uploadProgress)
                    Text("\(Int(uploadProgress * 100))%")
                        .foregroundColor(.secondary)
                }
            } else {
                Button {
                    uploadEmoji()
                } label: {
                    HStack {
                        Spacer()
                        Label(
                            NSLocalizedString("Upload Emoji", comment: "Button to upload emoji"),
                            systemImage: "arrow.up.circle.fill"
                        )
                        Spacer()
                    }
                }
                .disabled(!canUpload)
            }
        }
    }

    // MARK: - Computed Properties

    private var effectiveUploader: MediaUploader {
        selectedUploader ?? damus_state.settings.default_media_uploader
    }

    private var canUpload: Bool {
        selectedImage != nil && isValidShortcode(shortcode)
    }

    // MARK: - Shortcode Validation

    /// Validates a shortcode against NIP-30 requirements.
    ///
    /// - Parameter shortcode: The shortcode to validate.
    /// - Returns: True if the shortcode is valid.
    private func isValidShortcode(_ shortcode: String) -> Bool {
        guard shortcode.count >= 2, shortcode.count <= 32 else { return false }
        guard !shortcode.hasPrefix("_"), !shortcode.hasSuffix("_") else { return false }

        let allowedCharacters = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "_"))

        return shortcode.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    /// Sanitizes input to only allow valid shortcode characters.
    ///
    /// - Parameter input: The raw input string.
    /// - Returns: Sanitized string with only valid characters.
    private func sanitizeShortcode(_ input: String) -> String {
        let lowercased = input.lowercased()
        let allowedCharacters = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "_"))

        return String(lowercased.unicodeScalars.filter { allowedCharacters.contains($0) }.prefix(32))
    }

    // MARK: - Image Handling

    private func loadImage(from item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    await MainActor.run {
                        errorMessage = NSLocalizedString("Failed to load image", comment: "Error when image loading fails")
                    }
                    return
                }
                await MainActor.run {
                    selectedImage = resizeImage(uiImage, to: CGSize(width: emojiSize, height: emojiSize))
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Resizes an image to the specified size.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - size: The target size.
    /// - Returns: Resized UIImage.
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Upload

    private func uploadEmoji() {
        guard let image = selectedImage else { return }
        guard isValidShortcode(shortcode) else {
            errorMessage = NSLocalizedString("Invalid shortcode", comment: "Error for invalid shortcode")
            return
        }

        // Check if shortcode already exists
        if damus_state.custom_emojis.isSaved(shortcode) {
            errorMessage = NSLocalizedString("An emoji with this shortcode already exists", comment: "Error for duplicate shortcode")
            return
        }

        errorMessage = nil
        isUploading = true
        uploadProgress = 0

        Task {
            do {
                let url = try await performUpload(image: image)
                await saveEmoji(shortcode: shortcode, url: url)
                await MainActor.run {
                    isUploading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isUploading = false
                }
            }
        }
    }

    /// Performs the image upload to the media server.
    ///
    /// - Parameter image: The image to upload.
    /// - Returns: The URL of the uploaded image.
    /// - Throws: An error if the upload fails.
    private func performUpload(image: UIImage) async throws -> URL {
        guard let pngData = image.pngData() else {
            throw UploadError.invalidImage
        }

        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("emoji_\(UUID().uuidString).png")
        try pngData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let uploader = effectiveUploader
        let progressDelegate = UploadProgressDelegate { progress in
            Task { @MainActor in
                self.uploadProgress = progress
            }
        }

        let result = await AttachMediaUtility.create_upload_request(
            mediaToUpload: .image(tempURL),
            mediaUploader: uploader,
            mediaType: .normal,
            progress: progressDelegate,
            keypair: damus_state.keypair.to_full()?.to_keypair()
        )

        switch result {
        case .success(let urlString):
            guard let url = URL(string: urlString) else {
                throw UploadError.invalidResponse
            }
            return url
        case .failed(let error):
            throw error ?? UploadError.uploadFailed
        }
    }

    /// Saves the uploaded emoji to the store and publishes the updated list.
    @MainActor
    private func saveEmoji(shortcode: String, url: URL) async {
        let emoji = CustomEmoji(shortcode: shortcode, url: url)
        damus_state.custom_emojis.save(emoji)
        await damus_state.custom_emojis.publishEmojiList(damus_state: damus_state)
    }

    // MARK: - Error Types

    enum UploadError: LocalizedError {
        case invalidImage
        case invalidResponse
        case uploadFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return NSLocalizedString("Failed to process image", comment: "Error when image processing fails")
            case .invalidResponse:
                return NSLocalizedString("Invalid response from server", comment: "Error when server response is invalid")
            case .uploadFailed:
                return NSLocalizedString("Upload failed", comment: "Generic upload failure error")
            }
        }
    }
}

// MARK: - Upload Progress Delegate

/// Delegate for tracking upload progress.
private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(progress)
    }
}

#Preview {
    AddCustomEmojiView(damus_state: test_damus_state)
}
