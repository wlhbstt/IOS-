import SwiftUI
import PhotoCleanerCore

private struct OrganizeCollection: Identifiable, Sendable {
    let scope: ReviewScope
    let title: String
    let symbol: String
    let ids: [String]
    var id: String { scope.rawValue }

    static func grouped(_ records: [MediaRecord]) -> [OrganizeCollection] {
        let types: [(ReviewScope, String, String)] = [
            (.all, "全部项目", "photo.on.rectangle"), (.photos, "照片", "photo"),
            (.videos, "视频", "video"), (.screenshots, "截图", "viewfinder.rectangular"),
            (.livePhotos, "实况照片", "livephoto"), (.favorites, "收藏", "heart.fill")
        ]
        return types.map { scope, title, symbol in
            OrganizeCollection(scope: scope, title: title, symbol: symbol,
                ids: records.filter { scope.matches($0) }.map(\.id))
        }
    }
}

private struct OrganizeSnapshot: Sendable {
    var collections: [OrganizeCollection] = []
    var months: [ReviewMonth] = []
    var ids: [String] = []

    static func make(_ records: [MediaRecord]) -> OrganizeSnapshot {
        let sorted = MediaSorter.sorted(records, by: .newest)
        guard !Task.isCancelled else { return OrganizeSnapshot() }
        return OrganizeSnapshot(collections: OrganizeCollection.grouped(sorted),
            months: ReviewMonth.group(sorted), ids: sorted.map(\.id))
    }
}

private struct OrganizeReviewLaunch: Identifiable {
    let id = UUID()
    let title: String
    let ids: [String]
}

struct OrganizeView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var summary = OrganizeSnapshot()
    @State private var launch: OrganizeReviewLaunch?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(library.snapshot.count.formatted())
                            .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                            .accessibilityIdentifier("organize.count")
                            .accessibilityValue(String(library.snapshot.count))
                        Text("个项目").foregroundStyle(.secondary)
                        Spacer()
                        if library.authorization == .limited {
                            Image(systemName: "lock.shield").foregroundStyle(.secondary)
                                .accessibilityLabel("部分照片访问")
                        }
                    }
                    if !summary.ids.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(summary.ids.prefix(3)), id: \.self) { id in
                                PhotoThumbnail(id: id).frame(maxWidth: .infinity).frame(height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }.accessibilityHidden(true)
                    }
                    Button {
                        launch = OrganizeReviewLaunch(title: "全部项目", ids: summary.ids)
                    } label: {
                        HStack {
                            Label("开始整理", systemImage: "rectangle.portrait.on.rectangle.portrait")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline).padding(16).frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Color(uiColor: .systemBackground))
                    .background(LibraryStyle.accent, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(summary.ids.isEmpty || library.isReloading)
                    .accessibilityIdentifier("review.start")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("媒体类型").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(summary.collections) { collection in
                            NavigationLink {
                                RecordBrowser(title: collection.title, sourceIDs: Set(collection.ids))
                            } label: {
                                OrganizeCollectionTile(collection: collection)
                            }
                            .accessibilityIdentifier("organize.scope.\(collection.id)")
                        }
                    }.buttonStyle(.plain)
                }
                VStack(spacing: 0) {
                    NavigationLink { AlbumsOrganizeView() } label: {
                        OrganizeDestinationRow(title: "相簿", symbol: "rectangle.stack", color: .blue)
                    }.accessibilityIdentifier("organize.albums")
                    Divider()
                    NavigationLink { TimeOrganizeView() } label: {
                        OrganizeDestinationRow(title: "时间", symbol: "calendar", color: .orange)
                    }.accessibilityIdentifier("organize.time")
                    Divider()
                    NavigationLink { PlacesOrganizeView() } label: {
                        OrganizeDestinationRow(title: "地点", symbol: "mappin.and.ellipse", color: .teal)
                    }.accessibilityIdentifier("organize.places")
                }.buttonStyle(.plain)
                if !summary.months.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("最近月份").font(.headline)
                            Spacer()
                            NavigationLink { TimeOrganizeView() } label: {
                                Image(systemName: "arrow.right").frame(width: 44, height: 44)
                            }.accessibilityLabel("全部月份")
                        }
                        ForEach(Array(summary.months.prefix(3))) { month in
                            NavigationLink {
                                RecordBrowser(title: organizeMonthTitle(month), sourceIDs: Set(month.ids))
                            } label: {
                                OrganizeMediaRow(title: organizeMonthTitle(month), ids: month.ids, symbol: "calendar")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if library.snapshot.isEmpty && !library.isReloading {
                    ContentUnavailableView("没有可整理的项目", systemImage: "photo.on.rectangle")
                }
            }.padding(20)
        }
        .navigationTitle("整理")
        .modifier(LibraryControls())
        .task(id: library.snapshotRevision) {
            let records = library.snapshot
            let task = Task.detached(priority: .userInitiated) { OrganizeSnapshot.make(records) }
            let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            summary = result
        }
        .fullScreenCover(item: $launch) { launch in
            NavigationStack { SwipeReviewView(title: launch.title, ids: launch.ids) }
        }
    }
}

private struct OrganizeCollectionTile: View {
    let collection: OrganizeCollection

    private var color: Color {
        switch collection.scope {
        case .favorites: return .pink
        case .videos: return .orange
        case .livePhotos: return .teal
        case .screenshots: return .indigo
        case .all, .photos: return LibraryStyle.accent
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let id = collection.ids.first { PhotoThumbnail(id: id) }
                else {
                    Rectangle().fill(color.opacity(0.10))
                        .overlay { Image(systemName: collection.symbol).foregroundStyle(color) }
                }
            }.frame(width: 46, height: 52).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 5) {
                Text(collection.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Image(systemName: collection.symbol).foregroundStyle(color)
                    Text(collection.ids.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                }.font(.caption)
            }
            Spacer(minLength: 0)
        }.padding(10).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
    }
}

