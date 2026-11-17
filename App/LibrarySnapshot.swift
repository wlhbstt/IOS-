import PhotoCleanerCore

struct LibrarySnapshot: Sendable {
    let records: [MediaRecord]
    var analyzed = 0
    var unknownSize = 0
    var screenshots: [String] = []
    var quality: [String] = []
    var previews: [String: String] = [:]
    let categories: [(name: String, count: Int)]

    init(_ source: [MediaRecord]) {
        var display: [MediaRecord] = []
        display.reserveCapacity(source.count)
        var counts: [String: Int] = [:]
        for record in source {
            var compact = record
            compact.featurePrint = nil
            display.append(compact)
            if record.analysisState == .complete { analyzed += 1 }
            if record.originalBytes == nil { unknownSize += 1 }
            if record.isScreenshot { screenshots.append(record.id) }
            if record.tags.contains("疑似模糊") || record.tags.contains("疑似极暗") { quality.append(record.id) }
            for tag in Set(record.tags + record.customTags) {
                counts[tag, default: 0] += 1
                if previews[tag] == nil { previews[tag] = record.id }
            }
        }
        records = display
        categories = counts.map { (name: $0.key, count: $0.value) }.sorted {
            $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count
        }
    }
}
