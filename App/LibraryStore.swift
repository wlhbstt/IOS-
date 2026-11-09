import Combine
import Photos
import SwiftUI
import PhotoCleanerCore

struct LibraryNotice: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var snapshot: [MediaRecord] = []
    @Published private(set) var snapshotRevision = 0
    @Published private(set) var exactGroups: [DuplicateGroup] = []
    @Published private(set) var similarGroups: [DuplicateGroup] = []
    @Published private(set) var categories: [(name: String, count: Int)] = []
    @Published private(set) var albums: [AlbumChoice] = []
    @Published private(set) var protectedIDs = Set<String>()
    @Published private(set) var isScanning = false
    @Published private(set) var isReloading = false
    @Published private(set) var isDeleting = false
    @Published private(set) var processed = 0
    @Published private(set) var scanTotal = 0
    @Published private(set) var analyzedCount = 0
    @Published private(set) var pendingCount = 0
    @Published private(set) var unknownSizeCount = 0
    @Published var selectedIDs = Set<String>()
    @Published var notice: LibraryNotice?
    @Published var allowCloudDownload: Bool {
        didSet {
            UserDefaults.standard.set(allowCloudDownload, forKey: "allowCloudDownload")
            if oldValue != allowCloudDownload { pause() }
        }
    }
    @Published private(set) var protectedAlbumIDs: Set<String>

    let photos = PhotoAccess()
    private let index = LocalIndex()
    private let analyzer = ImageAnalyzer()
    private let similarFinder = SimilarFinder()
    private let observer = LibraryChangeObserver()
    private var records: [String: MediaRecord] = [:]
    private var assetMap: [String: PHAsset] = [:]
    private var indexLoaded = false
    private var scanTask: Task<Void, Never>?
    private var scanEpoch = UUID()
    private var changeTask: Task<Void, Never>?
    private var publicationGeneration = 0
    private var matchingTask: Task<[DuplicateGroup], Error>?

    init() {
        allowCloudDownload = UserDefaults.standard.bool(forKey: "allowCloudDownload")
        protectedAlbumIDs = Set(UserDefaults.standard.stringArray(forKey: "protectedAlbumIDs") ?? [])
        observer.changed = { [weak self] in
            Task { @MainActor in
                guard let self, !self.isDeleting else { return }
                self.pause()
                self.changeTask?.cancel()
                self.changeTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await self.reload()
                }
            }
        }
        PHPhotoLibrary.shared().register(observer)
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(observer) }

    var hasAccess: Bool { authorization == .authorized || authorization == .limited }

    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await reload()
    }

    func reload() async {
        guard !isReloading else { return }
        isReloading = true
        defer { isReloading = false }
        let running = scanTask
        pause()
        await running?.value
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard hasAccess else {
            records.removeAll()
            assetMap.removeAll()
            selectedIDs.removeAll()
            protectedIDs.removeAll()
            albums = []
            try? await index.clear()
            indexLoaded = false
            await publishSnapshot()
            return
        }
        do {
            if !indexLoaded {
                records = try await index.load()
                indexLoaded = true
            }
            let catalogue = await Task.detached(priority: .userInitiated) { [photos] in
                photos.assets().map { ($0, photos.metadata($0)) }
            }.value
            guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == authorization else {
                isReloading = false
                await reload()
                return
            }
            var refreshed: [String: MediaRecord] = [:]
            for (_, metadata) in catalogue {
                if var cached = records[metadata.id], cached.modifiedAt == metadata.modifiedAt,
                   cached.width == metadata.width, cached.height == metadata.height,
                   cached.isComplex == metadata.isComplex, cached.filename == metadata.filename {
                    cached.createdAt = metadata.createdAt
                    cached.isFavorite = metadata.isFavorite
                    refreshed[metadata.id] = cached
                } else {
                    var fresh = metadata
                    fresh.customTags = records[metadata.id]?.customTags ?? []
                    refreshed[metadata.id] = fresh
                }
            }
            if !selectedIDs.isEmpty {
                do {
                    try DeletionPolicy.validateUnchanged(selectedIDs: selectedIDs, reviewedRecords: Array(records.values),
                        currentRecords: Array(refreshed.values), groups: exactGroups + similarGroups)
                } catch {
                    selectedIDs.removeAll()
                    notice = LibraryNotice(message: "照片或保留项已变化，待删选择已清空，请重新检查。")
                }
            }
            records = refreshed
            assetMap = Dictionary(uniqueKeysWithValues: catalogue.map { ($0.0.localIdentifier, $0.0) })
            albums = photos.albums()
            protectedIDs = photos.protectedIDs(albumIDs: protectedAlbumIDs)
            selectedIDs.formIntersection(Set(records.keys))
            selectedIDs.subtract(protectedIDs)
            selectedIDs = selectedIDs.filter { records[$0]?.isFavorite == false }
            try await index.retain(ids: Set(records.keys))
            await publishSnapshot()
        } catch {
            notice = LibraryNotice(message: "读取本机索引失败：\(error.localizedDescription)。可在设置中清除索引后重试。")
        }
    }

    func scan() {
        guard hasAccess, !isReloading, scanTask == nil, !isDeleting else { return }
        let epoch = UUID()
        scanEpoch = epoch
        let candidates = records.values.filter { $0.analysisState != .complete || $0.originalBytes == nil }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.map(\.id)
        scanTotal = candidates.count
        processed = 0
        isScanning = true
        let network = allowCloudDownload
        scanTask = Task {
            var pendingWrites: [MediaRecord] = []
            for id in candidates {
                guard !Task.isCancelled, self.scanEpoch == epoch, var record = self.records[id],
                      let asset = self.assetMap[id] else { break }
                do {
                    if record.originalBytes == nil {
                        let summary = try await self.photos.originalSummary(asset: asset, network: network)
                        record.originalBytes = summary.bytes
                        record.digest = record.isComplex || record.isLivePhoto ? nil : summary.digest
                    }
                } catch is CancellationError { break }
                catch {
                    record.originalBytes = nil
                    record.digest = nil
                }
                guard !Task.isCancelled, self.scanEpoch == epoch else { break }
                if record.kind == .image && record.analysisState != .complete {
                    do {
                        let image = try await self.photos.image(id: id, size: CGSize(width: 1280, height: 1280), network: network)
                        record = try await self.analyzer.analyze(record, image: image)
                    } catch is CancellationError { break }
                    catch {
                        record.analysisState = .unavailable
                    }
                } else if record.kind == .video {
                    record.analysisState = record.originalBytes == nil ? .unavailable : .complete
                }
                guard !Task.isCancelled, self.scanEpoch == epoch else { break }
                self.records[id] = record
                pendingWrites.append(record)
                self.processed += 1
                if pendingWrites.count >= 24 {
                    do { try await self.index.upsert(pendingWrites) }
                    catch { self.notice = LibraryNotice(message: "扫描结果保存失败：\(error.localizedDescription)"); break }
                    pendingWrites.removeAll(keepingCapacity: true)
                }
            }
            // Saving the last small batch also makes a deliberate pause resumable.
            if !pendingWrites.isEmpty {
                do { try await self.index.upsert(pendingWrites) }
                catch { self.notice = LibraryNotice(message: "扫描结果保存失败：\(error.localizedDescription)") }
            }
            guard self.scanEpoch == epoch else { return }
            self.isScanning = false
            self.scanTask = nil
            await self.publishSnapshot()
        }
    }

    func pause() {
        scanTask?.cancel()
    }

    func refreshResults() async {
        guard !isReloading else { return }
        await publishSnapshot()
    }

    private func publishSnapshot() async {
        publicationGeneration += 1
        let generation = publicationGeneration
        let current = Array(records.values)
        let exact = DuplicateFinder.exactGroups(current)
        matchingTask?.cancel()
        let worker = Task.detached(priority: .utility) { [similarFinder] in
            try await similarFinder.groups(in: current)
        }
        matchingTask = worker
        let similar: [DuplicateGroup]
        do { similar = try await worker.value }
        catch { return }
        guard generation == publicationGeneration else { return }
        matchingTask = nil
        exactGroups = exact
        similarGroups = similar
        snapshot = current
        analyzedCount = current.filter { $0.analysisState == .complete }.count
        pendingCount = current.count - analyzedCount
        unknownSizeCount = current.filter { $0.originalBytes == nil }.count
        var counts: [String: Int] = [:]
        for record in current {
            for tag in Set(record.tags + record.customTags) { counts[tag, default: 0] += 1 }
        }
        categories = counts.map { (name: $0.key, count: $0.value) }.sorted {
            $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count
        }
        snapshotRevision += 1
    }

    func record(_ id: String) -> MediaRecord? { records[id] }

    func isProtected(_ id: String) -> Bool { records[id]?.isFavorite == true || protectedIDs.contains(id) }

    func toggleSelection(_ id: String) {
        guard !isDeleting else { return }
        if selectedIDs.contains(id) { selectedIDs.remove(id); return }
        let proposed = selectedIDs.union([id])
        do {
            try DeletionPolicy.validate(selectedIDs: proposed, records: Array(records.values),
                protectedIDs: protectedIDs, groups: exactGroups + similarGroups)
            selectedIDs = proposed
        } catch { notice = LibraryNotice(message: error.localizedDescription) }
    }

    func selectRecommended(_ group: DuplicateGroup) {
        selectRecommended([group])
    }

    func selectRecommended(_ groups: [DuplicateGroup]) {
        guard !isDeleting else { return }
        var proposed = selectedIDs
        let keepIDs = Set(groups.map(\.suggestedKeepID))
        proposed.subtract(keepIDs)
        for id in Set(groups.flatMap(\.memberIDs)).subtracting(keepIDs) where !isProtected(id) {
            guard let record = records[id], !record.isComplex, !record.isLivePhoto else { continue }
            proposed.insert(id)
        }
        applyBatchSelection(proposed)
    }

    func selectVisible(_ ids: Set<String>) {
        guard !isDeleting else { return }
        applyBatchSelection(selectedIDs.union(ids.filter { records[$0] != nil && !isProtected($0) }))
    }

    private func applyBatchSelection(_ candidate: Set<String>) {
        var proposed = candidate
        let existing = Set(records.keys)
        for group in exactGroups + similarGroups {
            let members = Set(group.memberIDs).intersection(existing)
            if !members.isEmpty && members.isSubset(of: proposed) { proposed.remove(group.suggestedKeepID) }
        }
        guard !proposed.isEmpty else { return }
        do {
            try DeletionPolicy.validate(selectedIDs: proposed, records: Array(records.values),
                protectedIDs: protectedIDs, groups: exactGroups + similarGroups)
            selectedIDs = proposed
        } catch { notice = LibraryNotice(message: error.localizedDescription) }
    }

    func setProtected(album: String, enabled: Bool) async {
        pause()
        if enabled { protectedAlbumIDs.insert(album) } else { protectedAlbumIDs.remove(album) }
        UserDefaults.standard.set(Array(protectedAlbumIDs), forKey: "protectedAlbumIDs")
        protectedIDs = photos.protectedIDs(albumIDs: protectedAlbumIDs)
        selectedIDs.subtract(protectedIDs)
    }

    func saveTags(id: String, text: String) async {
        guard var record = records[id], !isScanning else { return }
        record.customTags = Array(Set(text.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        record.tags = []
        records[id] = record
        do { try await index.upsert([record]); await publishSnapshot() }
        catch { notice = LibraryNotice(message: "保存标签失败：\(error.localizedDescription)") }
    }

    func clearIndex() async {
        let task = scanTask
        pause()
        await task?.value
        scanEpoch = UUID()
        do {
            try await index.clear()
            indexLoaded = false
            records.removeAll()
            selectedIDs.removeAll()
            await reload()
        } catch { notice = LibraryNotice(message: "清除索引失败：\(error.localizedDescription)") }
    }

    func deleteSelected() async {
        guard !isDeleting, !selectedIDs.isEmpty else { return }
        let ids = selectedIDs
        let reviewedGroups = exactGroups + similarGroups
        let reviewedRecords = Array(records.values)
        isDeleting = true
        defer { isDeleting = false }
        let task = scanTask
        pause()
        await task?.value
        while isReloading { await Task.yield() }
        await reload()
        do {
            guard hasAccess else { throw PhotoAccessError.missing }
            try DeletionPolicy.validateUnchanged(selectedIDs: ids, reviewedRecords: reviewedRecords,
                currentRecords: Array(records.values), groups: reviewedGroups)
            try DeletionPolicy.validate(selectedIDs: ids, records: Array(records.values),
                protectedIDs: protectedIDs, groups: reviewedGroups + exactGroups + similarGroups)
            try await photos.delete(ids: ids)
            selectedIDs.subtract(ids)
            await reload()
            notice = LibraryNotice(message: "已删除 \(ids.count) 个项目，可在系统相册的最近删除中检查或恢复。")
        } catch { notice = LibraryNotice(message: "删除未完成：\(error.localizedDescription)") }
    }
}
