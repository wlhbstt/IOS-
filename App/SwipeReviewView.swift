import SwiftUI
import PhotoCleanerCore

struct ReviewLaunch: Identifiable {
    let id = UUID()
    let title: String
    let ids: [String]
}

extension ReviewDecision {
    var title: String {
        switch self { case .delete: return "待删"; case .keep: return "保留"; case .favorite: return "待收藏"; case .skip: return "跳过" }
    }
    var symbol: String {
        switch self { case .delete: return "trash"; case .keep: return "checkmark"; case .favorite: return "heart"; case .skip: return "arrow.right.to.line" }
    }
    var color: Color {
        switch self { case .delete: return .red; case .keep: return LibraryStyle.accent; case .favorite: return .pink; case .skip: return .secondary }
    }
}

struct SwipeReviewView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    @State private var session: ReviewSession
    @State private var offset = CGSize.zero
    @State private var loadedID: String?
    @State private var pending = false
    @State private var settings = false
    @State private var detail: MediaRecord?
    @AppStorage("review.gesture.left") private var left = "delete"
    @AppStorage("review.gesture.right") private var right = "keep"
    @AppStorage("review.gesture.up") private var up = "favorite"
    @AppStorage("review.gesture.down") private var down = "skip"

    init(title: String, ids: [String]) {
        self.title = title
        _session = State(initialValue: ReviewSession(ids: ids))
    }

    private var current: MediaRecord? { session.currentID.flatMap(library.record) }
    private var busy: Bool { library.isDeleting || library.isSavingFavorites || library.isReloading }
    private var pendingCount: Int { library.selectedIDs.count + library.pendingFavoriteIDs.count }
    private var dragDecision: ReviewDecision {
        let raw = abs(offset.width) > abs(offset.height) ? (offset.width < 0 ? left : right) : (offset.height < 0 ? up : down)
        return ReviewDecision(rawValue: raw) ?? .skip
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(session.completedCount) / \(session.ids.count)").monospacedDigit()
                    .accessibilityIdentifier("review.progress")
                Spacer()
                if let current {
                    Text(current.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "日期未知")
                }
            }.font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
            ProgressView(value: Double(session.completedCount), total: Double(max(1, session.ids.count)))
                .tint(LibraryStyle.accent).padding(.horizontal, 20)
            if let record = current {
                media(record)
                HStack(spacing: 8) {
                    if library.isProtected(record.id) {
                        Label("已保护", systemImage: "lock.shield").foregroundStyle(LibraryStyle.accent)
                    } else if library.selectedIDs.contains(record.id) {
                        Label("待删", systemImage: "trash").foregroundStyle(.red)
                    } else if library.pendingFavoriteIDs.contains(record.id) {
                        Label("待收藏", systemImage: "heart").foregroundStyle(.pink)
                    }
                    Spacer(minLength: 0)
                    Text(mediaSize(record.originalBytes)).monospacedDigit()
                    Button { detail = record } label: { Image(systemName: record.kind == .video ? "play.circle" : "info.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel(record.kind == .video ? "播放视频" : "照片详情")
                }.font(.caption).padding(.horizontal, 20)
                Text(record.filename).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 20)
                    .accessibilityIdentifier("review.filename")
            } else if session.currentID != nil {
                ContentUnavailableView("项目已不在相册中", systemImage: "photo.badge.exclamationmark")
                Button("跳过") { session.decide(.skip, wasSelected: false) }.padding()
            } else {
                ContentUnavailableView {
                    Label("本组已整理", systemImage: "checkmark.circle")
                } description: { Text("\(session.completedCount) 项 · 待确认 \(pendingCount) 项") }
            }
            actions
        }
        .background(Color(uiColor: .systemBackground))
        .disabled(busy)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("手势设置")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { pending = true } label: {
                HStack {
                    Label("待确认 \(pendingCount) 项", systemImage: "tray.full")
                    Spacer()
                    Image(systemName: "chevron.right")
                }.font(.subheadline.weight(.semibold)).padding(16).frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(pendingCount > 0 ? LibraryStyle.accent : .secondary)
            .accessibilityIdentifier("review.pending").disabled(pendingCount == 0 || busy)
            .background(.bar).overlay(alignment: .top) { Divider() }
        }
        .overlay { LibraryOperationProgress(identifier: "review.operation.status") }
        .sheet(isPresented: $pending) { NavigationStack { DeletionReviewView() } }
        .sheet(isPresented: $settings) { NavigationStack { ReviewGestureSettingsView() } }
        .sheet(item: $detail) { record in NavigationStack { PhotoDetailView(record: record) } }
        .alert(item: $library.notice) { notice in
            Alert(title: Text("相册整理"), message: Text(notice.message), dismissButton: .default(Text("好")))
        }
    }

    private func media(_ record: MediaRecord) -> some View {
        GeometryReader { geometry in
            ReviewPhoto(id: record.id, onReady: { loadedID = $0 })
                .id(record.id)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .center) {
                    if max(abs(offset.width), abs(offset.height)) > 22 {
                        Label(dragDecision.title, systemImage: dragDecision.symbol)
                            .font(.title2.weight(.semibold)).foregroundStyle(.white)
                            .padding(16).background(dragDecision.color, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .offset(offset)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset.width / 35)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 16)
                    .onChanged { offset = $0.translation }
                    .onEnded { value in
                        let decision = dragDecision
                        if max(abs(value.translation.width), abs(value.translation.height)) >= 72 { decide(decision) }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { offset = .zero }
                    })
        }.padding(.horizontal, 16).padding(.top, 16).clipped()
    }

    private var actions: some View {
        HStack(alignment: .center, spacing: 8) {
            actionButton("撤销", symbol: "arrow.uturn.backward", color: .secondary, identifier: "review.undo") {
                if let step = session.undo() { library.restoreReview(step); loadedID = nil }
            }.disabled(!session.canUndo)
            ForEach([ReviewDecision.delete, .favorite, .keep, .skip], id: \.rawValue) { decision in
                actionButton(decision.title, symbol: decision.symbol, color: decision.color, identifier: "review.\(decision.rawValue)") {
                    decide(decision)
                }.disabled(current == nil || (decision == .delete && (loadedID != current?.id || current.map { library.isProtected($0.id) } == true)))
            }
        }.padding(.horizontal, 12).padding(.vertical, 16)
    }

    private func actionButton(_ title: String, symbol: String, color: Color, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48).background(color.opacity(0.10), in: Circle())
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }.foregroundStyle(color).frame(maxWidth: .infinity, minHeight: 72)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier(identifier)
    }

    private func decide(_ decision: ReviewDecision) {
        guard let record = current, !busy else { return }
        if decision == .delete && loadedID != record.id { return }
        let selected = library.selectedIDs.contains(record.id)
        let favorite = library.pendingFavoriteIDs.contains(record.id)
        guard library.stageReview(record.id, decision: decision) else { return }
        session.decide(decision, wasSelected: selected, wasFavoritePending: favorite)
        loadedID = nil
    }
}

