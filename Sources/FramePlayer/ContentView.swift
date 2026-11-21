import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @StateObject private var dropBox = Box(false)

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            HStack(spacing: 0) {
                VideoPanel()
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                    .padding(.trailing, m.showPlaylist ? 0 : 8)
                if m.showPlaylist {
                    PlaylistSidebar()
                        .frame(width: 430)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .background(Theme.window)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onDrop(of: [.fileURL], isTargeted: $dropBox.value) { providers in
            m.handleDrop(providers)
            return true
        }
        .overlay {
            if dropBox.value {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Theme.accent.opacity(0.08))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Text("K24 Screenshot Maker")
                .font(.system(size: 21, weight: .semibold))
                .padding(.leading, 96)
            Spacer()
            TopBarButton(title: "Open", icon: "folder") { m.openFiles() }
            TopBarButton(title: "Playlist", icon: "list.bullet", active: m.showPlaylist) {
                withAnimation(.easeInOut(duration: 0.22)) { m.showPlaylist.toggle() }
            }
            TopBarButton(title: "Capture", icon: "camera") { m.captureFrame() }
        }
        .padding(.trailing, 16)
        .frame(height: 56)
        .background(Theme.titleBar.gesture(WindowDragGesture()))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1) }
    }
}

// MARK: - Video panel

struct VideoPanel: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MPVVideoView()
                    .onTapGesture(count: 2) { m.toggleFullScreen() }
                    .simultaneousGesture(TapGesture().onEnded { if !m.showSheetPanel { m.togglePlay() } })

                if let item = m.current {
                    Text(item.name)
                        .font(.system(size: 21, weight: .medium))
                        .shadow(color: .black.opacity(0.7), radius: 4)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }

                StatusOverlay()

                if m.showSheetPanel {
                    ThumbnailSheetPanel()
                        .frame(width: 640)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if let toast = m.toast {
                    ToastView(toast: toast)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(6)
            .animation(.easeOut(duration: 0.2), value: m.showSheetPanel)

            ControlsBar()
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.06)))
    }
}

struct StatusOverlay: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        Group {
            if m.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "film.stack").font(.system(size: 54, weight: .light))
                    Text("Drop .ts recordings here").font(.system(size: 22, weight: .semibold))
                    Text("or click Open to choose files or a folder").foregroundStyle(Theme.secondaryText)
                    Button("Open Videos…") { m.openFiles() }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                }
            } else {
                switch m.playback {
                case .failed(let message):
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32)).foregroundStyle(.yellow)
                        Text("Can't play this file").font(.system(size: 17, weight: .semibold))
                        Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center).lineLimit(6).frame(maxWidth: 460)
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.6)))
                default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToastView: View {
    @EnvironmentObject var m: AppModel
    let toast: AppModel.Toast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            Text(toast.message).font(.system(size: 14, weight: .medium)).lineLimit(2)
            if !toast.reveal.isEmpty {
                Button("Show in Finder") { m.reveal(toast.reveal) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Theme.card.opacity(0.96)))
        .overlay(Capsule().strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

// MARK: - Controls

struct ControlsBar: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 8) {
            KnobSlider(value: m.currentTime, total: max(m.duration, 0.001), knob: 18, track: 5,
                       onChange: { m.seek(to: $0, exact: false) },
                       onEnd: { m.seek(to: $0) })
                .padding(.horizontal, 14)
                .disabled(m.playback != .ready)

            HStack(spacing: 18) {
                IconButton(icon: "backward.end.fill", size: 20, help: "Previous") { m.playAdjacent(-1) }
                IconButton(icon: m.isPlaying ? "pause.fill" : "play.fill", size: 28, help: "Play / Pause (Space)") {
                    m.togglePlay()
                }
                IconButton(icon: "forward.end.fill", size: 20, help: "Next") { m.playAdjacent(1) }
                Text("\(formatTime(m.currentTime)) / \(formatTime(m.duration))")
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
                    .padding(.leading, 18)
                Spacer()
                IconButton(icon: "camera", size: 21, help: "Capture frame") { m.captureFrame() }
                IconButton(icon: m.muted || m.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           size: 19, help: "Mute") { m.muted.toggle() }
                KnobSlider(value: Double(m.volume), total: 1, knob: 16, track: 4,
                           onChange: { m.volume = Float($0); m.muted = false })
                    .frame(width: 100)
                IconButton(icon: "arrow.up.left.and.arrow.down.right", size: 18, help: "Full screen") {
                    m.toggleFullScreen()
                }
                .padding(.leading, 12)
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - Playlist

struct PlaylistSidebar: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Playlist").font(.system(size: 23, weight: .semibold))
                Text("\(m.items.count) file\(m.items.count == 1 ? "" : "s")")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
                Spacer()
                if !m.items.isEmpty {
                    Menu {
                        Button("Add Videos…") { m.openFiles() }
                        Button("Remove All", role: .destructive) { m.removeAll() }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 17))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                TextField("Search in playlist", text: $m.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                if !m.search.isEmpty {
                    Button { m.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))

            HStack(spacing: 12) {
                CheckBox(isOn: m.allFilteredSelected) { m.toggleSelectAll() }
                Text("Select all").font(.system(size: 16))
                    .onTapGesture { m.toggleSelectAll() }
                Spacer()
                Text("\(m.selectedCount) selected")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.leading, 2)
            .disabled(m.items.isEmpty)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(m.filteredItems) { item in
                        PlaylistRow(item: item, isCurrent: item.id == m.currentID)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)
            .overlay {
                if m.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 30, weight: .light))
                        Text("No videos yet").font(.system(size: 15, weight: .medium))
                        Text("Drop .ts files or a folder here").font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .foregroundStyle(Theme.secondaryText)
                } else if m.filteredItems.isEmpty {
                    Text("No matches").foregroundStyle(Theme.secondaryText)
                }
            }

            VStack(spacing: 10) {
                Button {
                    withAnimation { m.showSheetPanel = true }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.grid.2x2").font(.system(size: 21))
                        Text("Create thumbnails (\(m.selectedCount))").font(.system(size: 19, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(m.selectedCount == 0 ? Theme.accent.opacity(0.35) : Theme.accent))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(m.selectedCount == 0)

                Text("Batch capture from selected files")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(Theme.sidebar)
    }
}

struct PlaylistRow: View {
    @EnvironmentObject var m: AppModel
    let item: VideoItem
    let isCurrent: Bool
    @StateObject private var hoverBox = Box(false)

    var body: some View {
        HStack(spacing: 16) {
            CheckBox(isOn: item.selected) { m.toggleSelected(item.id) }
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.45))
                if let thumb = item.thumbnail {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                } else if item.error != nil {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                } else {
                    ProgressView().controlSize(.small)
                }
                if isCurrent, m.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.6)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(3)
                }
            }
            .frame(width: 100, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.error ?? item.durationText)
                    .font(.system(size: 15))
                    .foregroundStyle(item.error == nil ? Theme.secondaryText : .yellow)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Theme.rowActive : (hoverBox.value ? Theme.row.opacity(1.3) : Theme.row))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isCurrent ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isCurrent { m.play(item.id) } }
        .onHover { hoverBox.value = $0 }
        .help(item.url.path)
        .contextMenu {
            Button("Play") { m.play(item.id) }
            Button(item.selected ? "Deselect" : "Select") { m.toggleSelected(item.id) }
            Button("Show in Finder") { m.reveal([item.url]) }
            Divider()
            Button("Remove from Playlist", role: .destructive) { m.remove(item.id) }
        }
    }
}

