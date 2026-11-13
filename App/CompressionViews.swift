import AVKit
import SwiftUI
import PhotoCleanerCore

struct CompressionLibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var videos = false
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    private var records: [MediaRecord] {
        library.snapshot.filter { videos ? $0.kind == .video : $0.kind == .image }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("媒体类型", selection: $videos) {
                    Text("照片").tag(false)
                    Text("视频").tag(true)
                }.pickerStyle(.segmented)
                if records.isEmpty {
                    ContentUnavailableView(videos ? "暂无视频" : "暂无照片", systemImage: videos ? "video" : "photo")
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(records) { record in
                            NavigationLink {
                                CompressionDetailView(record: record)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    PhotoThumbnail(id: record.id).aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(record.filename.isEmpty ? "未命名" : record.filename).font(.caption).lineLimit(1)
                                    Text(mediaSize(record.originalBytes)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("compression.source.\(record.filename.isEmpty ? record.id : record.filename)")
                        }
                    }
                }
            }.padding()
        }
        .navigationTitle("照片与视频压缩")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CompressionDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model = CompressionModel()
    let record: MediaRecord
    @State private var options = CompressionOptions()
    @State private var acceptsLoss = false
    @State private var deleteOriginal = false
    @State private var player: AVPlayer?
    @State private var previewImage: UIImage?
    @State private var deleting = false

    private var busy: Bool { model.isPreparing || model.isSaving || deleting }
    private var originalExists: Bool { library.record(record.id) != nil }

    var body: some View {
        Form {
            Section("原件") {
                PhotoThumbnail(id: record.id).aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .clipped().listRowInsets(EdgeInsets())
                LabeledContent("文件", value: record.filename.isEmpty ? "未命名" : record.filename)
                LabeledContent("原尺寸", value: "\(record.width) × \(record.height)")
                LabeledContent("原文件", value: mediaSize(model.originalBytes ?? record.originalBytes))
                    .accessibilityIdentifier("compression.originalBytes")
                    .accessibilityValue((model.originalBytes ?? record.originalBytes).map(String.init) ?? "unknown")
            }
            if !model.didSave {
                Section("压缩设置") {
                    if record.kind == .video {
                        Picker("分辨率上限", selection: $options.videoSize) {
                            ForEach(CompressionVideoSize.allCases) { size in Text(size.rawValue).tag(size) }
                        }
                    } else {
                        Picker("长边上限", selection: $options.maxDimension) {
                            Text("1280 像素").tag(1280)
                            Text("2048 像素").tag(2048)
                            Text("3072 像素").tag(3072)
                        }
                        LabeledContent("JPEG 画质", value: "\(Int(options.quality * 100))%")
                        Slider(value: $options.quality, in: 0.3...0.95, step: 0.05)
                            .frame(minHeight: 44).accessibilityLabel("JPEG 画质")
                    }
                    Toggle("接受有损转换", isOn: $acceptsLoss)
                        .accessibilityIdentifier("compression.acceptLoss")
                    Text(record.kind == .video
                         ? "转换为普通 MP4，画质、HDR、慢动作或空间效果可能变化。原件保留。"
                         : "转换为静态 JPEG，画质、HDR、透明度和部分元数据可能丢失；不支持实况、RAW、动画及复杂编辑资源。原件保留。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(busy || model.draft != nil)
                if model.isPreparing {
                    Section {
                        if let progress = model.progress { ProgressView(value: progress) }
                        else { ProgressView("读取原文件…") }
                        Button("取消压缩", systemImage: "xmark") { model.cancel() }
                            .frame(minHeight: 44).accessibilityIdentifier("compression.cancel")
                    }
                } else if let draft = model.draft {
                    Section("压缩预览") {
                        if let player {
                            VideoPlayer(player: player).frame(height: 260)
                        } else if let previewImage {
                            Image(uiImage: previewImage).resizable().scaledToFit().frame(maxHeight: 300)
                        } else { ProgressView() }
                        LabeledContent("副本大小", value: mediaSize(draft.outputBytes))
                            .accessibilityIdentifier("compression.outputBytes").accessibilityValue(String(draft.outputBytes))
                        LabeledContent("删除原件后可减少", value: mediaSize(draft.savedBytes))
                        Button("另存压缩副本", systemImage: "square.and.arrow.down") {
                            Task {
                                player?.pause()
                                await model.save()
                                if model.didSave { player = nil; previewImage = nil }
                            }
                        }.frame(minHeight: 44).disabled(busy || library.isDeleting)
                            .accessibilityIdentifier("compression.save")
                        Button("重新调整", systemImage: "slider.horizontal.3") {
                            player?.pause()
                            player = nil
                            previewImage = nil
                            model.discard()
                        }.frame(minHeight: 44).disabled(busy)
                    }.accessibilityIdentifier("compression.preview")
                } else {
                    Section {
                        Button("生成压缩预览", systemImage: "arrow.down.right.and.arrow.up.left") {
                            library.pause()
                            model.prepare(id: record.id, options: options, network: library.allowCloudDownload)
                        }.frame(minHeight: 44).disabled(!acceptsLoss || busy || !originalExists || library.isDeleting)
                            .accessibilityIdentifier("compression.prepare")
                    }
                }
            } else {
                Section("副本已保存") {
                    Label("原件已保留", systemImage: "checkmark.shield")
                    if let savedID = model.savedID {
                        PhotoThumbnail(id: savedID).aspectRatio(4.0 / 3.0, contentMode: .fit)
                            .accessibilityIdentifier("compression.savedCopy")
                    }
                    LabeledContent("副本大小", value: mediaSize(model.outputBytes))
                        .accessibilityIdentifier("compression.outputBytes")
                        .accessibilityValue(model.outputBytes.map(String.init) ?? "unknown")
                    Text("保留两份会额外占用副本空间。日期和位置已沿用原件，收藏和相簿归属不会自动复制。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if originalExists {
                        Button("删除原件…", systemImage: "trash", role: .destructive) { deleteOriginal = true }
                            .frame(minHeight: 44)
                            .disabled(model.savedID == nil || busy || library.isReloading || library.isDeleting || library.isProtected(record.id))
                        if library.isProtected(record.id) {
                            Label("原件受收藏或相簿保护", systemImage: "lock.shield").foregroundStyle(.secondary)
                        }
                    } else { Label("原件已不在当前相册范围", systemImage: "photo.badge.checkmark") }
                }.accessibilityIdentifier("compression.result")
            }
            if model.isSaving { Section { ProgressView("正在保存副本…") } }
            if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(record.kind == .video ? "视频压缩" : "照片压缩")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isSaving || deleting)
        .task(id: model.draft?.outputURL) {
            player?.pause()
            player = nil
            previewImage = nil
            guard let draft = model.draft else { return }
            if draft.isVideo { player = AVPlayer(url: draft.outputURL) }
            else { previewImage = UIImage(contentsOfFile: draft.outputURL.path) }
        }
        .onDisappear { player?.pause(); model.leave() }
        .confirmationDialog("确认已检查压缩副本，再删除原件？", isPresented: $deleteOriginal, titleVisibility: .visible) {
            Button("删除原件", role: .destructive) {
                Task {
                    guard let savedID = model.savedID else {
                        model.error = "压缩副本已不在当前相册范围，未删除原件。"
                        return
                    }
                    deleting = true
                    await library.deleteCompressedOriginal(originalID: record.id,
                        modifiedAt: model.originalModifiedAt, copyID: savedID)
                    deleting = false
                }
            }
        } message: {
            Text("将继续显示系统删除确认。删除会同步到 iCloud 照片设备，压缩副本将保留。")
        }
        .alert(item: $library.notice) { notice in
            Alert(title: Text("相册整理"), message: Text(notice.message), dismissButton: .default(Text("好")))
        }
    }
}
