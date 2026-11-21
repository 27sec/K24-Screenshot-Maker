import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var info: ProbeInfo?
    var thumbnail: NSImage?
    var selected = true
    var error: String?

    var name: String { url.lastPathComponent }
    var durationText: String { info.map { formatTime($0.duration) } ?? "--:--" }

    static func == (a: VideoItem, b: VideoItem) -> Bool {
        a.id == b.id && a.selected == b.selected && a.thumbnail === b.thumbnail
            && a.info?.duration == b.info?.duration && a.error == b.error
    }
}

enum PlaybackState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Playlist
    @Published var items: [VideoItem] = []
    @Published var currentID: UUID?
    @Published var search = ""
    @Published var showPlaylist = true

    // Player
    let player = MPVPlayer()
    @Published var playback: PlaybackState = .idle
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 0.8 { didSet { player.setVolume(volume); defaults.set(volume, forKey: "volume") } }
    @Published var muted = false { didSet { player.setMuted(muted) } }

    // Thumbnail sheet panel
    @Published var showSheetPanel = false
    @Published var layout: SheetLayout = .g3x4 { didSet { defaults.set(layout.rawValue, forKey: "layout") } }
    @Published var captureMode: CaptureMode = .even { didSet { defaults.set(captureMode.rawValue, forKey: "capture") } }
    @Published var outputFormat: OutputFormat = .jpeg { didSet { defaults.set(outputFormat.rawValue, forKey: "format") } }
    @Published var sheetWidth = 1920 { didSet { defaults.set(sheetWidth, forKey: "width") } }
    @Published var showTimestamps = true { didSet { defaults.set(showTimestamps, forKey: "timestamps") } }
    @Published var includeFilename = true { didSet { defaults.set(includeFilename, forKey: "filename") } }
    @Published var saveDirectory: URL { didSet { defaults.set(saveDirectory.path, forKey: "saveDir") } }

    @Published var generating = false
    @Published var generationProgress: Double = 0
    @Published var generationStatus = ""

    @Published var toast: Toast?

    struct Toast: Equatable {
        let id = UUID()
        let message: String
        let reveal: [URL]
    }

    private let defaults = UserDefaults.standard
    private var generateTask: Task<Void, Never>?
    private var metadataQueue: [UUID] = []
    private var metadataTask: Task<Void, Never>?

    private init() {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        saveDirectory = defaults.string(forKey: "saveDir").map { URL(fileURLWithPath: $0) }
            ?? pictures.appendingPathComponent("K24 Screenshot Maker", isDirectory: true)
        if let l = defaults.string(forKey: "layout"), let v = SheetLayout(rawValue: l) { layout = v }
        if let c = defaults.string(forKey: "capture"), let m = CaptureMode(rawValue: c) { captureMode = m }
        if let f = defaults.string(forKey: "format"), let o = OutputFormat(rawValue: f) { outputFormat = o }
        if defaults.object(forKey: "width") != nil { sheetWidth = defaults.integer(forKey: "width") }
        if defaults.object(forKey: "timestamps") != nil { showTimestamps = defaults.bool(forKey: "timestamps") }
        if defaults.object(forKey: "filename") != nil { includeFilename = defaults.bool(forKey: "filename") }
        if defaults.object(forKey: "volume") != nil { volume = defaults.float(forKey: "volume") }
        player.setVolume(volume)

        player.onTimePos = { [weak self] t in
            guard let self else { return }
            self.currentTime = t.isFinite ? max(0, t) : 0
        }
        player.onDuration = { [weak self] d in if d.isFinite, d > 0 { self?.duration = d } }
        player.onPlayingChanged = { [weak self] playing in
            if self?.isPlaying != playing { self?.isPlaying = playing }
        }
        player.onFileLoaded = { [weak self] in
            guard let self, self.currentID != nil else { return }
            self.playback = .ready
        }
        player.onFileFailed = { [weak self] message in
            guard let self, self.currentID != nil, self.playback == .loading else { return }
            self.playback = .failed(message)
        }
    }

    // MARK: - Derived

    var current: VideoItem? { items.first { $0.id == currentID } }

    var filteredItems: [VideoItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var selectedItems: [VideoItem] { items.filter(\.selected) }
    var selectedCount: Int { items.lazy.filter(\.selected).count }
    var allFilteredSelected: Bool { !filteredItems.isEmpty && filteredItems.allSatisfy(\.selected) }

    // MARK: - Adding files

    func openFiles() {
        let panel = NSOpenPanel()
        panel.title = "Open videos"
        panel.message = "Choose .ts recordings (or other videos) or a folder"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Open"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in AppModel.shared.add(urls: [url]) }
            }
        }
    }

    func add(urls: [URL]) {
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let f = e?.nextObject() as? URL {
                    if FF.videoExtensions.contains(f.pathExtension.lowercased()) { files.append(f) }
                }
            } else if FF.videoExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        let existing = Set(items.map { $0.url.standardizedFileURL.path })
        let newItems = files
            .filter { !existing.contains($0.standardizedFileURL.path) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { VideoItem(url: $0) }
        guard !newItems.isEmpty else {
            if files.isEmpty { showToast("No supported video files found") }
            return
        }
        items.append(contentsOf: newItems)
        metadataQueue.append(contentsOf: newItems.map(\.id))
        processMetadataQueue()
        if currentID == nil, let first = newItems.first { play(first.id) }
    }

    func remove(_ id: UUID) {
        if currentID == id {
            player.stop()
            currentID = nil
            playback = .idle
            currentTime = 0; duration = 0
        }
        items.removeAll { $0.id == id }
    }

    func removeAll() {
        for item in items { remove(item.id) }
    }

    private func processMetadataQueue() {
        guard metadataTask == nil else { return }
        metadataTask = Task { [weak self] in
            while let self, !self.metadataQueue.isEmpty {
                let id = self.metadataQueue.removeFirst()
                await self.loadMetadata(id)
            }
            self?.metadataTask = nil
        }
    }

    private func loadMetadata(_ id: UUID) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let url = item.url
        do {
            let info: ProbeInfo
            if let existing = item.info { info = existing } else {
                info = try await FF.probe(url)
                update(id) { $0.info = info }
            }
            let t = info.duration > 0 ? min(info.duration * 0.1, 90) : 1
            let img = try await FF.frame(url, at: t, width: 240)
            update(id) { $0.thumbnail = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)) }
        } catch {
            update(id) { $0.error = error.localizedDescription }
        }
    }

    private func update(_ id: UUID, _ change: (inout VideoItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    // MARK: - Selection

    func toggleSelected(_ id: UUID) { update(id) { $0.selected.toggle() } }

    func toggleSelectAll() {
        let target = !allFilteredSelected
        let ids = Set(filteredItems.map(\.id))
        for i in items.indices where ids.contains(items[i].id) { items[i].selected = target }
    }

    // MARK: - Playback

    func play(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        currentID = id
        currentTime = 0
        duration = item.info?.duration ?? 0
        guard player.isAvailable else {
            playback = .failed("libmpv was not found. Install it with:  brew install mpv")
            return
        }
        playback = .loading
        player.load(item.url)
    }

    func togglePlay() {
        guard player.hasFile else {
            if let id = currentID ?? items.first?.id { play(id) }
            return
        }
        if isPlaying { player.pause() } else {
            player.play()
        }
    }

    func seek(to seconds: Double, exact: Bool = true) {
        currentTime = max(0, seconds)
        player.seek(to: currentTime, exact: exact)
    }

    func skip(_ delta: Double) {
        seek(to: min(max(0, currentTime + delta), max(duration, 0)))
    }

    func playAdjacent(_ offset: Int) {
        let list = filteredItems.isEmpty ? items : filteredItems
        guard !list.isEmpty else { return }
        guard let idx = list.firstIndex(where: { $0.id == currentID }) else {
            play(list[0].id); return
        }
        if offset < 0, currentTime > 3 { seek(to: 0); return }
        let next = idx + offset
        guard list.indices.contains(next) else { return }
        play(list[next].id)
    }

    func toggleFullScreen() {
        (NSApp.keyWindow ?? NSApp.windows.first)?.toggleFullScreen(nil)
    }

    // MARK: - Capture current frame

    func captureFrame() {
        guard let item = current else { showToast("Open a video first"); return }
        let t = currentTime
        let dir = saveDirectory
        let width = item.info?.displayWidth ?? 1920
        Task {
            do {
                let img = try await FF.frame(item.url, at: t, width: max(width, 320))
                let stamp = formatTime(t, alwaysHours: true).replacingOccurrences(of: ":", with: "-")
                let out = ContactSheet.uniqueURL(in: dir, base: "\(item.url.deletingPathExtension().lastPathComponent)_\(stamp)", ext: "png")
                try ContactSheet.savePNG(img, to: out)
                showToast("Saved \(out.lastPathComponent)", reveal: [out])
            } catch {
                showToast("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Thumbnail sheets

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { saveDirectory = url }
    }

    var saveDirectoryDisplay: String {
        (saveDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    func generateSheets() {
        let targets = selectedItems
        guard !targets.isEmpty, !generating else { return }
        let settings = SheetSettings(layout: layout, capture: captureMode, format: outputFormat,
                                     width: sheetWidth, showTimestamps: showTimestamps,
                                     includeFilename: includeFilename, outputDirectory: saveDirectory)
        generating = true
        generationProgress = 0
        generationStatus = "Starting…"

        generateTask = Task { [weak self] in
            guard let self else { return }
            var outputs: [URL] = []
            var failures: [String] = []
            let total = Double(targets.count)
            for (index, item) in targets.enumerated() {
                if Task.isCancelled { break }
                self.generationStatus = "\(index + 1)/\(targets.count) · \(item.name)"
                do {
                    var info = self.items.first(where: { $0.id == item.id })?.info ?? item.info
                    if info == nil {
                        let probed = try await FF.probe(item.url)
                        info = probed
                        self.update(item.id) { $0.info = probed }
                    }
                    let url = try await ContactSheet.generate(for: item.url, info: info!, settings: settings) { p in
                        Task { @MainActor in
                            AppModel.shared.generationProgress = (Double(index) + p) / total
                        }
                    }
                    outputs.append(url)
                } catch is CancellationError {
                    break
                } catch {
                    failures.append(item.name)
                }
                self.generationProgress = Double(index + 1) / total
            }
            self.generating = false
            self.generateTask = nil
            if Task.isCancelled {
                self.showToast("Cancelled · \(outputs.count) sheet(s) created", reveal: outputs)
            } else {
                self.showSheetPanel = false
                var msg = "Created \(outputs.count) thumbnail sheet\(outputs.count == 1 ? "" : "s")"
                if !failures.isEmpty { msg += " · \(failures.count) failed" }
                self.showToast(msg, reveal: outputs)
            }
        }
    }

    func cancelSheets() {
        if generating { generateTask?.cancel() } else { showSheetPanel = false }
    }

    // MARK: - Toast

    func showToast(_ message: String, reveal: [URL] = []) {
        let t = Toast(message: message, reveal: reveal)
        withAnimation(.easeOut(duration: 0.2)) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(reveal.isEmpty ? 3 : 6))
            if self.toast?.id == t.id { withAnimation(.easeIn(duration: 0.2)) { self.toast = nil } }
        }
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
