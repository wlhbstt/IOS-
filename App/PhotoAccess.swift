import CryptoKit
import AVFoundation
import Photos
import UIKit
import PhotoCleanerCore

enum PhotoAccessError: LocalizedError {
    case unavailable, missing, noResource

    var errorDescription: String? {
        switch self {
        case .unavailable: return "内容未存储在本机，或暂时无法读取。"
        case .missing: return "照片已删除或不再有访问权限。"
        case .noResource: return "未找到可读取的原始媒体文件。"
        }
    }
}

// PhotoKit may finish synchronously, emit multiple image callbacks, or be cancelled.
private final class PhotoRequest<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var cancellation: (() -> Void)?

    func attach(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }

    func onCancel(_ cancellation: @escaping () -> Void) {
        lock.lock()
        let cancelled: Bool
        if case .failure(let error) = result { cancelled = error is CancellationError }
        else { cancelled = false }
        if !cancelled { self.cancellation = cancellation }
        lock.unlock()
        if cancelled { cancellation() }
    }

    func finish(_ value: Result<Value, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let continuation = self.continuation
        self.continuation = nil
        cancellation = nil
        lock.unlock()
        continuation?.resume(with: value)
    }

    func cancel() {
        lock.lock()
        let cancellation = self.cancellation
        lock.unlock()
        finish(.failure(CancellationError()))
        cancellation?()
    }
}

private final class ResourceAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var hash = SHA256()
    private var bytes: Int64 = 0

    func append(_ data: Data) {
        lock.lock()
        bytes += Int64(data.count)
        hash.update(data: data)
        lock.unlock()
    }

    func summary() -> (Int64, String) {
        lock.lock()
        defer { lock.unlock() }
        return (bytes, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

struct AlbumChoice: Identifiable {
    let id: String
    let title: String
}

final class PhotoAccess: @unchecked Sendable {
    private let images = PHCachingImageManager()

    func assets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var result: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in result.append(asset) }
        return result
    }

    func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func metadata(_ asset: PHAsset) -> MediaRecord {
        let resources = PHAssetResource.assetResources(for: asset)
        var record = MediaRecord(id: asset.localIdentifier)
        record.filename = resources.first(where: { $0.type == .photo || $0.type == .video })?.originalFilename ?? ""
        record.createdAt = asset.creationDate
        record.modifiedAt = asset.modificationDate
        record.kind = asset.mediaType == .video ? .video : .image
        record.isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        record.isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
        record.isFavorite = asset.isFavorite
        record.isComplex = resources.count != 1 || resources.first?.type != .photo
        record.width = asset.pixelWidth
        record.height = asset.pixelHeight
        record.duration = asset.duration
        if record.isScreenshot { record.tags = ["截图"] }
        if record.isLivePhoto { record.tags.append("实况照片") }
        if record.kind == .video { record.tags.append("视频") }
        return record
    }

    func albums() -> [AlbumChoice] {
        var result: [AlbumChoice] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            .enumerateObjects { collection, _, _ in
                result.append(AlbumChoice(id: collection.localIdentifier, title: collection.localizedTitle ?? "相簿"))
            }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func protectedIDs(albumIDs: Set<String>) -> Set<String> {
        var result = Set<String>()
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(albumIDs), options: nil)
            .enumerateObjects { album, _, _ in
                PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
                    result.insert(asset.localIdentifier)
                }
            }
        return result
    }

    func image(id: String, size: CGSize, network: Bool = false) async throws -> UIImage {
        guard let asset = asset(id) else { throw PhotoAccessError.missing }
        let state = PhotoRequest<UIImage>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                state.attach(continuation)
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = network
                options.deliveryMode = .highQualityFormat
                options.resizeMode = size == PHImageManagerMaximumSize ? .none : .fast
                let requestID = images.requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                     options: options) { image, info in
                    if (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true { return }
                    if let error = info?[PHImageErrorKey] as? Error { state.finish(.failure(error)) }
                    else if let image { state.finish(.success(image)) }
                    else { state.finish(.failure(PhotoAccessError.unavailable)) }
                }
                state.onCancel { [images] in images.cancelImageRequest(requestID) }
            }
        }, onCancel: { state.cancel() })
    }

    func originalSummary(asset: PHAsset, network: Bool) async throws -> (bytes: Int64, digest: String?) {
        let originals = PHAssetResource.assetResources(for: asset).filter {
            [.photo, .video, .pairedVideo, .alternatePhoto, .audio].contains($0.type)
        }
        guard !originals.isEmpty else { throw PhotoAccessError.noResource }
        var bytes: Int64 = 0
        var digest: String?
        for resource in originals {
            try Task.checkCancellation()
            let summary = try await read(resource, network: network)
            bytes += summary.0
            if originals.count == 1 && resource.type == .photo { digest = summary.1 }
        }
        return (bytes, digest)
    }

    private func read(_ resource: PHAssetResource, network: Bool) async throws -> (Int64, String) {
        let state = PhotoRequest<(Int64, String)>()
        let accumulator = ResourceAccumulator()
        let manager = PHAssetResourceManager.default()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                state.attach(continuation)
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = network
                let requestID = manager.requestData(for: resource, options: options,
                    dataReceivedHandler: { accumulator.append($0) }, completionHandler: { error in
                        if let error { state.finish(.failure(error)) }
                        else { state.finish(.success(accumulator.summary())) }
                    })
                state.onCancel { manager.cancelDataRequest(requestID) }
            }
        }, onCancel: { state.cancel() })
    }

    func delete(ids: Set<String>) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        guard assets.count == ids.count else { throw PhotoAccessError.missing }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    func playerItem(id: String, network: Bool) async throws -> AVPlayerItem {
        guard let asset = asset(id) else { throw PhotoAccessError.missing }
        let state = PhotoRequest<AVPlayerItem>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                state.attach(continuation)
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = network
                let requestID = images.requestPlayerItem(forVideo: asset, options: options) { item, info in
                    if let error = info?[PHImageErrorKey] as? Error { state.finish(.failure(error)) }
                    else if let item { state.finish(.success(item)) }
                    else { state.finish(.failure(PhotoAccessError.unavailable)) }
                }
                state.onCancel { [images] in images.cancelImageRequest(requestID) }
            }
        }, onCancel: { state.cancel() })
    }
}

final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    var changed: (() -> Void)?
    func photoLibraryDidChange(_ changeInstance: PHChange) { changed?() }
}
