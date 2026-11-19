import CoreImage
import Photos
import PhotosUI
import PhotoCleanerCore
import SwiftUI

struct PhotoEditorView: View {
    private enum Tool: String, CaseIterable {
        case ai = "AI 美化", filters = "滤镜", adjust = "调整", crop = "裁剪"
        var icon: String {
            switch self {
            case .ai: return "sparkles"
            case .filters: return "camera.filters"
            case .adjust: return "slider.horizontal.3"
            case .crop: return "crop.rotate"
            }
        }
    }

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let record: MediaRecord
    let onSaved: (Bool) -> Void

    @State private var renderer: PhotoEditRenderer?
    @State private var asset: PHAsset?
    @State private var source: CIImage?
    @State private var original: UIImage?
    @State private var preview: UIImage?
    @State private var livePreview: PHLivePhoto?
    @State private var edits = PhotoEdits()
    @State private var undo: [PhotoEdits] = []
    @State private var subjects: EditSubjects?
    @State private var tool = Tool.ai
    @State private var group = FilterGroup.everyday
    @State private var adjustment = EditControl.exposure
    @State private var allowDownload = false
    @State private var allowOriginalDownload = false
    @State private var loading = true
    @State private var comparing = false
    @State private var busy: String?
    @State private var message: String?
    @State private var showSave = false
    @State private var showDiscard = false
    @State private var thumbnails: [EditFilter: UIImage] = [:]

