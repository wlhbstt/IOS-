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
    private var matchingTask: Task<Void, Never>?

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
        guard !isReloading, !isDeleting else { return }
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
                refreshed[metadata.id] = records[metadata.id]?.updatingMetadata(from: metadata) ?? metadata
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

    func scan(originals: Bool = false) {
        guard hasAccess, !isReloading, scanTask == nil, !isDeleting else { return }
        let epoch = UUID()
        scanEpoch = epoch
        let candidates = records.values.filter {
            originals ? $0.originalBytes == nil : ($0.kind == .image && $0.analysisState != .complete)
        }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.map(\.id)
        scanTotal = candidates.count
        processed = 0
        isScanning = true
        let network = allowCloudDownload
        scanTask = Task {
            var pendingWrites: [MediaRecord] = []
            var completed = 0
            var lastUpdate = Date()
            for id in candidates {
                guard !Task.isCancelled, self.scanEpoch == epoch, var record = self.records[id],
                      let asset = self.assetMap[id] else { break }
                if originals {
                    do {
                        let summary = try await self.photos.originalSummary(asset: asset, network: network)
                        record.originalBytes = summary.bytes
                        record.digest = record.isComplex || record.isLivePhoto ? nil : summary.digest
                    } catch is CancellationError { break }
                    catch {
                        record.originalBytes = nil
                        record.digest = nil
                    }
                }
                guard !Task.isCancelled, self.scanEpoch == epoch else { break }
                if !originals && record.kind == .image && record.analysisState != .complete {
                    do {
                        let edge: CGFloat = record.isScreenshot ? 1280 : 1024
                        let image = try await self.photos.image(id: id, size: CGSize(width: edge, height: edge), network: network)
                        record = try await self.analyzer.analyze(record, image: image)
                    } catch is CancellationError { break }
                    catch {
                        record.analysisState = .unavailable
                    }
                } else if originals && record.kind == .video {
                    record.analysisState = record.originalBytes == nil ? .unavailable : .complete
                }
                guard !Task.isCancelled, self.scanEpoch == epoch else { break }
                pendingWrites.append(record)
                record.featurePrint = nil
                self.records[id] = record
                completed += 1
                if pendingWrites.count >= 64 {
                    do { try await self.index.upsert(pendingWrites) }
                    catch { self.notice = LibraryNotice(message: "扫描结果保存失败：\(error.localizedDescription)"); break }
                    pendingWrites.removeAll(keepingCapacity: true)
                }
                guard self.scanEpoch == epoch else { return }
                if Date().timeIntervalSince(lastUpdate) >= 3 {
                    self.processed = completed
                    await self.publishSnapshot(rebuildGroups: false)
                    lastUpdate = Date()
                }
            }
            guard self.scanEpoch == epoch else { return }
            // Saving the last small batch also makes a deliberate pause resumable.
            if !pendingWrites.isEmpty {
                do { try await self.index.upsert(pendingWrites) }
                catch { self.notice = LibraryNotice(message: "扫描结果保存失败：\(error.localizedDescription)") }
            }
            guard self.scanEpoch == epoch else { return }
            self.isScanning = false
            self.scanTask = nil
            self.processed = completed
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

    private func publishSnapshot(rebuildGroups: Bool = true) async {
        publicationGeneration += 1
        let generation = publicationGeneration
        let current = Array(records.values)
        matchingTask?.cancel()
        snapshot = current.map { record in
            var display = record
            display.featurePrint = nil
            return display
        }
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
        guard rebuildGroups else { return }
        let worker = Task.detached(priority: .utility) { [similarFinder, index] in
            let exact = DuplicateFinder.exactGroups(current)
            let similar = try await similarFinder.groups(in: current, index: index)
            return (exact, similar)
        }
        matchingTask = Task {
            await withTaskCancellationHandler(operation: {
                guard let groups = try? await worker.value, !Task.isCancelled,
                      generation == self.publicationGeneration else { return }
                self.exactGroups = groups.0
                self.similarGroups = groups.1
            }, onCancel: { worker.cancel() })
        }
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
        await delete(ids: selectedIDs)
    }

    func delete(ids: Set<String>) async {
        guard !isDeleting, !isReloading, !ids.isEmpty else { return }
        let reviewedGroups = (exactGroups + similarGroups).filter { $0.memberIDs.contains(where: ids.contains) }
        let relevantIDs = ids.union(reviewedGroups.flatMap(\.memberIDs))
        let reviewedRecords = relevantIDs.compactMap { records[$0] }
        isDeleting = true
        defer { isDeleting = false }
        pause()
        scanEpoch = UUID()
        scanTask = nil
        isScanning = false
        matchingTask?.cancel()
        do {
            authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard hasAccess else { throw PhotoAccessError.missing }
            let current = await Task.detached(priority: .userInitiated) { [photos] in
                photos.metadata(ids: relevantIDs)
            }.value.map { metadata in records[metadata.id]?.updatingMetadata(from: metadata) ?? metadata }
            let protection = photos.protectedIDs(albumIDs: protectedAlbumIDs)
            try DeletionPolicy.validateUnchanged(selectedIDs: ids, reviewedRecords: reviewedRecords,
                currentRecords: current, groups: reviewedGroups)
            try DeletionPolicy.validate(selectedIDs: ids, records: current,
                protectedIDs: protection, groups: reviewedGroups)
            try await photos.delete(ids: ids)
            selectedIDs.subtract(ids)
            for id in ids { records.removeValue(forKey: id); assetMap.removeValue(forKey: id) }
            exactGroups.removeAll { $0.memberIDs.contains(where: ids.contains) }
            similarGroups.removeAll { $0.memberIDs.contains(where: ids.contains) }
            await publishSnapshot()
            do { try await index.retain(ids: Set(records.keys)) }
            catch { notice = LibraryNotice(message: "照片已删除，但本机索引更新失败，请刷新相册。") }
        } catch {
            let failure = error as NSError
            if failure.domain == PHPhotosErrorDomain && failure.code == PHPhotosError.Code.userCancelled.rawValue { return }
            notice = LibraryNotice(message: "删除未完成：\(error.localizedDescription)\n\(failure.domain) / \(failure.code)")
        }
    }
}
