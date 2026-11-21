import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--sheet"), args.count > i + 2 {
            // Headless mode: FramePlayer --sheet <video> <outdir> [3x4]
            Headless.makeSheet(video: args[i + 1], outDir: args[i + 2],
                               layout: args.count > i + 3 ? SheetLayout(rawValue: args[i + 3]) ?? .g3x4 : .g3x4)
            return
        }
        FramePlayerApp.main()
    }
}

enum Headless {
    static func makeSheet(video: String, outDir: String, layout: SheetLayout) {
        let sema = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let url = URL(fileURLWithPath: video)
                let info = try await FF.probe(url)
                print("probe: \(info.duration)s \(info.width)x\(info.height) -> \(info.displayWidth) \(info.codecDescription)")
                let settings = SheetSettings(layout: layout, outputDirectory: URL(fileURLWithPath: outDir))
                let out = try await ContactSheet.generate(for: url, info: info, settings: settings)
                print("sheet: \(out.path)")
            } catch {
                print("error: \(error.localizedDescription)")
            }
            sema.signal()
        }
        sema.wait()
    }
}

struct FramePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var model = AppModel.shared

    var body: some Scene {
        // The main window is created by AppDelegate (SwiftUI skips its window when launched by opening files).
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openFiles() }.keyboardShortcut("o")
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { model.togglePlay() }
                Button("Forward 10 s") { model.skip(10) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Back 10 s") { model.skip(-10) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("Capture Frame") { model.captureFrame() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Create Thumbnail Sheets…") { model.showSheetPanel = true }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    private var mainWindow: NSWindow?

    @MainActor func showMainWindow() {
        if let w = mainWindow { w.makeKeyAndOrderFront(nil); return }
        let root = ContentView()
            .environmentObject(AppModel.shared)
            .frame(minWidth: 1000, minHeight: 640)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1520, height: 960),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "K24 Screenshot Maker"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.contentView = NSHostingView(rootView: root)
        w.contentMinSize = NSSize(width: 1000, height: 640)
        w.center()
        w.setFrameAutosaveName("FramePlayerMain")
        mainWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { showMainWindow() }
        return true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { showMainWindow() }
        NSApp.activate(ignoringOtherApps: true)
        scheduleSnapshotIfRequested()
        let files = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
        if !files.isEmpty {
            Task { @MainActor in AppModel.shared.add(urls: files.map { URL(fileURLWithPath: $0) }) }
        }
        if FF.ffmpegPath == nil {
            Task { @MainActor in AppModel.shared.showToast("ffmpeg not found — install with: brew install ffmpeg") }
        }
        DispatchQueue.global(qos: .utility).async { FF.removeLegacyPlaybackCache() }
        // Space = play/pause, ←/→ = seek 10 s (unless typing in a text field).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let model = AppModel.shared
            switch event.keyCode {
            case 49: model.togglePlay(); return nil
            case 123: model.skip(-10); return nil
            case 124: model.skip(10); return nil
            default: return event
            }
        }
    }

    /// Debug aid: FRAMEPLAYER_SNAPSHOT=/path.png writes a picture of the window after a few seconds.
    func scheduleSnapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["FRAMEPLAYER_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if ProcessInfo.processInfo.environment["FRAMEPLAYER_SNAPSHOT_PANEL"] != nil {
                AppModel.shared.showSheetPanel = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let view = NSApp.windows.first(where: { $0.contentView != nil && $0.frame.width > 600 })?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { FileHandle.standardError.write("snapshot: no window \(NSApp.windows.map { "\($0.className) \($0.frame) \($0.isVisible)" })\n".data(using: .utf8)!); return }
                view.cacheDisplay(in: view.bounds, to: rep)
                do { try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) } catch { FileHandle.standardError.write("snapshot: \(error)\n".data(using: .utf8)!) }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppModel.shared.add(urls: urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.player.shutdown() }
    }
}
