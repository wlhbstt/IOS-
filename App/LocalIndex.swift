import Foundation
import PhotoCleanerCore

actor LocalIndex {
    private struct Page: Codable {
        var version = 1
        var records: [String: MediaRecord] = [:]
    }

    private let directory: URL
    private var pages: [Int: Page] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("PhotoCleaner/Index", isDirectory: true)
    }

    func load() throws -> [String: MediaRecord] {
        try prepare()
        pages.removeAll()
        let decoder = JSONDecoder()
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            let page = try decoder.decode(Page.self, from: Data(contentsOf: url))
            guard page.version == 1, let bucket = Int(url.deletingPathExtension().lastPathComponent) else { continue }
            pages[bucket] = page
        }
        return pages.values.reduce(into: [:]) { $0.merge($1.records, uniquingKeysWith: { _, new in new }) }
    }

    func upsert(_ records: [MediaRecord]) throws {
        var changed = Set<Int>()
        for record in records {
            let bucket = shard(record.id)
            pages[bucket, default: Page()].records[record.id] = record
            changed.insert(bucket)
        }
        try write(changed)
    }

    func retain(ids: Set<String>) throws {
        var changed = Set<Int>()
        for bucket in Array(pages.keys) {
            let filtered = pages[bucket]!.records.filter { ids.contains($0.key) }
            if filtered.count != pages[bucket]!.records.count {
                pages[bucket]!.records = filtered
                changed.insert(bucket)
            }
        }
        try write(changed)
    }

    func clear() throws {
        pages.removeAll()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try prepare()
    }

    private func shard(_ id: String) -> Int {
        Int(id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 } % 128)
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func write(_ buckets: Set<Int>) throws {
        try prepare()
        let encoder = JSONEncoder()
        for bucket in buckets {
            let url = directory.appendingPathComponent("\(bucket).json")
            try encoder.encode(pages[bucket]!).write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}
