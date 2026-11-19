import CoreImage
import ImageIO
import PhotoCleanerCore
import UIKit
import Vision

enum FilterGroup: String, CaseIterable, Identifiable {
    case everyday = "日常", portrait = "人像", food = "美食", classic = "经典", scenery = "风景", night = "夜景"
    case street = "街拍", airy = "清透", film = "胶片", cinema = "电影", mono = "黑白"
    var id: Self { self }
}

enum EditFilter: String, CaseIterable, Codable, Identifiable, Sendable {
    case original, natural, warm, cool, soft, vivid
    case portrait, peach, ivory, glow, blush
    case forest, ocean, sunset, alpine, autumn
    case film, faded, slide, print, sepia
    case cinema, amber, night, noirBlue, mute
    case mono, silver, graphite, matte, highKey
    case foodWarm, foodFresh, coffee, dessert, banquet, market, tea, grilled
    case neon, blueHour, cityLights, tungsten, moonlight, dusk, nightRain, candle
    case urban, concrete, brick, crosswalk, afterRain, metro, newsprint, streetGold
    case airyWhite, mist, sakura, seaGlass, creamSky, linen, spring, sugar
    case classicChrome, classicFade, classicInstant, classicMono, classicNoir, classicProcess, classicTonal, classicTransfer

    var id: Self { self }

    static func options(in group: FilterGroup) -> [Self] {
        [.original] + allCases.filter { $0 != .original && $0.look.group == group }
    }

    var systemEffect: String? {
        switch self {
        case .classicChrome: return "CIPhotoEffectChrome"
        case .classicFade: return "CIPhotoEffectFade"
        case .classicInstant: return "CIPhotoEffectInstant"
        case .classicMono: return "CIPhotoEffectMono"
        case .classicNoir: return "CIPhotoEffectNoir"
        case .classicProcess: return "CIPhotoEffectProcess"
        case .classicTonal: return "CIPhotoEffectTonal"
        case .classicTransfer: return "CIPhotoEffectTransfer"
        default: return nil
        }
    }

    // Saturation delta, exposure EV, color temperature shift, contrast delta, sepia.
    typealias Look = (title: String, group: FilterGroup, saturation: Float, exposure: Float,
                      tint: Double, contrast: Double, sepia: Double)

