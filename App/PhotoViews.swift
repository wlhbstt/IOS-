import AVKit
import Photos
import SwiftUI
import PhotoCleanerCore

func mediaSize(_ bytes: Int64?) -> String {
    guard let bytes else { return "大小未知" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .decimal
    return formatter.string(fromByteCount: bytes)
}

struct PhotoThumbnail: View {
    @EnvironmentObject private var library: LibraryStore
    let id: String
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: id) {
            image = nil
            let loaded = try? await library.photos.image(id: id, size: CGSize(width: 280, height: 280), thumbnail: true)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .onDisappear { image = nil }
        .accessibilityHidden(true)
    }
}

struct PhotoTile: View {
    let record: MediaRecord
    let selected: Bool
    let protected: Bool
    var selectionActive = false
    let select: () -> Void
    let preview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PhotoThumbnail(id: record.id)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? LibraryStyle.accent : .clear, lineWidth: 3) }
                .overlay(alignment: .topTrailing) {
                    Button(action: select) {
                        Image(systemName: protected ? "lock.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                            .font(.title3).foregroundStyle(selected ? Color(uiColor: .systemBackground) : .white)
                            .frame(width: 44, height: 44)
                            .background(selected ? LibraryStyle.accent : .black.opacity(0.40), in: Circle())
                    }
                    .buttonStyle(.plain).disabled(protected)
                    .accessibilityLabel(protected ? "已保护" : (selected ? "取消选择" : "选择待删"))
                    .padding(5)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(mediaSize(record.originalBytes)).font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 4)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4)).padding(6)
                }
                .overlay(alignment: .bottomLeading) {
                    if record.kind == .video || record.isLivePhoto {
                        Image(systemName: record.kind == .video ? "video.fill" : "livephoto")
                            .foregroundStyle(.white).padding(6).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4)).padding(5)
                    }
                }
                .contentShape(Rectangle()).onTapGesture(perform: selectionActive ? select : preview)
                .contextMenu { Button("查看照片", systemImage: "arrow.up.left.and.arrow.down.right", action: preview) }
            Text(record.filename.isEmpty ? "未命名" : record.filename).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(record.filename)
    }
}

struct PhotoDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let record: MediaRecord
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var tags = ""
    @State private var download = false
    @State private var fullResolution = false
    @State private var tagsInitialized = false
    @State private var loading = true
    @State private var failed = false

    private var current: MediaRecord { library.record(record.id) ?? record }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    if let player { VideoPlayer(player: player) }
                    else if let image { ZoomablePhoto(image: image) }
                    else if loading { ProgressView() }
                    else { Image(systemName: "icloud.and.arrow.down").font(.largeTitle).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity).frame(height: 360).clipped()
                if failed && !download {
                    Button("下载内容以预览", systemImage: "icloud.and.arrow.down") { download = true }
                        .buttonStyle(.bordered)
                } else if failed { Text("内容暂时无法读取").foregroundStyle(.secondary) }
                if current.kind == .image && !fullResolution {
                    Button("原尺寸预览", systemImage: "arrow.up.left.and.arrow.down.right") { fullResolution = true }
                        .buttonStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("原文件大小", value: mediaSize(current.originalBytes))
                    LabeledContent("分辨率", value: "\(current.width) × \(current.height)")
                    LabeledContent("日期", value: current.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")
                    if library.isProtected(record.id) { Label("已保护", systemImage: "lock.shield").foregroundStyle(.green) }
                    if current.tags.contains("疑似模糊") || current.tags.contains("疑似极暗") {
                        Text(current.tags.filter { $0.hasPrefix("疑似") }.joined(separator: "、")).foregroundStyle(.secondary)
                    }
                }
                Divider()
                TextField("标签", text: $tags, axis: .vertical).textFieldStyle(.roundedBorder)
                Button("保存标签", systemImage: "tag") { Task { await library.saveTags(id: record.id, text: tags) } }
                    .disabled(library.isScanning)
                if !current.text.isEmpty {
                    Divider()
                    Text("识别文字").font(.headline)
                    Text(current.text).font(.callout).textSelection(.enabled)
                }
            }.padding()
        }
        .navigationTitle(current.filename.isEmpty ? "照片" : current.filename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .bottomBar) {
                Button(library.selectedIDs.contains(record.id) ? "取消待删" : "加入待删", systemImage: "trash") {
                    library.toggleSelection(record.id)
                }.disabled(library.isProtected(record.id))
            }
        }
        .task(id: "\(download):\(fullResolution)") {
            if !tagsInitialized {
                tags = current.customTags.joined(separator: "，")
                tagsInitialized = true
            }
            loading = true
            failed = false
            do {
                if current.kind == .video {
                    let item = try await library.photos.playerItem(id: record.id, network: download || library.allowCloudDownload)
                    player = AVPlayer(playerItem: item)
                } else {
                    image = try await library.photos.image(id: record.id,
                        size: fullResolution ? PHImageManagerMaximumSize : CGSize(width: 2560, height: 2560),
                        network: download || library.allowCloudDownload)
                }
            } catch is CancellationError { return }
            catch { failed = true }
            loading = false
        }
        .onDisappear { player?.pause() }
    }
}

struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingPhotoScrollView { ZoomingPhotoScrollView() }

    func updateUIView(_ view: ZoomingPhotoScrollView, context: Context) {
        if view.photo.image !== image {
            view.setZoomScale(1, animated: false)
            view.photo.image = image
            view.setNeedsLayout()
        }
    }
}

final class ZoomingPhotoScrollView: UIScrollView, UIScrollViewDelegate {
    let photo = UIImageView()

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        photo.contentMode = .scaleAspectFit
        photo.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(photo)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 {
            photo.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }
}

struct DeletionReviewView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var preview: MediaRecord?

    private var selected: [MediaRecord] {
        MediaSorter.sorted(library.snapshot.filter { library.selectedIDs.contains($0.id) }, by: .sizeDescending)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("待删除", value: "\(library.selectedIDs.count) 项")
                Text("删除会同步到已开启 iCloud 照片的设备。项目通常会进入系统相册的最近删除。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ForEach(selected) { record in
                    HStack {
                        Button { preview = record } label: {
                            HStack(spacing: 12) {
                                PhotoThumbnail(id: record.id).frame(width: 52, height: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.filename.isEmpty ? "照片" : record.filename).lineLimit(1)
                                    Text(mediaSize(record.originalBytes)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Button { library.selectedIDs.remove(record.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("移出待删")
                    }
                }
            }
        }
        .navigationTitle("待删清单")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { Button("清空") { library.selectedIDs.removeAll() }.disabled(selected.isEmpty) }
            ToolbarItem(placement: .bottomBar) {
                Button("删除 \(library.selectedIDs.count) 项", systemImage: "trash", role: .destructive) {
                    Task {
                        await library.deleteSelected()
                        if library.selectedIDs.isEmpty { dismiss() }
                    }
                }
                    .disabled(library.selectedIDs.isEmpty || library.isDeleting || library.isReloading)
            }
        }
        .alert(item: $library.notice) { notice in
            Alert(title: Text("相册整理"), message: Text(notice.message), dismissButton: .default(Text("好")))
        }
        .sheet(item: $preview) { record in NavigationStack { PhotoDetailView(record: record) } }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var clear = false

    var body: some View {
        Form {
            Section("相册") {
                LabeledContent("访问范围", value: library.authorization == .limited ? "部分照片" : "全部授权照片")
                Button("更改相册访问权限", systemImage: "photo.badge.checkmark") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Toggle("允许读取 iCloud 原件", isOn: $library.allowCloudDownload)
            }
            Section("保护相簿") {
                Label("收藏项目已保护", systemImage: "heart.fill").foregroundStyle(.secondary)
                ForEach(library.albums) { album in
                    Toggle(album.title, isOn: Binding(
                        get: { library.protectedAlbumIDs.contains(album.id) },
                        set: { enabled in Task { await library.setProtected(album: album.id, enabled: enabled) } }))
                }
            }
            Section("本机索引") {
                LabeledContent("已分析", value: "\(library.analyzedCount)")
                Button("清除索引", systemImage: "trash", role: .destructive) { clear = true }
                    .disabled(library.isReloading || library.isDeleting)
            }
        }
        .navigationTitle("设置")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .confirmationDialog("清除分类、文字索引和自定义标签？照片不会被删除。", isPresented: $clear, titleVisibility: .visible) {
            Button("清除索引", role: .destructive) { Task { await library.clearIndex() } }
        }
    }
}
