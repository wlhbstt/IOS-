import AVFoundation
import Combine
import ImageIO
import Photos
import UniformTypeIdentifiers
import UIKit

enum CompressionError: LocalizedError {
    case unsupported, encoding, notSmaller, changed, permission

    var errorDescription: String? {
        switch self {
        case .unsupported: return "暂不支持实况、RAW、动画、连拍或已编辑的复杂资源，请选择普通照片或视频。"
        case .encoding: return "无法生成压缩副本，请尝试其他尺寸或画质。"
        case .notSmaller: return "压缩结果没有变小，未保存副本。请降低尺寸或画质后重试。"
        case .changed: return "原件已变化或无法访问，请返回相册重新选择。"
        case .permission: return "需要现有相册读写权限才能保存副本，请在设置中检查。"
        }
    }
}

enum CompressionVideoSize: String, CaseIterable, Identifiable, Sendable {
    case compact = "720p", balanced = "1080p"
    var id: String { rawValue }
    var preset: String { self == .compact ? AVAssetExportPreset1280x720 : AVAssetExportPreset1920x1080 }
}

struct CompressionOptions: Sendable {
    var quality = 0.7
    var maxDimension = 2048
    var videoSize = CompressionVideoSize.balanced
}

final class CompressionDraft: @unchecked Sendable {
    let originalID: String
    let originalModifiedAt: Date?
    let originalBytes: Int64
    let outputBytes: Int64
    let outputURL: URL
    let isVideo: Bool
    private let directory: URL

    init(asset: PHAsset, originalBytes: Int64, outputBytes: Int64, outputURL: URL, directory: URL) {
        originalID = asset.localIdentifier
        originalModifiedAt = asset.modificationDate
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
        self.outputURL = outputURL
        self.directory = directory
        isVideo = asset.mediaType == .video
    }

    var savedBytes: Int64 { originalBytes - outputBytes }
    func discard() { try? FileManager.default.removeItem(at: directory) }
    deinit { discard() }
}

// PhotoKit delivers chunks on its own queue; cancellation closes the file before cleanup.
private final class CompressionResourceWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?
    private var continuation: CheckedContinuation<Int64, Error>?
    private var result: Result<Int64, Error>?
    private var requestID: PHAssetResourceDataRequestID?
    private var bytes: Int64 = 0
    private var writeError: Error?

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CompressionError.encoding }
        handle = try FileHandle(forWritingTo: url)
    }

    func attach(_ continuation: CheckedContinuation<Int64, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }

    func setRequest(_ id: PHAssetResourceDataRequestID) {
        lock.lock()
        let finished = result != nil
        requestID = id
        lock.unlock()
        if finished { PHAssetResourceManager.default().cancelDataRequest(id) }
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard result == nil, writeError == nil else { return }
        do { try handle?.write(contentsOf: data); bytes += Int64(data.count) }
        catch { writeError = error }
    }

    func finish(_ error: Error? = nil) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        var failure = error ?? writeError
        do { try handle?.close() } catch { if failure == nil { failure = error } }
        handle = nil
        let outcome: Result<Int64, Error> = failure.map { .failure($0) } ?? .success(bytes)
        result = outcome
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: outcome)
    }

    func cancel() {
        finish(CancellationError())
        lock.lock()
        let id = requestID
        lock.unlock()
        if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
}

enum MediaCompressor {
    static func prepare(id: String, options: CompressionOptions, network: Bool,
                        progress: @escaping @Sendable (Double?) -> Void) async throws -> CompressionDraft {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw CompressionError.changed
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard asset.mediaType == .image || asset.mediaType == .video,
              !asset.mediaSubtypes.contains(.photoLive), asset.burstIdentifier == nil,
              resources.count == 1, let resource = resources.first,
              resource.type == (asset.mediaType == .video ? .video : .photo) else { throw CompressionError.unsupported }
        if asset.mediaType == .image {
            guard let type = UTType(resource.uniformTypeIdentifier), !type.conforms(to: .rawImage),
                  [UTType.jpeg, .heic, .heif, .png, .tiff].contains(where: { type.conforms(to: $0) }) else {
                throw CompressionError.unsupported
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("compression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: directory) } }
        let fileExtension = (resource.originalFilename as NSString).pathExtension
        let input = directory.appendingPathComponent("original").appendingPathExtension(fileExtension)
        let output = directory.appendingPathComponent(asset.mediaType == .video ? "compressed.mp4" : "compressed.jpg")
        let writer = try CompressionResourceWriter(url: input)
        progress(nil)
        let originalBytes = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                writer.attach(continuation)
                let request = PHAssetResourceRequestOptions()
                request.isNetworkAccessAllowed = network
                let requestID = PHAssetResourceManager.default().requestData(for: resource, options: request,
                    dataReceivedHandler: { writer.append($0) }, completionHandler: { writer.finish($0) })
                writer.setRequest(requestID)
            }
        }, onCancel: { writer.cancel() })
        try Task.checkCancellation()
        if asset.mediaType == .video {
            try await encodeVideo(input: input, output: output, size: options.videoSize, progress: progress)
        } else {
            let worker = Task.detached(priority: .userInitiated) {
                try encodeImage(input: input, output: output, options: options)
            }
            try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        }
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let outputBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard originalBytes > 0, outputBytes > 0, outputBytes < originalBytes else { throw CompressionError.notSmaller }
        try FileManager.default.removeItem(at: input)
        retained = true
        progress(1)
        return CompressionDraft(asset: asset, originalBytes: originalBytes, outputBytes: outputBytes,
                                outputURL: output, directory: directory)
    }