private struct OrganizeDestinationRow: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color).frame(width: 28)
            Text(title).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.frame(minHeight: 56).contentShape(Rectangle())
    }
}

private struct OrganizeMediaRow: View {
    let title: String
    let ids: [String]
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let id = ids.first { PhotoThumbnail(id: id) }
                else {
                    Color(uiColor: .secondarySystemBackground)
                        .overlay { Image(systemName: symbol).foregroundStyle(.secondary) }
                }
            }.frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(ids.count.formatted()) 个项目").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 4).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

private func organizeMonthTitle(_ month: ReviewMonth) -> String {
    month.date?.formatted(.dateTime.year().month(.wide)) ?? "日期未知"
}

private struct OrganizeAlbum: Identifiable, Sendable {
    let id: String
    let title: String
    let ids: [String]
}

struct AlbumsOrganizeView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var albums: [OrganizeAlbum] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading { ProgressView().frame(maxWidth: .infinity) }
            ForEach(albums) { album in
                NavigationLink {
                    RecordBrowser(title: album.title, sourceIDs: Set(album.ids))
                } label: {
                    OrganizeMediaRow(title: album.title, ids: album.ids, symbol: "rectangle.stack")
                }
            }
        }
        .overlay {
            if !loading && albums.isEmpty {
                ContentUnavailableView("没有可访问的相簿", systemImage: "rectangle.stack")
            }
        }
        .navigationTitle("相簿").navigationBarTitleDisplayMode(.inline)
        .task(id: library.snapshotRevision) {
            loading = true
            let choices = library.albums
            let photos = library.photos
            let records = Dictionary(uniqueKeysWithValues: library.snapshot.map { ($0.id, $0) })
            let task = Task.detached(priority: .userInitiated) {
                var result: [OrganizeAlbum] = []
                for album in choices {
                    guard !Task.isCancelled else { return result }
                    let ids = photos.assetIDs(in: album.id)
                    let accessible = ids.compactMap { records[$0] }
                    result.append(OrganizeAlbum(id: album.id, title: album.title,
                        ids: MediaSorter.sorted(accessible, by: .newest).map(\.id)))
                }
                return result
            }
            let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            albums = result
            loading = false
        }
    }
}

struct TimeOrganizeView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var months: [ReviewMonth] = []
    @State private var loading = true

    var body: some View {
        List {
            ForEach(months) { month in
                NavigationLink {
                    RecordBrowser(title: organizeMonthTitle(month), sourceIDs: Set(month.ids))
                } label: {
                    OrganizeMediaRow(title: organizeMonthTitle(month), ids: month.ids, symbol: "calendar")
                }
            }
        }
        .overlay {
            if loading { ProgressView() }
            else if months.isEmpty { ContentUnavailableView("没有可整理的项目", systemImage: "calendar") }
        }
        .navigationTitle("时间").navigationBarTitleDisplayMode(.inline)
        .task(id: library.snapshotRevision) {
            loading = true
            let records = library.snapshot
            let task = Task.detached(priority: .userInitiated) { ReviewMonth.group(records) }
            let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            months = result
            loading = false
        }
    }
}

struct PlacesOrganizeView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var places: [MediaPlace] = []
    @State private var unlocated: [String] = []
    @State private var loading = true

    var body: some View {
        List {
            if !loading && places.isEmpty {
                ContentUnavailableView("没有拍摄地点", systemImage: "mappin.slash",
                    description: Text("当前项目没有可用的拍摄位置记录。"))
                    .frame(maxWidth: .infinity, minHeight: 180).listRowBackground(Color.clear)
            }
            if !places.isEmpty {
                Section {
                    ForEach(places) { place in
                        NavigationLink {
                            RecordBrowser(title: coordinateTitle(place), sourceIDs: Set(place.ids))
                        } label: {
                            OrganizeMediaRow(title: coordinateTitle(place), ids: place.ids, symbol: "mappin")
                        }
                    }
                } footer: {
                    Text("拍摄地点按 0.1° 网格汇总，坐标为网格中心。")
                }
            }
            if !unlocated.isEmpty {
                NavigationLink {
                    RecordBrowser(title: "地点未知", sourceIDs: Set(unlocated))
                } label: {
                    OrganizeMediaRow(title: "地点未知", ids: unlocated, symbol: "mappin.slash")
                }
            }
        }
        .overlay(alignment: .top) {
            if loading { ProgressView().padding() }
        }
        .navigationTitle("地点").navigationBarTitleDisplayMode(.inline)
        .task(id: library.snapshotRevision) {
            loading = true
            let records = library.snapshot
            let task = Task.detached(priority: .userInitiated) {
                let places = MediaPlace.group(records)
                let located = Set(places.flatMap(\.ids))
                let unknown = MediaSorter.sorted(records.filter { !located.contains($0.id) }, by: .newest).map(\.id)
                return (places, unknown)
            }
            let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            places = result.0
            unlocated = result.1
            loading = false
        }
    }

    private func coordinateTitle(_ place: MediaPlace) -> String {
        let latitude = String(format: "%.2f", abs(place.latitude))
        let longitude = String(format: "%.2f", abs(place.longitude))
        return "\(place.latitude < 0 ? "南纬" : "北纬") \(latitude)° · \(place.longitude < 0 ? "西经" : "东经") \(longitude)°"
    }
}
