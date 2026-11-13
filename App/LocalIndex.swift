import Foundation
import CryptoKit
import PhotoCleanerCore

actor LocalIndex {
    private struct Page: Codable {
        var version = 1
        var records: [String: MediaRecord] = [:]
    }

    private let directory: URL
    private var pages: [Int: Page] = [:]

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? base.appendingPathComponent("PhotoCleaner/Index", isDirectory: true)
    }

    func load() throws -> [String: MediaRecord] {
        try prepare()
        pages.removeAll()
        let decoder = JSONDecoder()
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            var page = try decoder.decode(Page.self, from: Data(contentsOf: url))
            guard page.version == 1, let bucket = Int(url.deletingPathExtension().lastPathComponent) else { continue }
            var migrated = false
            for id in Array(page.records.keys) {
                if let data = page.records[id]?.featurePrint {
                    try storeFeature(data, id: id)
                    page.records[id]?.featurePrint = nil
                    migrated = true
                }
            }
            pages[bucket] = page
            if migrated { try write([bucket]) }
        }
        return pages.values.reduce(into: [:]) { $0.merge($1.records, uniquingKeysWith: { _, new in new }) }
    }

    func upsert(_ records: [MediaRecord]) throws {
        var changed = Set<Int>()
        try prepare()
        for record in records {
            let bucket = shard(record.id)
            var compact = record
            if let data = compact.featurePrint { try storeFeature(data, id: record.id) }
            compact.featurePrint = nil
            pages[bucket, default: Page()].records[record.id] = compact
            changed.insert(bucket)
        }
        try write(changed)
    }

    func retain(ids: Set<String>) throws {
        var changed = Set<Int>()
        for bucket in Array(pages.keys) {
            for id in pages[bucket]!.records.keys where !ids.contains(id) {
                let url = featureURL(id)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            let filtered = pages[bucket]!.records.filter { ids.contains($0.key) }
            if filtered.count != pages[bucket]!.records.count {
                pages[bucket]!.records = filtered
                changed.insert(bucket)
            }
        }
        try write(changed)
    }

    func remove(ids: Set<String>) throws {
        var changed = Set<Int>()
        for id in ids {
            let bucket = shard(id)
            if pages[bucket]?.records.removeValue(forKey: id) != nil { changed.insert(bucket) }
            let url = featureURL(id)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        if !changed.isEmpty { try write(changed) }
    }

    func clear() throws {
        pages.removeAll()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try prepare()
    }

    func featurePrint(id: String) -> Data? {
        try? Data(contentsOf: featureURL(id))
    }

    private func featureURL(_ id: String) -> URL {
        let name = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("features", isDirectory: true).appendingPathComponent(name)
    }

    private func storeFeature(_ data: Data, id: String) throws {
        try data.write(to: featureURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func shard(_ id: String) -> Int {
        Int(id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 } % 128)
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("features", isDirectory: true),
            withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        for folder in [directory, directory.appendingPathComponent("features", isDirectory: true)] {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
        }
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
            try encoder.encode(pages[bucket]!).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
