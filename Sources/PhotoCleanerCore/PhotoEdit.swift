import Foundation

public enum EditAspect: String, Codable, CaseIterable, Sendable {
    case original, square, landscape, portrait

    public func crop(in bounds: CGRect) -> CGRect {
        let ratio: CGFloat
        switch self {
        case .original: return bounds
        case .square: ratio = 1
        case .landscape: ratio = 4 / 3
        case .portrait: ratio = 3 / 4
        }
        let width = min(bounds.width, bounds.height * ratio)
        let height = width / ratio
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }
}

public struct EditEnhancement: Codable, Equatable, Sendable {
    public var exposure = 0.0
    public var shadows = 0.0
    public var highlights = 0.0
    public var saturation = 0.0

    public init() {}

    public static func suggest(brightness: Double, portrait: Bool) -> Self {
        let dark = max(0, 0.52 - brightness)
        var result = Self()
        result.exposure = min(0.65, dark * (portrait ? 1.7 : 1.3))
        result.shadows = min(0.8, dark * (portrait ? 1.9 : 1.35))
        result.highlights = -min(0.25, max(0, brightness - 0.60) * 0.8)
        result.saturation = portrait ? 0.015 : 0.08
        return result
    }

    public func at(strength: Double) -> Self {
        let amount = min(1, max(0, strength))
        var result = Self()
        result.exposure = exposure * amount
        result.shadows = shadows * amount
        result.highlights = highlights * amount
        result.saturation = saturation * amount
        return result
    }
}
