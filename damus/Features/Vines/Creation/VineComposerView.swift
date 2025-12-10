//
//  VineComposerView.swift
//  damus
//
//  Created by OpenAI Codex on 2025-11-29.
//

import SwiftUI
import AVFoundation

struct VineComposerView: View {
    enum UploadPhase: Equatable {
        case idle
        case uploading
        case uploaded
        case failed(String)
        
        static func == (lhs: UploadPhase, rhs: UploadPhase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.uploading, .uploading), (.uploaded, .uploaded):
                return true
            case let (.failed(lhsMessage), .failed(rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
    @Environment(\.dismiss) private var dismiss
    
    let damus_state: DamusState
    
    @State private var showingMediaPicker = false
    @State private var selectedUpload: MediaUpload?
    @State private var mediaDescriptor: VineMediaDescriptor?
    @State private var uploadPhase: UploadPhase = .idle
    @State private var showingCamera = false
    
    @State private var vineIdentifier: String = ""
    @State private var titleText: String = ""
    @State private var captionText: String = ""
    @State private var summaryText: String = ""
    @State private var hashtagsInput: String = ""
    @State private var contentWarning: String = ""
    @State private var altText: String = ""
    @State private var originSource: String = ""
    @State private var originIdentifier: String = ""
    @State private var originDetail: String = ""
    @State private var referenceURL: String = ""
    
    @State private var isPublishing = false
    
    private let uploadService = VineBlossomUploadService()
    
    var body: some View {
        NavigationStack {
            Form {
                clipSection
                metadataSection
                advancedSection
            }
            .navigationTitle(NSLocalizedString("New Vine", comment: "Navigation title for the Vine composer view."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Button title to dismiss the Vine composer without publishing.")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Publish", comment: "Button title to publish the new Vine event.")) {
                        publishVine()
                    }
                    .disabled(!canPublish)
                }
            }
            .sheet(isPresented: $showingMediaPicker) {
                MediaPicker(
                    mediaPickerEntry: .postView,
                    onMediaSelected: nil,
                    onMediaPicked: { media in
                        handlePickedMedia(media)
                    }
                )
            }
            .sheet(isPresented: $showingCamera) {
                CameraController(
                    uploader: damus_state.settings.default_media_uploader,
                    imagesOnly: false,
                    mode: .handle_video { url in
                        showingCamera = false
                        handlePickedMedia(.processed_video(url))
                    }
                )
            }
        }
    }
    
