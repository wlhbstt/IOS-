import CoreImage
import Photos
import UIKit

enum PhotoEditError: LocalizedError {
    case cloud, unavailable, changed, render, noSubject, livePair

    var errorDescription: String? {
        switch self {
        case .cloud: return "原件在 iCloud。下载后可继续编辑。"
        case .unavailable: return "当前照片无法编辑，请检查系统相册的访问权限。"
        case .changed: return "照片已在相册中变化，请重新打开编辑。"
        case .render: return "照片处理失败，请重试。"
        case .noSubject: return "没有找到清晰的主体。"
        case .livePair: return "无法生成完整的实况副本。请重试或选择保存到原图。"
        }
    }
}

enum PhotoEditSave {
    static func input(for asset: PHAsset, network: Bool) async throws -> PHContentEditingInput {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = network
        // Work from the visible version, including any edits made in Photos or other apps.
        options.canHandleAdjustmentData = { _ in false }
        let state = PhotoRequest<PHContentEditingInput>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.attach(continuation)
                let id = asset.requestContentEditingInput(with: options) { input, info in
                    if let input { state.finish(.success(input)) }
                    else if (info[PHContentEditingInputResultIsInCloudKey] as? Bool) == true { state.finish(.failure(PhotoEditError.cloud)) }
                    else { state.finish(.failure(PhotoEditError.unavailable)) }
                }
                state.onCancel { asset.cancelContentEditingInputRequest(id) }
            }
        } onCancel: { state.cancel() }
    }

    static func playback(_ input: PHContentEditingInput, edits: PhotoEdits,
                         renderer: PhotoEditRenderer, fullSize: Bool = false) async throws -> PHLivePhoto {
        let context = try liveContext(input, edits: edits, renderer: renderer)
        let sourceSize = context.fullSizeImage.extent.size
        let scale = fullSize ? 1 : min(1, 960 / max(sourceSize.width, sourceSize.height))
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                context.prepareLivePhotoForPlayback(withTargetSize: size,
                    options: [PHLivePhotoEditingOption.shouldRenderAtPlaybackTime.rawValue: false]) { photo, error in
                    if let photo { continuation.resume(returning: photo) }
                    else { continuation.resume(throwing: error ?? PhotoEditError.render) }
                }
            }
        } onCancel: { context.cancel() }
    }

    private static func liveContext(_ input: PHContentEditingInput, edits: PhotoEdits,
                                    renderer: PhotoEditRenderer) throws -> PHLivePhotoEditingContext {
        guard edits.background == .original, let context = PHLivePhotoEditingContext(livePhotoEditingInput: input) else {
            throw PhotoEditError.unavailable
        }
        context.frameProcessor = { frame, _ in
            autoreleasepool { try? renderer.apply(edits, to: frame.image) }
        }
        return context
    }

    static func save(asset: PHAsset, input: PHContentEditingInput, edits: PhotoEdits, copy: Bool,
                     renderer: PhotoEditRenderer, mask: CIImage?) async throws {
        let live = asset.mediaSubtypes.contains(.photoLive)
        let output = PHContentEditingOutput(contentEditingInput: input)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        var stillURL: URL?
        var motionURL: URL?
        if live && copy {
            let rendered = try await playback(input, edits: edits, renderer: renderer, fullSize: true)
            let resources = PHAssetResource.assetResources(for: rendered)
            guard let photo = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }),
                  let motion = resources.first(where: { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo }) else {
                throw PhotoEditError.livePair
            }
            let still = temporary.appendingPathComponent("photo").appendingPathExtension(URL(fileURLWithPath: photo.originalFilename).pathExtension)
            let video = temporary.appendingPathComponent("motion.mov")
            try await PHAssetResourceManager.default().writeData(for: photo, toFile: still, options: nil)
            try await PHAssetResourceManager.default().writeData(for: motion, toFile: video, options: nil)
            try await validateLivePair(still: still, motion: video)
            stillURL = still
            motionURL = video
        } else if live {
            let context = try liveContext(input, edits: edits, renderer: renderer)
            try await withTaskCancellationHandler { try await context.saveLivePhoto(to: output) } onCancel: { context.cancel() }
        } else {
            guard let url = input.fullSizeImageURL, let source = CIImage(contentsOf: url) else { throw PhotoEditError.unavailable }
            let transparent = copy && edits.background == .cutout
            let target = copy ? temporary.appendingPathComponent(transparent ? "photo.png" : "photo.jpg") : output.renderedContentURL
            stillURL = target
            let image = source.oriented(forExifOrientation: input.fullSizeImageOrientation).atOrigin()
            try await Task.detached(priority: .userInitiated) {
                let edited = try renderer.apply(edits, to: image, mask: mask, transparent: transparent)
                try renderer.write(edited, to: target, transparent: transparent)
            }.value
        }

        try Task.checkCancellation()
        guard let current = PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: PhotoAccess.fetchOptions()).firstObject,
              current.modificationDate == asset.modificationDate else { throw PhotoEditError.changed }
        if copy {
            guard let photo = stillURL else { throw PhotoEditError.render }
            let video = motionURL
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: photo, options: nil)
                if let video { request.addResource(with: .pairedVideo, fileURL: video, options: nil) }
                request.creationDate = current.creationDate
                request.location = current.location
            }
        } else {
            guard current.canPerform(.content) else { throw PhotoEditError.unavailable }
            output.adjustmentData = PHAdjustmentData(formatIdentifier: "com.localphototools.PhotoCleaner.edit",
                                                    formatVersion: "1", data: try JSONEncoder().encode(edits))
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: current).contentEditingOutput = output
            }
        }
    }

    private static func validateLivePair(still: URL, motion: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHLivePhoto.request(withResourceFileURLs: [still, motion], placeholderImage: nil,
                                targetSize: CGSize(width: 160, height: 160), contentMode: .aspectFit) { photo, info in
                guard (info[PHLivePhotoInfoIsDegradedKey] as? Bool) != true else { return }
                if photo != nil { continuation.resume() }
                else { continuation.resume(throwing: PhotoEditError.livePair) }
            }
        }
    }
}
