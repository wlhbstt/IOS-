import Photos
import SwiftUI
import PhotoCleanerCore

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Group {
            if library.hasAccess {
                TabView {
                    NavigationStack { OrganizeView() }
                        .tabItem { Label("整理", systemImage: "rectangle.stack") }
                    NavigationStack { CleanupView() }
                        .tabItem { Label("清理", systemImage: "sparkles") }
                    NavigationStack { CategoriesView() }
                        .tabItem { Label("分类", systemImage: "square.grid.2x2") }
                    NavigationStack { RecordBrowser(title: "搜索") }
                        .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                }
                .tint(LibraryStyle.accent)
                .toolbarBackground(Color(uiColor: .systemBackground), for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .disabled(library.isDeleting || library.isSavingFavorites)
            } else {
                NavigationStack {
                    ContentUnavailableView {
                        Label("相册整理", systemImage: "photo.on.rectangle")
                    } description: {
                        Text(library.authorization == .denied || library.authorization == .restricted
                            ? "相册访问未开启" : "尚未授权访问相册")
                    } actions: {
                        if library.authorization == .notDetermined {
                            Button("选择照片访问范围") { Task { await library.requestAccess() } }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("打开设置", systemImage: "gearshape") { openSettings() }
                        }
                    }
                }
            }
        }
        .alert(item: $library.notice) { notice in
            Alert(title: Text("相册整理"), message: Text(notice.message), dismissButton: .default(Text("好")))
        }
        .overlay { LibraryOperationProgress() }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

struct LibraryControls: ViewModifier {
    @EnvironmentObject private var library: LibraryStore
    @State private var settings = false
    @State private var review = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await library.refreshResults() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(library.isReloading).accessibilityLabel("刷新扫描结果").help("刷新扫描结果")
                    Button { review = true } label: {
                        Label("待确认 \(library.selectedIDs.count + library.pendingFavoriteIDs.count)", systemImage: "tray")
                    }.disabled(library.selectedIDs.isEmpty && library.pendingFavoriteIDs.isEmpty)
                        .accessibilityIdentifier("library.pending")
                    Button { settings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置").help("设置")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                if library.isScanning || library.isReloading {
                    HStack(spacing: 12) {
                        if library.isReloading { ProgressView(); Text("正在读取相册") }
                        else {
                            ProgressView(value: Double(library.processed), total: Double(max(1, library.scanTotal)))
                            Text("\(library.processed)/\(library.scanTotal)").font(.caption.monospacedDigit())
                            Button { library.pause() } label: { Image(systemName: "pause.fill").frame(width: 44, height: 44) }
                                .accessibilityLabel("暂停扫描").help("暂停扫描")
                        }
                    }
                    .padding().background(.bar)
                }
                if !library.selectedIDs.isEmpty {
                    HStack(spacing: 16) {
                        Button { review = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "list.bullet").font(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("已选 \(library.selectedIDs.count) 项").font(.subheadline.weight(.semibold))
                                    Text(library.selectedOriginalBytes.map { mediaSize($0) } ?? "含未知大小")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(minHeight: 44)
                        }.foregroundStyle(.primary).accessibilityLabel("预览待删清单")
                        Spacer()
                        Button("删除", systemImage: "trash", role: .destructive) {
                            Task { await library.deleteSelected() }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(.red)
                        .accessibilityIdentifier("library.delete")
                        .buttonBorderShape(.roundedRectangle(radius: 8))
                        .disabled(library.isDeleting || library.isReloading)
                    }.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
                        .overlay(alignment: .top) { Divider() }
                }
                if library.selectedIDs.isEmpty && !library.pendingFavoriteIDs.isEmpty {
                    Button { review = true } label: {
                        HStack {
                            Label("待收藏 \(library.pendingFavoriteIDs.count) 项", systemImage: "heart")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.padding(16).frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.pink).background(.bar)
                }
                }
            }
            .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
            .sheet(isPresented: $review) { NavigationStack { DeletionReviewView() } }
    }
}