    var look: Look {
        switch self {
        case .original: return ("原图", .everyday, 0, 0, 0, 0, 0)
        case .natural: return ("自然", .everyday, 0.18, 0.10, 0, 0.04, 0)
        case .warm: return ("暖调", .everyday, 0.11, 0.08, -850, 0, 0)
        case .cool: return ("冷调", .everyday, -0.10, -0.06, 850, 0, 0)
        case .soft: return ("柔光", .everyday, -0.12, 0.22, -160, -0.18, 0)
        case .vivid: return ("鲜艳", .everyday, 0.38, 0.06, 80, 0.13, 0)
        case .portrait: return ("自然肤色", .portrait, 0.04, 0.18, -300, -0.08, 0)
        case .peach: return ("蜜桃", .portrait, 0.17, 0.14, -730, -0.10, 0.07)
        case .ivory: return ("奶油", .portrait, -0.25, 0.28, -440, -0.15, 0.15)
        case .glow: return ("通透", .portrait, 0.03, 0.33, 290, 0.08, 0)
        case .blush: return ("柔暖", .portrait, -0.07, 0.11, -1050, -0.12, 0.10)
        case .forest: return ("森林", .scenery, 0.30, -0.15, 310, 0.12, 0)
        case .ocean: return ("海岸", .scenery, 0.22, 0.12, 1140, 0.06, 0)
        case .sunset: return ("日落", .scenery, 0.32, -0.08, -1490, 0.12, 0.04)
        case .alpine: return ("雪山", .scenery, -0.09, 0.27, 1130, 0.12, 0)
        case .autumn: return ("秋日", .scenery, 0.12, -0.04, -1020, 0.11, 0.23)
        case .film: return ("复古胶片", .film, -0.27, 0.04, -210, -0.11, 0.33)
        case .faded: return ("褪色", .film, -0.36, 0.11, 0, -0.30, 0.12)
        case .slide: return ("反转片", .film, 0.26, -0.10, 200, 0.30, 0)
        case .print: return ("老相纸", .film, -0.15, 0.02, -800, 0.19, 0.39)
        case .sepia: return ("棕褐", .film, -0.48, 0, -390, 0.09, 0.83)
        case .cinema: return ("冷暖电影", .cinema, -0.16, -0.10, 460, 0.25, 0.12)
        case .amber: return ("琥珀", .cinema, 0.09, -0.17, -1680, 0.28, 0.14)
        case .night: return ("蓝夜", .cinema, -0.20, -0.42, 1770, 0.17, 0)
        case .noirBlue: return ("冷灰", .cinema, -0.63, -0.12, 1280, 0.30, 0)
        case .mute: return ("低饱和", .cinema, -0.55, 0.09, 140, -0.13, 0.07)
        case .mono: return ("标准黑白", .mono, -1, 0, 0, 0, 0)
        case .silver: return ("银盐", .mono, -1, -0.05, 0, 0.20, 0)
        case .graphite: return ("石墨", .mono, -1, -0.33, 0, 0.38, 0)
        case .matte: return ("哑光黑白", .mono, -1, 0.03, 0, -0.22, 0)
        case .highKey: return ("高调黑白", .mono, -1, 0.36, 0, 0.15, 0)
        case .foodWarm: return ("暖桌", .food, 0.30, 0.14, -560, 0.14, 0)
        case .foodFresh: return ("鲜果", .food, 0.42, 0.19, 240, 0.08, 0)
        case .coffee: return ("咖啡馆", .food, -0.19, -0.09, -1020, 0.16, 0.32)
        case .dessert: return ("甜点", .food, 0.11, 0.31, -280, -0.18, 0.06)
        case .banquet: return ("晚餐", .food, 0.23, 0.29, 950, 0.12, 0)
        case .market: return ("市集", .food, 0.47, -0.06, -330, 0.24, 0)
        case .tea: return ("茶席", .food, -0.28, 0.25, 720, -0.10, 0.10)
        case .grilled: return ("炙烤", .food, 0.21, -0.19, -1380, 0.34, 0.13)
        case .neon: return ("霓虹", .night, 0.38, -0.16, 710, 0.37, 0)
        case .blueHour: return ("蓝调时刻", .night, 0.03, 0.24, 1580, 0.15, 0)
        case .cityLights: return ("城市灯火", .night, 0.25, 0.30, -460, 0.19, 0.04)
        case .tungsten: return ("灯光校色", .night, -0.16, 0.12, 2020, 0.22, 0)
        case .moonlight: return ("月光", .night, -0.78, 0.13, 1250, 0.08, 0)
        case .dusk: return ("暮色", .night, -0.25, -0.19, 520, 0.31, 0.21)
        case .nightRain: return ("雨夜", .night, -0.38, -0.06, 1480, -0.11, 0)
        case .candle: return ("烛光", .night, 0.07, 0.10, -1610, -0.07, 0.26)
        case .urban: return ("都市", .street, -0.23, -0.06, 450, 0.29, 0)
        case .concrete: return ("水泥灰", .street, -0.71, 0.18, 0, 0.10, 0)
        case .brick: return ("红砖", .street, 0.19, -0.13, -940, 0.25, 0.12)
        case .crosswalk: return ("斑马线", .street, -1, 0.08, 0, 0.46, 0)
        case .afterRain: return ("雨后", .street, 0.29, 0.11, 1020, 0.21, 0)
        case .metro: return ("地铁", .street, -0.42, -0.22, 940, 0.32, 0.08)
        case .newsprint: return ("报纸", .street, -1, 0.18, 0, -0.14, 0.35)
        case .streetGold: return ("午后街道", .street, 0.07, 0.26, -1190, 0.08, 0.17)
        case .airyWhite: return ("亮白", .airy, -0.24, 0.38, 160, -0.12, 0)
        case .mist: return ("薄雾", .airy, -0.39, 0.23, 930, -0.29, 0.05)
        case .sakura: return ("樱色", .airy, 0.13, 0.32, -620, -0.17, 0.12)
        case .seaGlass: return ("海玻璃", .airy, 0.17, 0.24, 1510, -0.18, 0)
        case .creamSky: return ("奶油天空", .airy, -0.10, 0.34, -790, -0.23, 0.21)
        case .linen: return ("亚麻", .airy, -0.43, 0.17, -340, -0.20, 0.29)
        case .spring: return ("春日", .airy, 0.28, 0.28, 430, -0.09, 0)
        case .sugar: return ("淡彩", .airy, 0.24, 0.16, -210, -0.33, 0.09)
        case .classicChrome: return ("浓彩", .classic, 0, 0, 0, 0, 0)
        case .classicFade: return ("淡褪", .classic, 0, 0, 0, 0, 0)
        case .classicInstant: return ("即时相片", .classic, 0, 0, 0, 0, 0)
        case .classicMono: return ("单色", .classic, 0, 0, 0, 0, 0)
        case .classicNoir: return ("黑色电影", .classic, 0, 0, 0, 0, 0)
        case .classicProcess: return ("交叉冲洗", .classic, 0, 0, 0, 0, 0)
        case .classicTonal: return ("灰阶", .classic, 0, 0, 0, 0, 0)
        case .classicTransfer: return ("转印", .classic, 0, 0, 0, 0, 0)
        }
    }
}