// MARK: - Thumbnail sheet panel

struct ThumbnailSheetPanel: View {
    @EnvironmentObject var m: AppModel

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 15)).frame(width: 78, alignment: .leading)
    }

    var body: some View {
        let n = m.selectedCount
        VStack(alignment: .leading, spacing: 0) {
            Text("Create thumbnail sheets").font(.system(size: 22, weight: .bold))
            Text("\(n) selected video\(n == 1 ? "" : "s") • One contact sheet per video")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    label("Layout:")
                    LayoutSegment(selection: $m.layout)
                }
                HStack(spacing: 12) {
                    label("Capture:")
                    Picker("", selection: $m.captureMode) {
                        ForEach(CaptureMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 290)
                }
                HStack(spacing: 12) {
                    label("Output:")
                    Picker("", selection: $m.outputFormat) {
                        ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 290)
                    Text("Width:").font(.system(size: 15)).padding(.leading, 8)
                    TextField("", value: $m.sheetWidth, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("px").font(.system(size: 15))
                }
                HStack(spacing: 40) {
                    Toggle("Show timestamps", isOn: $m.showTimestamps)
                    Toggle("Include filename", isOn: $m.includeFilename)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 15))
                .padding(.leading, 90)
                HStack(spacing: 12) {
                    label("Save to:")
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(Color(red: 0.35, green: 0.68, blue: 1))
                        Text(m.saveDirectoryDisplay).font(.system(size: 15)).lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                    Button("Choose…") { m.chooseSaveDirectory() }
                }
            }
            .controlSize(.large)
            .padding(.top, 20)
            .disabled(m.generating)

            Divider().padding(.vertical, 16)

            HStack(spacing: 12) {
                if m.generating {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: m.generationProgress).frame(width: 300)
                        Text(m.generationStatus)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(width: 300, alignment: .leading)
                    }
                } else {
                    Text("\(m.layout.count) frames per video · \(n) sheet\(n == 1 ? "" : "s") total")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button(m.generating ? "Stop" : "Cancel") { m.cancelSheets() }
                    .keyboardShortcut(.cancelAction)
                Button("Generate \(n) sheet\(n == 1 ? "" : "s")") { m.generateSheets() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(n == 0 || m.generating)
            }
            .controlSize(.large)
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    }
}

struct LayoutSegment: View {
    @Binding var selection: SheetLayout
    private let options = SheetLayout.allCases

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { n in
                Button { selection = n } label: {
                    Text(n.label)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 72, height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selection == n ? Theme.accent : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(1)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
    }
}
