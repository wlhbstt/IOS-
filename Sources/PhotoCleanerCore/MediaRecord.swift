import Foundation

public enum MediaKind: String, Codable, Hashable, Sendable {
    case image, video
}

public enum AnalysisState: String, Codable, Hashable, Sendable {
    case pending, complete, unavailable, failed
}

public struct MediaRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var filename: String
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var kind: MediaKind
    public var isScreenshot: Bool
    public var isLivePhoto: Bool
    public var isFavorite: Bool
    public var isComplex: Bool
    public var width: Int
    public var height: Int
    public var duration: Double
    public var originalBytes: Int64?
    public var digest: String?
    public var perceptualHash: UInt64?
    public var featurePrint: Data?
    public var brightness: Double?
    public var sharpness: Double?
    public var tags: [String]
    public var customTags: [String]
    public var text: String
    public var analysisState: AnalysisState

    public init(
        id: String,
        filename: String = "",
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        kind: MediaKind = .image,
        isScreenshot: Bool = false,
        isLivePhoto: Bool = false,
        isFavorite: Bool = false,
        isComplex: Bool = false,
        width: Int = 0,
        height: Int = 0,
        duration: Double = 0,
        originalBytes: Int64? = nil,
        digest: String? = nil,
        perceptualHash: UInt64? = nil,
        featurePrint: Data? = nil,
        brightness: Double? = nil,
        sharpness: Double? = nil,
        tags: [String] = [],
        customTags: [String] = [],
        text: String = "",
        analysisState: AnalysisState = .pending
    ) {
        self.id = id
        self.filename = filename
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.kind = kind
        self.isScreenshot = isScreenshot
        self.isLivePhoto = isLivePhoto
        self.isFavorite = isFavorite
        self.isComplex = isComplex
        self.width = width
        self.height = height
        self.duration = duration
        self.originalBytes = originalBytes
        self.digest = digest
        self.perceptualHash = perceptualHash
        self.featurePrint = featurePrint
        self.brightness = brightness
        self.sharpness = sharpness
        self.tags = tags
        self.customTags = customTags
        self.text = text
        self.analysisState = analysisState
    }

    public func updatingMetadata(from metadata: MediaRecord) -> MediaRecord {
        guard id == metadata.id, modifiedAt == metadata.modifiedAt, createdAt == metadata.createdAt,
              filename == metadata.filename, width == metadata.width, height == metadata.height,
              kind == metadata.kind, isComplex == metadata.isComplex, isLivePhoto == metadata.isLivePhoto else {
            var fresh = metadata
            fresh.customTags = customTags
            return fresh
        }
        var refreshed = self
        refreshed.isFavorite = metadata.isFavorite
        return refreshed
    }
}

public enum ResourceByteCounts {
    public static func total(_ values: [Int64?]) -> Int64? {
        guard !values.isEmpty else { return nil }
        var result: Int64 = 0
        for value in values {
            guard let value, value >= 0 else { return nil }
            let addition = result.addingReportingOverflow(value)
            guard !addition.overflow else { return nil }
            result = addition.partialValue
        }
        return result
    }
}