enum EditBackground: String, Codable, Sendable { case original, blur, cutout }

enum EditControl: String, CaseIterable {
    case exposure = "曝光", highlights = "高光", shadows = "阴影", saturation = "饱和度", warmth = "色温"
}

struct PhotoEdits: Codable, Equatable, Sendable {
    var filter = EditFilter.original
    var intensity = 0.8
    var enhancement: EditEnhancement?
    var enhancementStrength = 0.9
    var adjustments: [String: Double] = [:]
    var aspect = EditAspect.original
    var turns = 0
    var straighten = 0.0
    var background = EditBackground.original
    var blur = 0.5
    var subjects: [Int] = []

    var hasEffects: Bool {
        (filter != .original && intensity > 0) || (enhancement != nil && enhancementStrength > 0) ||
        adjustments.values.contains { $0 != 0 } || aspect != .original || turns != 0 || straighten != 0 ||
        background == .cutout || (background == .blur && blur > 0)
    }
}

// Rendering contexts are thread-safe. Mutable filters belong to one invocation.
final class PhotoEditRenderer: @unchecked Sendable {
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func enhance(_ input: CIImage) throws -> EditEnhancement {
        let small = input.fitted(longEdge: 512)
        let faces = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(ciImage: small).perform([faces])
        let region: CGRect
        if let face = faces.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            let box = face.boundingBox
            region = CGRect(x: box.minX * small.extent.width, y: box.minY * small.extent.height,
                            width: box.width * small.extent.width, height: box.height * small.extent.height)
        } else {
            region = small.extent
        }
        let average = small.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: region)])
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            ci.render(average, toBitmap: address, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8, colorSpace: colorSpace)
        }
        let brightness = (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
        return .suggest(brightness: brightness, portrait: !(faces.results ?? []).isEmpty)
    }

    func subjects(in image: CIImage) throws -> EditSubjects {
        let input = image.fitted(longEdge: 1024)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: input)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw PhotoEditError.noSubject }
        return EditSubjects(observation: result, handler: handler)
    }

    func raster(_ input: CIImage) throws -> CGImage {
        guard let output = ci.createCGImage(input, from: input.extent) else { throw PhotoEditError.render }
        return output
    }

    func write(_ input: CIImage, to url: URL, transparent: Bool) throws {
        if transparent {
            try ci.writePNGRepresentation(of: input, to: url, format: .RGBA8, colorSpace: colorSpace)
        } else {
            try ci.writeJPEGRepresentation(of: input, to: url, colorSpace: colorSpace)
        }
    }

    func apply(_ edits: PhotoEdits, to input: CIImage, mask: CIImage? = nil, transparent: Bool = false) throws -> CIImage {
        let bounds = input.extent
        let auto = edits.enhancement?.at(strength: edits.enhancementStrength) ?? .init()
        func amount(_ control: EditControl) -> Double { edits.adjustments[control.rawValue, default: 0] }
        var result = input
        if auto.exposure + amount(.exposure) != 0 {
            result = result.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: auto.exposure + amount(.exposure)])
        }
        if auto.shadows + amount(.shadows) != 0 || auto.highlights + amount(.highlights) != 0 {
            result = result.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputShadowAmount": auto.shadows + amount(.shadows),
                "inputHighlightAmount": max(0, min(1, 1 + auto.highlights + amount(.highlights)))
            ])
        }
        if auto.saturation + amount(.saturation) != 0 {
            result = result.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + auto.saturation + amount(.saturation)])
        }
        if amount(.warmth) != 0 {
            result = result.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 - amount(.warmth) * 2100, y: 0)
            ])
        }
        result = applyFilter(edits.filter, strength: edits.intensity, to: result)
        if edits.background != .original, let mask {
            let fit = mask.atOrigin().transformed(by: CGAffineTransform(scaleX: bounds.width / mask.extent.width,
                                                                       y: bounds.height / mask.extent.height))
                .transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
            let backdrop: CIImage
            if edits.background == .blur {
                backdrop = result.clampedToExtent().applyingGaussianBlur(sigma: edits.blur * min(bounds.width, bounds.height) * 0.035)
                    .cropped(to: bounds)
            } else {
                backdrop = CIImage(color: transparent ? .clear : .white).cropped(to: bounds)
            }
            result = result.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: backdrop, kCIInputMaskImageKey: fit])
                .cropped(to: bounds)
        }
        if edits.turns != 0 { result = result.oriented(forExifOrientation: [1, 6, 3, 8][edits.turns]) }
        if edits.straighten != 0 {
            result = result.applyingFilter("CIStraightenFilter", parameters: [kCIInputAngleKey: edits.straighten * .pi / 180])
        }
        let crop = edits.aspect.crop(in: result.extent)
        return result.cropped(to: crop.integral.intersection(result.extent)).atOrigin()
    }

    private func applyFilter(_ filter: EditFilter, strength: Double, to input: CIImage) -> CIImage {
        guard filter != .original, strength > 0 else { return input }
        if let effect = filter.systemEffect {
            let styled = input.applyingFilter(effect)
            return input.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: styled, kCIInputTimeKey: strength
            ]).cropped(to: input.extent)
        }
        let look = filter.look
        let saturationValue = 1 + Float(strength) * look.saturation
        let exposureValue = Float(strength) * look.exposure
        var result = input
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturationValue])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposureValue])
        if look.tint != 0 {
            result = result.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 + strength * look.tint, y: 0)
            ])
        }
        if look.contrast != 0 {
            result = result.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + strength * look.contrast])
        }
        if look.sepia != 0 { result = result.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: strength * look.sepia]) }
        return result.cropped(to: input.extent)
    }
}

final class EditSubjects: @unchecked Sendable {
    private let observation: VNInstanceMaskObservation
    private let handler: VNImageRequestHandler
    private let lock = NSLock()

    init(observation: VNInstanceMaskObservation, handler: VNImageRequestHandler) {
        self.observation = observation
        self.handler = handler
    }

    var indices: [Int] { Array(observation.allInstances) }

    func mask(for selection: [Int]) throws -> CIImage {
        lock.lock()
        defer { lock.unlock() }
        let ids = selection.isEmpty ? observation.allInstances : IndexSet(selection).intersection(observation.allInstances)
        guard !ids.isEmpty else { throw PhotoEditError.noSubject }
        return CIImage(cvPixelBuffer: try observation.generateScaledMaskForImage(forInstances: ids, from: handler))
    }
}

extension CIImage {
    func atOrigin() -> CIImage {
        transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    func fitted(longEdge: CGFloat) -> CIImage {
        let scale = min(1, longEdge / max(extent.width, extent.height))
        return atOrigin().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