    var body: some View {
        VStack(spacing: 0) {
            stage.frame(maxHeight: .infinity)
            HStack(spacing: 0) {
                comparison
                Spacer()
                if record.isLivePhoto {
                    Button { playLive() } label: { Label("播放实况", systemImage: "livephoto.play") }
                        .disabled(source == nil || busy != nil)
                }
                Spacer()
                Button { if let previous = undo.popLast() { edits = previous } } label: { Image(systemName: "arrow.uturn.backward") }
                    .accessibilityLabel("撤销").disabled(undo.isEmpty || busy != nil)
                Button { change { $0 = PhotoEdits() } } label: { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("重置").disabled(!edits.hasEffects || busy != nil)
            }
            .buttonStyle(.borderless).font(.subheadline.weight(.semibold))
            .controlSize(.large).padding(.horizontal, 14).frame(minHeight: 44)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tool {
                    case .ai: aiControls
                    case .filters: filterControls
                    case .adjust: adjustControls
                    case .crop: cropControls
                    }
                }.padding(.horizontal, 14).padding(.vertical, 10)
            }.frame(height: 160).disabled(source == nil || busy != nil)
            Divider()
            HStack {
                ForEach(Tool.allCases, id: \.self) { item in
                    Button { tool = item } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon).font(.title3)
                            Text(item.rawValue).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(tool == item ? LibraryStyle.accent : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tool == item ? .isSelected : [])
                }
            }.padding(.horizontal, 12)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(record.isLivePhoto ? "编辑实况照片" : "编辑照片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { if edits.hasEffects { showDiscard = true } else { dismiss() } }.disabled(busy != nil)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { showSave = true }.fontWeight(.semibold)
                    .disabled(!edits.hasEffects || source == nil || busy != nil)
                    .accessibilityIdentifier("photo.editor.save")
            }
        }
        .confirmationDialog("保存编辑", isPresented: $showSave, titleVisibility: .visible) {
            Button(edits.background == .cutout ? "保存到原图（白色背景）" : "保存到原图") { save(copy: false) }
            Button(edits.background == .cutout ? "另存副本（透明 PNG）" : "另存副本") { save(copy: true) }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("放弃本次编辑？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃编辑", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .alert("照片编辑", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(message ?? "") }
        .alert("从 iCloud 下载原件？", isPresented: $showCloudDownload) {
            Button("允许下载") { allowOriginalDownload = true }
            Button("取消", role: .cancel) {}
        } message: { Text("下载后可重新播放实况或保存编辑。") }
        .interactiveDismissDisabled(edits.hasEffects || busy != nil)
        .task(id: allowDownload) { await load() }
        .task(id: edits) {
            livePreview = nil
            do {
                try await Task.sleep(for: .milliseconds(55))
                guard let renderer, let source else { return }
                let settings = edits, subjects = subjects
                let rendered = try await Task.detached(priority: .userInitiated) {
                    let mask = settings.background == .original ? nil : try subjects?.mask(for: settings.subjects)
                    return try renderer.raster(renderer.apply(settings, to: source, mask: mask, transparent: true))
                }.value
                guard !Task.isCancelled else { return }
                preview = UIImage(cgImage: rendered)
            } catch is CancellationError {} catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
        .task(id: tool == .filters ? group : nil) { await prepareThumbnails() }
    }

    private var stage: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image = comparing ? original : preview ?? original {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .accessibilityLabel(comparing ? "原图" : "编辑预览")
                        .accessibilityIdentifier("photo.editor.preview")
                } else if loading {
                    ProgressView()
                } else {
                    Button("从 iCloud 下载", systemImage: "icloud.and.arrow.down") { allowDownload = true }
                        .disabled(allowDownload)
                }
                if let livePreview, !comparing { EditLivePlayer(photo: livePreview).accessibilityLabel("编辑后的实况预览") }
                if let busy {
                    ProgressView(busy).padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.clipped()
    }

    private var comparison: some View {
        Label("对比", systemImage: "circle.lefthalf.filled")
            .frame(minHeight: 44).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in comparing = true }.onEnded { _ in comparing = false })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { comparing.toggle() }
            .foregroundStyle(edits.hasEffects ? LibraryStyle.accent : .secondary)
            .allowsHitTesting(edits.hasEffects)
    }

    private var aiControls: some View {
        Group {
            HStack {
                Button(edits.enhancement == nil ? "一键美化" : "取消美化", systemImage: "wand.and.stars") {
                    if edits.enhancement == nil { enhance() } else { change { $0.enhancement = nil } }
                }.accessibilityIdentifier("photo.editor.ai")
                if !record.isLivePhoto {
                    Button("虚化", systemImage: "camera.aperture") { setBackground(.blur) }
                    Button("抠图", systemImage: "person.crop.rectangle") { setBackground(.cutout) }
                }
            }.buttonStyle(.bordered).font(.subheadline)
            if edits.enhancement != nil { slider("美化强度", \.enhancementStrength, in: 0...1) }
            if edits.background == .blur { slider("虚化强度", \.blur, in: 0...1) }
            if edits.background != .original, let subjects, subjects.indices.count > 1 {
                Menu("保留主体", systemImage: "person.crop.circle") {
                    Button("全部主体") { change { $0.subjects = [] } }
                    ForEach(Array(subjects.indices.enumerated()), id: \.element) { index, id in
                        Button("主体 \(index + 1)") { change { $0.subjects = [id] } }
                    }
                }
            }
        }
    }

    private var filterControls: some View {
        Group {
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(FilterGroup.allCases) { item in
                        Button(item.rawValue) { group = item }.buttonStyle(.plain)
                            .font(.subheadline.weight(group == item ? .bold : .regular))
                            .foregroundStyle(group == item ? LibraryStyle.accent : .secondary)
                            .padding(.vertical, 4)
                    }
                }
            }.scrollIndicators(.hidden)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([EditFilter.original] + EditFilter.allCases.filter { $0 != .original && $0.look.group == group }) { item in
                        Button { change { $0.filter = item } } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Color(uiColor: .secondarySystemBackground)
                                    if let thumbnail = thumbnails[item] {
                                        Image(uiImage: thumbnail).resizable().scaledToFill()
                                    } else { ProgressView().controlSize(.mini) }
                                }.frame(width: 56, height: 44).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(edits.filter == item ? LibraryStyle.accent : .clear, lineWidth: 2) }
                                Text(item.look.title).font(.caption2).lineLimit(1)
                            }.frame(width: 60)
                        }.buttonStyle(.plain).accessibilityIdentifier("photo.editor.filter.\(item.rawValue)")
                    }
                }
            }.scrollIndicators(.hidden)
            if edits.filter != .original { slider("强度", \.intensity, in: 0...1) }
        }
    }

    private var adjustControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("调整项目", selection: $adjustment) {
                ForEach(EditControl.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            let key = adjustment.rawValue
            Slider(value: Binding(get: { edits.adjustments[key, default: 0] }, set: { edits.adjustments[key] = $0 }),
                   in: -0.8...0.8, onEditingChanged: { if $0 { remember() } }) { Text(key) }
        }
    }

    private var cropControls: some View {
        Group {
            HStack {
                Menu("比例", systemImage: "aspectratio") {
                    ForEach(EditAspect.allCases, id: \.self) { aspect in
                        let names: [EditAspect: String] = [.original: "原比例", .square: "1:1", .landscape: "4:3", .portrait: "3:4"]
                        Button(names[aspect] ?? aspect.rawValue) { change { $0.aspect = aspect } }
                    }
                }
                Button("旋转", systemImage: "rotate.right") { change { $0.turns = ($0.turns + 1) % 4 } }
            }.buttonStyle(.bordered)
            slider("拉直", \.straighten, in: -30...30)
        }
    }

    private func slider(_ title: String, _ key: WritableKeyPath<PhotoEdits, Double>, in range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.caption.weight(.medium))
            Slider(value: Binding(get: { edits[keyPath: key] }, set: { edits[keyPath: key] = $0 }),
                   in: range, onEditingChanged: { if $0 { remember() } }) { Text(title) }
        }
    }

    private func remember() {
        if undo.last != edits { undo.append(edits) }
        if undo.count > 30 { undo.removeFirst() }
    }

    private func change(_ update: (inout PhotoEdits) -> Void) {
        remember()
        update(&edits)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            guard let asset = library.photos.asset(record.id) else { throw PhotoEditError.unavailable }
            let image = try await library.photos.image(id: record.id, size: CGSize(width: 1440, height: 1440),
                                                       network: allowDownload || library.allowCloudDownload)
            guard let cgImage = image.cgImage else { throw PhotoEditError.unavailable }
            let base = CIImage(cgImage: cgImage).oriented(image.imageOrientation.cgOrientation).atOrigin()
            let engine = await Task.detached(priority: .userInitiated) { PhotoEditRenderer() }.value
            try Task.checkCancellation()
            self.asset = asset
            renderer = engine
            original = image
            source = base
        } catch is CancellationError {} catch { if allowDownload { message = error.localizedDescription } }
    }

    private func prepareThumbnails() async {
        guard tool == .filters, let source, let renderer else { return }
        let size = source.fitted(longEdge: 128)
        let items = [EditFilter.original] + EditFilter.allCases.filter { $0 != .original && $0.look.group == group }
        for item in items where thumbnails[item] == nil {
            guard !Task.isCancelled else { return }
            let thumbnail = try? await Task.detached(priority: .utility) {
                var settings = PhotoEdits()
                settings.filter = item
                return try renderer.raster(renderer.apply(settings, to: size))
            }.value
            if !Task.isCancelled, let thumbnail { thumbnails[item] = UIImage(cgImage: thumbnail) }
        }
    }

    private func enhance() {
        guard let source, let renderer else { return }
        run("正在美化") {
            let suggestion = try await Task.detached(priority: .userInitiated) { try renderer.enhance(source) }.value
            change { $0.enhancement = suggestion }
        }
    }

    private func setBackground(_ type: EditBackground) {
        guard let source, let renderer, !record.isLivePhoto else { return }
        if edits.background == type { change { $0.background = .original }; return }
        run("正在识别主体") {
            if subjects == nil { subjects = try await Task.detached(priority: .userInitiated) { try renderer.subjects(in: source) }.value }
            change { $0.background = type }
        }
    }

    private func playLive() {
        guard let asset, let renderer else { return }
        let settings = edits
        run("正在生成实况预览") {
            let input = try await editInput(asset)
            let rendered = try await PhotoEditSave.playback(input, edits: settings, renderer: renderer)
            livePreview = nil
            await Task.yield()
            livePreview = rendered
        }
    }

    private func save(copy: Bool) {
        guard let asset, let renderer else { return }
        let settings = edits, subjects = subjects
        run("正在保存") {
            let input = try await editInput(asset)
            let mask = try await Task.detached(priority: .userInitiated) {
                settings.background == .original ? nil : try subjects?.mask(for: settings.subjects)
            }.value
            try await PhotoEditSave.save(asset: asset, input: input, edits: settings, copy: copy, renderer: renderer, mask: mask)
            onSaved(copy)
            dismiss()
        }
    }

    private func editInput(_ asset: PHAsset) async throws -> PHContentEditingInput {
        do { return try await PhotoEditSave.input(for: asset, network: allowOriginalDownload || allowDownload || library.allowCloudDownload) }
        catch PhotoEditError.cloud { showCloudDownload = true; throw CancellationError() }
    }

    @State private var showCloudDownload = false

    private func run(_ description: String, operation: @escaping @MainActor () async throws -> Void) {
        guard busy == nil else { return }
        busy = description
        Task { @MainActor in
            defer { busy = nil }
            do { try await operation() }
            catch is CancellationError {} catch { message = error.localizedDescription }
        }
    }
}

private struct EditLivePlayer: UIViewRepresentable {
    let photo: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        guard view.livePhoto !== photo else { return }
        view.livePhoto = photo
        view.startPlayback(with: .full)
    }
}