    private var clipSection: some View {
        Section(NSLocalizedString("Clip", comment: "Section title for the selected Vine clip.")) {
            if let descriptor = mediaDescriptor,
               let url = descriptor.sources.first?.url {
                VStack(alignment: .leading, spacing: 6) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                    if let duration = descriptor.duration {
                        Text(String(format: NSLocalizedString("Duration: %.1fs", comment: "Label describing the video duration."), duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let size = descriptor.dimensions {
                        Text("\(Int(size.width))×\(Int(size.height))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text(NSLocalizedString("Attach a vertical clip (mp4/m3u8).", comment: "Placeholder text before a Vine clip is selected."))
                    .foregroundColor(.secondary)
            }
            
            Button {
                showingMediaPicker = true
            } label: {
                Label(NSLocalizedString("Choose Video", comment: "Button to open the media picker for Vine clips."), systemImage: "film")
            }
            
            Button {
                showingCamera = true
            } label: {
                Label(NSLocalizedString("Record Video", comment: "Button to open the Vine camera recorder."), systemImage: "video.fill")
            }
            .disabled(isUploadingVideo)

            switch uploadPhase {
            case .idle:
                EmptyView()
            case .uploading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(NSLocalizedString("Uploading to Blossom…", comment: "Status label shown while uploading Vine video to Blossom."))
                }
            case .uploaded:
                Label(NSLocalizedString("Upload complete.", comment: "Status label shown when Vine upload finishes successfully."), systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
            }
        }
    }
    
    private var metadataSection: some View {
        Section(NSLocalizedString("Details", comment: "Section title for Vine metadata fields.")) {
            TextField(NSLocalizedString("Title", comment: "Placeholder for Vine title field."), text: $titleText)
            TextField(NSLocalizedString("Caption", comment: "Placeholder for Vine caption field."), text: $captionText, prompt: Text(NSLocalizedString("Describe your Vine…", comment: "Prompt for Vine caption field.")))
            TextField(NSLocalizedString("Summary (optional)", comment: "Placeholder for Vine summary field."), text: $summaryText)
            TextField(NSLocalizedString("Hashtags (comma separated)", comment: "Placeholder for Vine hashtag field."), text: $hashtagsInput)
        }
    }
    
    private var advancedSection: some View {
        Section(NSLocalizedString("Advanced", comment: "Section title for optional Vine metadata fields.")) {
            TextField(NSLocalizedString("Identifier (optional)", comment: "Placeholder for Vine identifier/d-tag field."), text: $vineIdentifier)
            TextField(NSLocalizedString("Content warning (optional)", comment: "Placeholder for the Vine content warning field."), text: $contentWarning)
            TextField(NSLocalizedString("Alt text (optional)", comment: "Placeholder for Vine alternative text field."), text: $altText)
            TextField(NSLocalizedString("Origin source", comment: "Placeholder for Vine origin source field."), text: $originSource)
            TextField(NSLocalizedString("Origin identifier", comment: "Placeholder for Vine origin identifier field."), text: $originIdentifier)
            TextField(NSLocalizedString("Origin detail", comment: "Placeholder for Vine origin detail field."), text: $originDetail)
            TextField(NSLocalizedString("Reference link", comment: "Placeholder for Vine reference link field."), text: $referenceURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
    }
    
    private var canPublish: Bool {
        guard damus_state.keypair.privkey != nil else { return false }
        guard mediaDescriptor != nil else { return false }
        guard case .uploaded = uploadPhase else { return false }
        return !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPublishing
    }
    
    private var isUploadingVideo: Bool {
        if case .uploading = uploadPhase {
            return true
        }
        return false
    }
    
    private func handlePickedMedia(_ media: PreUploadedMedia) {
        Task {
            guard var upload = generateMediaUpload(media) else {
                await MainActor.run {
                    uploadPhase = .failed(NSLocalizedString("Unable to process media.", comment: "Error shown when Vine composer cannot process selected media."))
                }
                return
            }
            
            guard case .video(let localURL) = upload else {
                await MainActor.run {
                    uploadPhase = .failed(NSLocalizedString("Please select a video clip.", comment: "Error shown when user selects a non-video media for Vine composer."))
                }
                return
            }
            
            if let convertedURL = await convertVideoToMP4IfNeeded(localURL: localURL) {
                upload = .video(convertedURL)
            } else if localURL.pathExtension.lowercased() != "mp4" {
                await MainActor.run {
                    uploadPhase = .failed(NSLocalizedString("Unable to convert clip to MP4.", comment: "Error shown when Vine composer cannot transcode to MP4 for upload."))
                }
                return
            }
            
            await MainActor.run {
                selectedUpload = upload
            }
            await uploadSelectedMedia(upload)
        }
    }
    
    @MainActor
    private func uploadSelectedMedia(_ media: MediaUpload) async {
        guard let keypair = damus_state.keypair.privkey != nil ? damus_state.keypair : nil else {
            uploadPhase = .failed(NSLocalizedString("A signing key is required to upload.", comment: "Error shown when trying to upload a Vine without a private key."))
            return
        }
        uploadPhase = .uploading
        mediaDescriptor = nil
        
        let metadata = videoMetadata(for: media.localURL)
        
        Task.detached {
            do {
                let response = try await uploadService.uploadVideo(
                    fileURL: media.localURL,
                    mimeType: media.mime_type,
                    keypair: keypair
                )
                let descriptor = self.makeDescriptor(from: response, mimeType: media.mime_type, videoMetadata: metadata)
                await MainActor.run {
                    self.mediaDescriptor = descriptor
                    if self.vineIdentifier.isEmpty {
                        self.vineIdentifier = response.videoID
                    }
                    self.uploadPhase = .uploaded
                }
            } catch {
                await MainActor.run {
                    if let vineError = error as? VineBlossomUploadError {
                        self.uploadPhase = .failed(vineError.localizedDescription)
                    } else {
                        self.uploadPhase = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func videoMetadata(for url: URL) -> (duration: TimeInterval?, dimensions: CGSize?) {
        let asset = AVURLAsset(url: url)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        var dimensions: CGSize?
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            dimensions = CGSize(width: abs(size.width), height: abs(size.height))
        }
        return (durationSeconds.isFinite ? durationSeconds : nil, dimensions)
    }
    
    private func convertVideoToMP4IfNeeded(localURL: URL) async -> URL? {
        return await withCheckedContinuation { continuation in
            let asset = AVAsset(url: localURL)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                continuation.resume(returning: localURL.pathExtension.lowercased() == "mp4" ? localURL : nil)
                return
            }
            
            let destinationURL = generateUniqueTemporaryMediaURL(fileExtension: "mp4")
            exporter.outputURL = destinationURL
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true
            exporter.metadataItemFilter = AVMetadataItemFilter.forSharing()
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: destinationURL)
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func makeDescriptor(from response: VineBlossomUploadResponse, mimeType: String, videoMetadata: (duration: TimeInterval?, dimensions: CGSize?)) -> VineMediaDescriptor {
        var sources: [VineMediaDescriptor.Source] = []
        func append(_ url: URL?, kind: VineMediaDescriptor.Source.Kind) {
            guard let url else { return }
            sources.append(.init(url: url, kind: kind))
        }
        append(response.primaryURL, kind: sourceKind(for: response.primaryURL))
        append(response.streamingMP4URL, kind: .mp4)
        append(response.streamingHLSURL, kind: .hls)
        append(response.fallbackURL, kind: .fallback)
        return VineMediaDescriptor(
            sources: sources,
            mimeType: mimeType,
            thumbnailURL: response.thumbnailURL,
            blurhash: nil,
            dimensions: videoMetadata.dimensions,
            duration: videoMetadata.duration,
            fileSize: nil,
            sha256: response.videoID
        )
    }
    
    private func sourceKind(for url: URL) -> VineMediaDescriptor.Source.Kind {
        switch url.pathExtension.lowercased() {
        case "m3u8":
            return .hls
        case "mp4":
            return .mp4
        default:
            return .legacy
        }
    }
    
    private func publishVine() {
        guard let descriptor = mediaDescriptor else { return }
        let metadata = VineDraftMetadata(
            identifier: vineIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vineIdentifier,
            title: titleText.trimmingCharacters(in: .whitespacesAndNewlines),
            caption: captionText.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : summaryText,
            hashtags: parsedHashtags(),
            publishedAt: Date(),
            contentWarning: contentWarning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : contentWarning,
            altText: altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : altText,
            origin: originDescriptor(),
            references: parsedReferences(),
            participants: [],
            expiration: nil,
            extraTags: []
        )
        
        let builder = VineEventBuilder(metadata: metadata, media: descriptor)
        guard let post = builder.makePost() else {
            uploadPhase = .failed(NSLocalizedString("Failed to build Vine event.", comment: "Error shown when Vine builder fails to produce an event."))
            return
        }
        
        isPublishing = true
        notify(.post(.post(post)))
        dismiss()
    }
    
    private func parsedHashtags() -> [String] {
        let characterSet = CharacterSet(charactersIn: ",")
        return hashtagsInput
            .components(separatedBy: characterSet.union(.whitespacesAndNewlines))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func parsedReferences() -> [URL] {
        guard let url = URL(string: referenceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              !referenceURL.isEmpty else {
            return []
        }
        return [url]
    }
    
    private func originDescriptor() -> VineOriginDescriptor? {
        let trimmedSource = originSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return nil }
        let identifier = originIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = originDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        return VineOriginDescriptor(
            source: trimmedSource,
            identifier: identifier.isEmpty ? nil : identifier,
            detail: detail.isEmpty ? nil : detail
        )
    }
}
