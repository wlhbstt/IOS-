import ImageIO
import UIKit
import Vision
import PhotoCleanerCore

actor ImageAnalyzer {
    func analyze(_ source: MediaRecord, image: UIImage) throws -> MediaRecord {
        try autoreleasepool { try analyzeImage(source, image: image) }
    }

    private func analyzeImage(_ source: MediaRecord, image: UIImage) throws -> MediaRecord {
        try Task.checkCancellation()
        guard let cgImage = image.cgImage else { throw PhotoAccessError.unavailable }
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.recognitionLanguages = ["zh-Hans", "en-US"]
        let classification = VNClassifyImageRequest()
        let feature = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.imageOrientation.cgOrientation)
        if source.isScreenshot { try handler.perform([text]) }
        else { try handler.perform([text, classification, feature]) }
        try Task.checkCancellation()

        var record = source
        record.text = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        var tags = source.isScreenshot ? ["截图"] : []
        if source.isLivePhoto { tags.append("实况照片") }
        tags += ScreenshotRules.tags(for: record.text)
        if ScreenshotRules.isSensitive(text: record.text) { tags.append("重要资料") }
        for observation in (classification.results ?? []).prefix(5) where observation.confidence >= 0.45 {
            if let tag = Self.category(observation.identifier) { tags.append(tag) }
        }
        if let observation = feature.results?.first {
            record.featurePrint = try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
        }
        if let small = Self.gray(cgImage, width: 9, height: 8) {
            var hash: UInt64 = 0
            for y in 0..<8 {
                for x in 0..<8 {
                    hash = (hash << 1) | (small[y * 9 + x] > small[y * 9 + x + 1] ? 1 : 0)
                }
            }
            record.perceptualHash = hash
        }
        if let pixels = Self.gray(cgImage, width: 192, height: 192) {
            record.brightness = pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count) / 255
            var sum = 0.0, squared = 0.0
            for y in 1..<191 {
                for x in 1..<191 {
                    let p = y * 192 + x
                    let laplacian = Double(Int(pixels[p - 1]) + Int(pixels[p + 1]) +
                        Int(pixels[p - 192]) + Int(pixels[p + 192]) - 4 * Int(pixels[p]))
                    sum += laplacian
                    squared += laplacian * laplacian
                }
            }
            let count = 190.0 * 190.0
            record.sharpness = max(0, squared / count - pow(sum / count, 2))
            if !source.isScreenshot && !ScreenshotRules.isSensitive(text: record.text) {
                if (record.brightness ?? 1) < 0.035 { tags.append("疑似极暗") }
                else if (record.sharpness ?? 100) < 12 { tags.append("疑似模糊") }
            }
        }
        record.tags = Array(Set(tags)).sorted()
        record.analysisState = .complete
        return record
    }

    private static func category(_ identifier: String) -> String? {
        let label = identifier.lowercased()
        let mappings: [(String, [String])] = [
            ("人物", ["person", "people", "portrait", "selfie", "human", "wedding"]),
            ("美食", ["food", "meal", "dish", "cuisine", "dessert", "drink", "fruit"]),
            ("风景", ["landscape", "mountain", "beach", "coast", "forest", "sunset", "lake", "sky"]),
            ("车辆", ["car", "vehicle", "truck", "motorcycle", "bicycle", "automobile"]),
            ("建筑", ["building", "architecture", "bridge", "tower", "house"]),
            ("植物", ["plant", "flower", "garden"]),
            ("文档", ["document", "receipt", "printed_text"])
        ]
        return mappings.first { _, keywords in keywords.contains { label.split(separator: "_").contains(Substring($0)) || label == $0 } }?.0
    }

    private static func gray(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}

private extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

actor SimilarFinder {
    func groups(in records: [MediaRecord], index: LocalIndex) async throws -> [DuplicateGroup] {
        let eligible = records.filter {
            $0.kind == .image && !$0.isScreenshot && !$0.isLivePhoto && !$0.isComplex && $0.createdAt != nil &&
            $0.perceptualHash != nil
        }.sorted { ($0.createdAt!, $0.id) < ($1.createdAt!, $1.id) }
        var groups: [[MediaRecord]] = []
        var membership: [String: Int] = [:]
        var observations: [String: VNFeaturePrintObservation] = [:]

        func observation(_ record: MediaRecord) async -> VNFeaturePrintObservation? {
            if let cached = observations[record.id] { return cached }
            let stored = await index.featurePrint(id: record.id)
            guard let data = stored,
                  let value = autoreleasepool(invoking: {
                      try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
                  })
            else { return nil }
            if observations.count >= 32 { observations.removeAll(keepingCapacity: true) }
            observations[record.id] = value
            return value
        }

        func matches(_ lhs: MediaRecord, _ rhs: MediaRecord) async -> Bool {
            if let digest = lhs.digest, digest == rhs.digest { return false }
            guard let a = lhs.perceptualHash, let b = rhs.perceptualHash,
                  (a ^ b).nonzeroBitCount <= 8,
                  abs(Double(lhs.width) / Double(max(lhs.height, 1)) - Double(rhs.width) / Double(max(rhs.height, 1))) < 0.08,
                  let first = await observation(lhs), let second = await observation(rhs) else { return false }
            var distance: Float = 0
            do { try first.computeDistance(&distance, to: second) }
            catch { return false }
            return distance < 0.30
        }

        for (position, record) in eligible.enumerated() {
            try Task.checkCancellation()
            for previousIndex in stride(from: position - 1, through: max(0, position - 20), by: -1) where previousIndex >= 0 {
                let previous = eligible[previousIndex]
                guard record.createdAt!.timeIntervalSince(previous.createdAt!) <= 10 else { break }
                let groupIndex = membership[previous.id]
                let representative = groupIndex.map { groups[$0][0] } ?? previous
                guard await matches(record, representative) else { continue }
                if let groupIndex {
                    groups[groupIndex].append(record)
                    membership[record.id] = groupIndex
                } else {
                    membership[previous.id] = groups.count
                    membership[record.id] = groups.count
                    groups.append([previous, record])
                }
                break
            }
            if position > 20 { observations.removeValue(forKey: eligible[position - 21].id) }
        }
        return groups.map { members in
            let keep = members.sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                if $0.sharpness != $1.sharpness { return ($0.sharpness ?? 0) > ($1.sharpness ?? 0) }
                return $0.id < $1.id
            }[0]
            return DuplicateGroup(id: "similar:\(members[0].id)", memberIDs: members.map(\.id), suggestedKeepID: keep.id)
        }
    }
}