private struct ReviewPhoto: View {
    @EnvironmentObject private var library: LibraryStore
    let id: String
    let onReady: (String) -> Void
    @State private var image: UIImage?
    @State private var failed = false
    @State private var download = false

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("整理大图").accessibilityIdentifier("review.image")
            } else if failed {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.down").font(.title)
                    Text("预览暂不可用").font(.subheadline)
                    if !download { Button("从 iCloud 加载") { download = true } }
                }.foregroundStyle(.secondary)
            } else { ProgressView() }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: "\(id):\(download)") {
            image = nil
            failed = false
            do {
                let loaded = try await library.photos.image(id: id, size: CGSize(width: 1440, height: 1440), network: download || library.allowCloudDownload)
                guard !Task.isCancelled else { return }
                image = loaded
                onReady(id)
            } catch is CancellationError { return }
            catch { failed = true }
        }
        .onDisappear { image = nil }
    }
}

struct ReviewGestureSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("review.gesture.left") private var left = "delete"
    @AppStorage("review.gesture.right") private var right = "keep"
    @AppStorage("review.gesture.up") private var up = "favorite"
    @AppStorage("review.gesture.down") private var down = "skip"

    var body: some View {
        Form {
            Section("滑动动作") {
                picker("左滑", value: $left)
                picker("右滑", value: $right)
                picker("上滑", value: $up)
                picker("下滑", value: $down)
            }
            Button("恢复默认") { left = "delete"; right = "keep"; up = "favorite"; down = "skip" }
        }
        .navigationTitle("手势设置").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }

    private func picker(_ title: String, value: Binding<String>) -> some View {
        Picker(title, selection: value) {
            ForEach(ReviewDecision.allCases, id: \.rawValue) { decision in
                Label(decision.title, systemImage: decision.symbol).tag(decision.rawValue)
            }
        }
    }
}