    static func encodeImage(input: URL, output: URL, options: CompressionOptions) throws {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1, let typeID = CGImageSourceGetType(source),
              let type = UTType(typeID as String), !type.conforms(to: .rawImage),
              [UTType.jpeg, .heic, .heif, .png, .tiff].contains(where: { type.conforms(to: $0) }) else {
            throw CompressionError.unsupported
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(3072, max(640, options.maxDimension))
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw CompressionError.encoding
        }
        try Task.checkCancellation()
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CompressionError.encoding
        }
        CGImageDestinationAddImage(destination, image,
            [kCGImageDestinationLossyCompressionQuality: min(0.95, max(0.3, options.quality))] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CompressionError.encoding }
        try Task.checkCancellation()
    }

    static func encodeVideo(input: URL, output: URL, size: CompressionVideoSize,
                            progress: @escaping @Sendable (Double?) -> Void) async throws {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: input)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: size.preset),
              exporter.supportedFileTypes.contains(.mp4) else { throw CompressionError.encoding }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = false
        let monitor = Task {
            while !Task.isCancelled {
                progress(Double(exporter.progress))
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
        defer { monitor.cancel() }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed: continuation.resume()
                    case .cancelled: continuation.resume(throwing: CancellationError())
                    default: continuation.resume(throwing: exporter.error ?? CompressionError.encoding)
                    }
                }
                if Task.isCancelled { exporter.cancelExport() }
            }
        }, onCancel: { exporter.cancelExport() })
    }

    // The caller prevents cancellation during this PhotoKit transaction.
    static func save(_ draft: CompressionDraft) async throws -> String? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { throw CompressionError.permission }
        guard let original = PHAsset.fetchAssets(withLocalIdentifiers: [draft.originalID], options: nil).firstObject,
              original.modificationDate == draft.originalModifiedAt else { throw CompressionError.changed }
        guard draft.outputBytes > 0, draft.outputBytes < draft.originalBytes else { throw CompressionError.notSmaller }
        var savedID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: draft.isVideo ? .video : .photo, fileURL: draft.outputURL, options: nil)
            request.creationDate = original.creationDate
            request.location = original.location
            request.isFavorite = false
            savedID = request.placeholderForCreatedAsset?.localIdentifier
        }
        return savedID
    }
}

@MainActor
final class CompressionModel: ObservableObject {
    @Published private(set) var draft: CompressionDraft?
    @Published private(set) var isPreparing = false
    @Published private(set) var isSaving = false
    @Published private(set) var didSave = false
    @Published private(set) var savedID: String?
    @Published private(set) var originalModifiedAt: Date?
    @Published private(set) var originalBytes: Int64?
    @Published private(set) var outputBytes: Int64?
    @Published private(set) var progress: Double?
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func prepare(id: String, options: CompressionOptions, network: Bool) {
        guard !isPreparing, !isSaving, !didSave else { return }
        discard()
        error = nil
        isPreparing = true
        let token = UUID()
        generation = token
        task = Task {
            defer { if generation == token { isPreparing = false; task = nil } }
            do {
                let prepared = try await MediaCompressor.prepare(id: id, options: options, network: network) { value in
                    Task { @MainActor [weak self] in
                        guard self?.generation == token, self?.isPreparing == true else { return }
                        self?.progress = value
                    }
                }
                guard !Task.isCancelled else { prepared.discard(); return }
                draft = prepared
                originalBytes = prepared.originalBytes
                outputBytes = prepared.outputBytes
                originalModifiedAt = prepared.originalModifiedAt
            } catch is CancellationError { return }
            catch { if generation == token { self.error = error.localizedDescription } }
        }
    }

    func save() async {
        guard let draft, !isPreparing, !isSaving, !didSave else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            savedID = try await MediaCompressor.save(draft)
            didSave = true
            draft.discard()
            self.draft = nil
        } catch { self.error = error.localizedDescription }
    }

    func cancel() {
        guard !isSaving else { return }
        task?.cancel()
    }

    func discard() {
        guard !isSaving, !didSave else { return }
        draft?.discard()
        draft = nil
        originalBytes = nil
        outputBytes = nil
        originalModifiedAt = nil
        progress = nil
    }

    func leave() { cancel(); discard() }
}