struct CleanupView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(library.snapshot.count.formatted())
                            .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("个项目").foregroundStyle(.secondary)
                        Spacer()
                        if library.authorization == .limited {
                            Image(systemName: "lock.shield").foregroundStyle(.secondary).accessibilityLabel("部分照片访问")
                        }
                    }
                    HStack(spacing: 16) {
                        LibraryMetric(title: "已分析", value: library.analyzedCount, color: LibraryStyle.accent)
                        LibraryMetric(title: "待分析", value: library.pendingCount, color: .primary)
                        LibraryMetric(title: "大小未知", value: library.unknownSizeCount, color: .secondary)
                    }
                    ProgressView(value: Double(library.analyzedCount), total: Double(max(1, library.snapshot.count)))
                        .tint(LibraryStyle.accent)
                }
                if !library.isScanning {
                    VStack(spacing: 10) {
                        Button { library.scan() } label: {
                            HStack {
                                Label("快速分析照片", systemImage: "viewfinder")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }.font(.subheadline.weight(.semibold)).padding(15).frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(Color(uiColor: .systemBackground))
                        .accessibilityIdentifier("library.analyze")
                        .background(LibraryStyle.accent, in: RoundedRectangle(cornerRadius: 8))
                        Button("读取原件大小与完全重复", systemImage: "internaldrive") { library.scan(originals: true) }
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                    }.disabled(library.isReloading || library.snapshot.isEmpty)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("清理项目").font(.headline)
                        Spacer()
                        NavigationLink { RecordBrowser(title: "全部项目") } label: {
                            HStack(spacing: 4) { Text("全部照片"); Image(systemName: "arrow.right") }.font(.subheadline)
                        }.accessibilityIdentifier("library.all")
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        NavigationLink { GroupListView(similar: false) } label: {
                            CleanupDestination(title: "完全重复", value: "\(library.exactGroups.count) 组", symbol: "square.on.square",
                                color: .blue, ids: library.exactGroups.first?.memberIDs ?? [])
                        }
                        NavigationLink { GroupListView(similar: true) } label: {
                            CleanupDestination(title: "相似照片", value: "\(library.similarGroups.count) 组", symbol: "rectangle.on.rectangle",
                                color: LibraryStyle.accent, ids: library.similarGroups.first?.memberIDs ?? [])
                        }
                        NavigationLink { RecordBrowser(title: "截图", tag: "截图") } label: {
                            CleanupDestination(title: "截图", value: "\(library.screenshotCount) 张", symbol: "viewfinder.rectangular",
                                color: .orange, ids: library.screenshotPreviewIDs)
                        }
                        NavigationLink { RecordBrowser(title: "疑似废片", mode: .quality) } label: {
                            CleanupDestination(title: "疑似废片", value: "\(library.qualityCount) 张", symbol: "camera.metering.unknown",
                                color: .pink, ids: library.qualityPreviewIDs)
                        }
                    }.buttonStyle(.plain)
                }
                NavigationLink { RecordBrowser(title: "临时截图候选", mode: .temporary) } label: {
                    HStack {
                        Label("临时截图候选", systemImage: "rectangle.dashed")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.font(.subheadline).padding(.vertical, 12)
                }
                Divider()
                NavigationLink { RecordBrowser(title: "大文件", mode: .all) } label: {
                    Label("大文件", systemImage: "internaldrive").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                NavigationLink { CompressionLibraryView() } label: {
                    Label("图片与视频压缩", systemImage: "arrow.down.right.and.arrow.up.left")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("library.compression")
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("相册整理")
        .refreshable { await library.reload() }
        .modifier(LibraryControls())
    }
}

struct CategoriesView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        List {
            NavigationLink { RecordBrowser(title: "全部项目") } label: { LabeledContent("全部项目", value: "\(library.snapshot.count)") }
            ForEach(library.categories, id: \.name) { category in
                NavigationLink { RecordBrowser(title: category.name, tag: category.name) } label: {
                    HStack(spacing: 14) {
                        if let id = library.categoryPreviewIDs[category.name] {
                            PhotoThumbnail(id: id).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Text(category.name).font(.body.weight(.medium))
                        Spacer()
                        Text(category.count.formatted()).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            if library.categories.isEmpty { ContentUnavailableView("尚无分类结果", systemImage: "square.grid.2x2") }
        }
        .listStyle(.plain)
        .navigationTitle("分类")
        .modifier(LibraryControls())
    }
}

enum BrowserMode: String { case all, temporary, quality }

struct RecordBrowser: View {
    @EnvironmentObject private var library: LibraryStore
    let title: String
    var tag: String? = nil
    var mode = BrowserMode.all
    var sourceIDs: Set<String>? = nil
    @State private var query = ""
    @State private var sort = MediaSort.sizeDescending
    @State private var useDates = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var results: [MediaRecord] = []
    @State private var preview: MediaRecord?
    @State private var filtering = false
    @AppStorage("library.twoRows") private var twoRows = false
    @State private var reviewLaunch: ReviewLaunch?
    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    private var filterID: String {
        "\(library.snapshotRevision)|\(query)|\(sort.rawValue)|\(useDates)|\(from.timeIntervalSince1970)|\(to.timeIntervalSince1970)|\(tag ?? "")|\(mode.rawValue)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(results.count.formatted()) 项").font(.subheadline.weight(.semibold)).monospacedDigit()
                if filtering { ProgressView().controlSize(.small) }
                Spacer()
                Button { reviewLaunch = ReviewLaunch(title: title, ids: results.map(\.id)) } label: {
                    Image(systemName: "rectangle.stack").frame(width: 44, height: 44)
                }.accessibilityLabel("逐张整理").accessibilityIdentifier("browser.review").disabled(results.isEmpty)
                Button { twoRows.toggle() } label: {
                    Image(systemName: twoRows ? "square.grid.3x3" : "rectangle.grid.1x2").frame(width: 44, height: 44)
                }.accessibilityLabel(twoRows ? "网格浏览" : "双行浏览").accessibilityIdentifier("browser.layout")
                Menu {
                    Button("选择当前结果", systemImage: "checkmark.circle") { library.selectVisible(Set(results.map(\.id))) }
                    Button("取消当前结果选择", systemImage: "minus.circle") { library.selectedIDs.subtract(Set(results.map(\.id))) }
                } label: { Image(systemName: "checklist") }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("批量选择").help("批量选择").disabled(results.isEmpty)
                Menu {
                    Toggle("日期范围", isOn: $useDates)
                    Picker("排序", selection: $sort) {
                        Text("原文件大小：从大到小").tag(MediaSort.sizeDescending)
                        Text("原文件大小：从小到大").tag(MediaSort.sizeAscending)
                        Text("日期：从新到旧").tag(MediaSort.newest)
                        Text("日期：从旧到新").tag(MediaSort.oldest)
                    }
                } label: { Image(systemName: "arrow.up.arrow.down").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("排序").help("排序")
            }.padding(.horizontal, 16).padding(.vertical, 4).background(.bar)
            if useDates {
                HStack {
                    DatePicker("从", selection: $from, in: ...to, displayedComponents: .date)
                    DatePicker("至", selection: $to, in: from..., displayedComponents: .date)
                }.font(.caption).padding(.horizontal).padding(.bottom, 10)
            }
            if results.isEmpty && !filtering {
                ContentUnavailableView("没有匹配的项目", systemImage: "photo")
            } else {
                if twoRows {
                    GeometryReader { geometry in
                        let height = min(240, max(120, (geometry.size.height - 32) / 2))
                        ScrollView(.horizontal) {
                            LazyHGrid(rows: [GridItem(.fixed(height)), GridItem(.fixed(height))], spacing: 8) {
                                ForEach(results) { record in
                                    tile(record).frame(width: max(120, height - 22))
                                }
                            }.padding(12)
                        }.accessibilityIdentifier("browser.twoRows")
                    }
                } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) { ForEach(results) { record in tile(record) } }.padding(8)
                }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "文字、分类、文件名或年份")
        .task(id: filterID) {
            filtering = true
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            let snapshot = library.snapshot
            let request = MediaQuery(text: query, tag: tag, startDate: useDates ? from : nil, endDate: useDates ? to : nil)
            let order = sort, filterMode = mode, allowed = sourceIDs
            let worker = Task.detached(priority: .userInitiated) {
                var matches: [MediaRecord] = []
                for record in snapshot {
                    try Task.checkCancellation()
                    let include: Bool = {
                    guard allowed?.contains(record.id) != false, request.matches(record) else { return false }
                    switch filterMode {
                    case .all: return true
                    case .temporary: return record.isScreenshot && !ScreenshotRules.isSensitive(text: record.text) &&
                        record.tags.contains(where: { $0 == "验证码" || $0 == "物流" })
                    case .quality: return record.tags.contains(where: { $0 == "疑似模糊" || $0 == "疑似极暗" })
                    }
                    }()
                    if include { matches.append(record) }
                }
                try Task.checkCancellation()
                return MediaSorter.sorted(matches, by: order)
            }
            await withTaskCancellationHandler(operation: {
                guard let filtered = try? await worker.value, !Task.isCancelled else { return }
                results = filtered
                filtering = false
            }, onCancel: { worker.cancel() })
        }
        .sheet(item: $preview) { record in NavigationStack { PhotoDetailView(record: record) } }
        .fullScreenCover(item: $reviewLaunch) { launch in NavigationStack { SwipeReviewView(title: launch.title, ids: launch.ids) } }
        .modifier(LibraryControls())
    }

    private func tile(_ record: MediaRecord) -> some View {
        PhotoTile(record: record, selected: library.selectedIDs.contains(record.id),
            protected: library.isProtected(record.id), selectionActive: !library.selectedIDs.isEmpty,
            select: { library.toggleSelection(record.id) }, preview: { preview = record })
    }
}

