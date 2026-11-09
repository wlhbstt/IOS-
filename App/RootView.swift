import Photos
import SwiftUI
import PhotoCleanerCore

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Group {
            if library.hasAccess {
                TabView {
                    NavigationStack { CleanupView() }.modifier(LibraryControls())
                        .tabItem { Label("清理", systemImage: "sparkles") }
                    NavigationStack { CategoriesView() }.modifier(LibraryControls())
                        .tabItem { Label("分类", systemImage: "square.grid.2x2") }
                    NavigationStack { RecordBrowser(title: "搜索") }.modifier(LibraryControls())
                        .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                }
                .tint(.green)
                .disabled(library.isDeleting)
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
        .overlay {
            if library.isDeleting { ProgressView("正在处理删除请求").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) }
        }
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
                        Label("待删 \(library.selectedIDs.count)", systemImage: "trash")
                    }.disabled(library.selectedIDs.isEmpty)
                    Button { settings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置").help("设置")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if library.isScanning || library.isReloading {
                    HStack(spacing: 12) {
                        if library.isReloading { ProgressView(); Text("正在读取相册") }
                        else {
                            ProgressView(value: Double(library.processed), total: Double(max(1, library.scanTotal)))
                            Text("\(library.processed)/\(library.scanTotal)").font(.caption.monospacedDigit())
                            Button { library.pause() } label: { Image(systemName: "pause.fill") }
                                .accessibilityLabel("暂停扫描").help("暂停扫描")
                        }
                    }
                    .padding().background(.bar)
                }
            }
            .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
            .sheet(isPresented: $review) { NavigationStack { DeletionReviewView() } }
    }
}

struct CleanupView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        List {
            Section {
                LabeledContent("可访问项目", value: "\(library.snapshot.count)")
                LabeledContent("已分析", value: "\(library.analyzedCount)")
                LabeledContent("未分析完成", value: "\(library.pendingCount)")
                LabeledContent("大小未知", value: "\(library.unknownSizeCount)")
                if library.authorization == .limited { Label("当前为部分照片访问", systemImage: "lock.shield") }
                if !library.isScanning {
                    Button("扫描未完成项目", systemImage: "play.fill") { library.scan() }
                        .disabled(library.isReloading || library.snapshot.isEmpty)
                }
            }
            Section {
                NavigationLink { RecordBrowser(title: "全部项目") } label: { Label("全部项目", systemImage: "photo.stack") }
                NavigationLink { GroupListView(similar: false) } label: {
                    LabeledContent { Text("\(library.exactGroups.count) 组") } label: { Label("完全重复", systemImage: "square.on.square") }
                }
                NavigationLink { GroupListView(similar: true) } label: {
                    LabeledContent { Text("\(library.similarGroups.count) 组") } label: { Label("相似照片", systemImage: "rectangle.on.rectangle") }
                }
                NavigationLink { RecordBrowser(title: "临时截图候选", mode: .temporary) } label: { Label("临时截图候选", systemImage: "rectangle.dashed") }
                NavigationLink { RecordBrowser(title: "疑似废片", mode: .quality) } label: { Label("疑似废片", systemImage: "camera.metering.unknown") }
            }
        }
        .navigationTitle("相册整理")
        .refreshable { await library.reload() }
    }
}

struct CategoriesView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        List {
            NavigationLink { RecordBrowser(title: "全部项目") } label: { LabeledContent("全部项目", value: "\(library.snapshot.count)") }
            ForEach(library.categories, id: \.name) { category in
                NavigationLink { RecordBrowser(title: category.name, tag: category.name) } label: {
                    LabeledContent(category.name, value: "\(category.count)")
                }
            }
            if library.categories.isEmpty { ContentUnavailableView("尚无分类结果", systemImage: "square.grid.2x2") }
        }
        .navigationTitle("分类")
    }
}

enum BrowserMode: String { case all, temporary, quality }

struct RecordBrowser: View {
    @EnvironmentObject private var library: LibraryStore
    let title: String
    var tag: String? = nil
    var mode = BrowserMode.all
    @State private var query = ""
    @State private var sort = MediaSort.sizeDescending
    @State private var useDates = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var results: [MediaRecord] = []
    @State private var preview: MediaRecord?
    @State private var filtering = false
    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 8)]

    private var filterID: String {
        "\(library.snapshotRevision)|\(query)|\(sort.rawValue)|\(useDates)|\(from.timeIntervalSince1970)|\(to.timeIntervalSince1970)|\(tag ?? "")|\(mode.rawValue)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(results.count) 项").font(.subheadline).foregroundStyle(.secondary)
                if filtering { ProgressView().controlSize(.small) }
                Spacer()
                Menu {
                    Button("选择当前结果", systemImage: "checkmark.circle") { library.selectVisible(Set(results.map(\.id))) }
                    Button("取消当前结果选择", systemImage: "minus.circle") { library.selectedIDs.subtract(Set(results.map(\.id))) }
                } label: { Image(systemName: "checklist") }
                    .accessibilityLabel("批量选择").help("批量选择").disabled(results.isEmpty)
                Toggle(isOn: $useDates) { Image(systemName: "calendar") }
                    .toggleStyle(.button).accessibilityLabel("日期范围")
                Menu {
                    Picker("排序", selection: $sort) {
                        Text("原文件大小：从大到小").tag(MediaSort.sizeDescending)
                        Text("原文件大小：从小到大").tag(MediaSort.sizeAscending)
                        Text("日期：从新到旧").tag(MediaSort.newest)
                        Text("日期：从旧到新").tag(MediaSort.oldest)
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel("排序").help("排序")
            }.padding(.horizontal).padding(.vertical, 10)
            if useDates {
                HStack {
                    DatePicker("从", selection: $from, in: ...to, displayedComponents: .date)
                    DatePicker("至", selection: $to, in: from..., displayedComponents: .date)
                }.font(.caption).padding(.horizontal).padding(.bottom, 10)
            }
            if results.isEmpty && !filtering {
                ContentUnavailableView("没有匹配的项目", systemImage: "photo")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(results) { record in
                            PhotoTile(record: record, selected: library.selectedIDs.contains(record.id),
                                protected: library.isProtected(record.id),
                                select: { library.toggleSelection(record.id) },
                                preview: { preview = record })
                        }
                    }.padding(12)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "文字、分类、文件名或年份")
        .task(id: filterID) {
            filtering = true
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            let snapshot = library.snapshot
            let request = MediaQuery(text: query, tag: tag, startDate: useDates ? from : nil, endDate: useDates ? to : nil)
            let order = sort, filterMode = mode
            let worker = Task.detached(priority: .userInitiated) {
                MediaSorter.sorted(snapshot.filter { record in
                    guard request.matches(record) else { return false }
                    switch filterMode {
                    case .all: return true
                    case .temporary: return record.isScreenshot && !ScreenshotRules.isSensitive(text: record.text) &&
                        record.tags.contains(where: { $0 == "验证码" || $0 == "物流" })
                    case .quality: return record.tags.contains(where: { $0 == "疑似模糊" || $0 == "疑似极暗" })
                    }
                }, by: order)
            }
            let filtered = await worker.value
            guard !Task.isCancelled else { return }
            results = filtered
            filtering = false
        }
        .sheet(item: $preview) { record in NavigationStack { PhotoDetailView(record: record) } }
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
                            protected: library.isProtected(record.id), select: { library.toggleSelection(record.id) }, preview: { preview = record })
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
    }
}
