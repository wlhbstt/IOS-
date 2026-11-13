import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class MediaCompressorTests: XCTestCase {
    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return try XCTUnwrap(context.makeImage())
    }

    func testJPEGDownsamplesLongEdgeAndPreservesInput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.png")
        let output = directory.appendingPathComponent("output.jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try image(width: 2400, height: 1200), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = try Data(contentsOf: input)
        var options = CompressionOptions()
        options.maxDimension = 640
        try MediaCompressor.encodeImage(input: input, output: output, options: options)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 640)
        XCTAssertEqual(decoded.height, 320)
        XCTAssertEqual(try XCTUnwrap(CGImageSourceGetType(source)) as String, UTType.jpeg.identifier)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testAnimationIsRejectedWithoutProducingOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("animated.gif")
        let output = directory.appendingPathComponent("output.jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(input as CFURL, UTType.gif.identifier as CFString, 2, nil))
        let frame = try image(width: 16, height: 16)
        CGImageDestinationAddImage(destination, frame, nil)
        CGImageDestinationAddImage(destination, frame, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertThrowsError(try MediaCompressor.encodeImage(input: input, output: output, options: CompressionOptions())) { error in
            guard case CompressionError.unsupported = error else { return XCTFail("Expected unsupported animation, received \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testVideoExportProducesPlayableBoundedMP4AndPreservesSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.mov")
        let output = directory.appendingPathComponent("compressed.mp4")
        try await makeVideo(at: input)
        let original = try Data(contentsOf: input)
        try await MediaCompressor.encodeVideo(input: input, output: output, size: .compact) { _ in }
        XCTAssertGreaterThan(try Data(contentsOf: output).count, 0)
        XCTAssertEqual(try Data(contentsOf: input), original)
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 1280)
        XCTAssertGreaterThan(min(size.width, size.height), 0)
        XCTAssertEqual(duration.seconds, 1, accuracy: 0.1)
    }

    func testAlreadyCancelledVideoExportDoesNotCreateAFile() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await MediaCompressor.encodeVideo(input: output, output: output, size: .compact) { _ in }
        }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeVideo(at url: URL) async throws {
        let width = 640, height = 360
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw CompressionError.encoding }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CompressionError.encoding }
        var finished = false
        defer { if !finished { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)
        let deadline = Date().addingTimeInterval(20)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, Date() < deadline else { throw writer.error ?? CompressionError.encoding }
                try await Task.sleep(for: .milliseconds(10))
            }
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer else { throw CompressionError.encoding }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for y in 0..<height {
                let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt32.self)
                for x in 0..<width { row[x] = 0xff000000 | UInt32((x + frame * 5) % 256) << 16 | UInt32(y % 256) << 8 | UInt32(frame * 10) }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)) else {
                throw writer.error ?? CompressionError.encoding
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CompressionError.encoding }
        finished = true
    }
}