struct GroupListView: View {
    @EnvironmentObject private var library: LibraryStore
    let similar: Bool
    private var groups: [DuplicateGroup] { similar ? library.similarGroups : library.exactGroups }

    var body: some View {
        List(groups) { group in
            NavigationLink {
                GroupDetailView(group: group, similar: similar)
            } label: {
                HStack(spacing: 12) {
                    PhotoThumbnail(id: group.suggestedKeepID).frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(group.memberIDs.count) 张\(similar ? "相似照片" : "重复照片")")
                        if let record = library.record(group.suggestedKeepID) {
                            Text(record.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "日期未知")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay { if groups.isEmpty { ContentUnavailableView("尚未发现匹配组", systemImage: "square.on.square") } }
        .navigationTitle(similar ? "相似照片" : "完全重复")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("按推荐批量选择", systemImage: "checkmark.circle") { library.selectRecommended(groups) }
                    .disabled(groups.isEmpty)
            }
        }
        .modifier(LibraryControls())
    }
}

struct GroupDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    let group: DuplicateGroup
    let similar: Bool
    @State private var preview: MediaRecord?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(group.memberIDs.compactMap { library.record($0) }) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        PhotoTile(record: record, selected: library.selectedIDs.contains(record.id),
                            protected: library.isProtected(record.id), selectionActive: !library.selectedIDs.isEmpty,
                            select: { library.toggleSelection(record.id) }, preview: { preview = record })
                        if record.id == group.suggestedKeepID { Label("推荐保留", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.green) }
                    }
                }
            }.padding()
        }
        .navigationTitle(similar ? "相似照片" : "重复照片")
        .safeAreaInset(edge: .bottom) {
            Button("保留推荐项，选择其余", systemImage: "checkmark.circle") { library.selectRecommended(group) }
                .buttonStyle(.bordered).padding().frame(maxWidth: .infinity).background(.bar)
        }
        .sheet(item: $preview) { record in NavigationStack { PhotoDetailView(record: record) } }
        .modifier(LibraryControls())
    }
}
