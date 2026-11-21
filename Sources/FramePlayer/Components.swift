import SwiftUI

enum Theme {
    static let window = Color(red: 0.105, green: 0.115, blue: 0.140)
    static let titleBar = Color(red: 0.125, green: 0.135, blue: 0.160)
    static let panel = Color(red: 0.085, green: 0.090, blue: 0.105)
    static let sidebar = Color(red: 0.110, green: 0.125, blue: 0.155)
    static let row = Color(red: 0.135, green: 0.160, blue: 0.205)
    static let rowActive = Color(red: 0.165, green: 0.215, blue: 0.300)
    static let field = Color(red: 0.090, green: 0.100, blue: 0.125)
    static let card = Color(red: 0.120, green: 0.130, blue: 0.155)
    static let accent = Color(red: 0.118, green: 0.447, blue: 1.0)
    static let border = Color.white.opacity(0.13)
    static let secondaryText = Color.white.opacity(0.62)
}

struct CheckBox: View {
    var isOn: Bool
    var size: CGFloat = 20
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(isOn ? Theme.accent : Color.white.opacity(0.04))
                RoundedRectangle(cornerRadius: 4.5)
                    .strokeBorder(isOn ? Color.clear : Color.white.opacity(0.35), lineWidth: 1.2)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.6, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Thin bar with a round knob, used for both seeking and volume.
struct KnobSlider: View {
    var value: Double
    var total: Double
    var knob: CGFloat = 16
    var track: CGFloat = 4
    var onChange: (Double) -> Void
    var onEnd: (Double) -> Void = { _ in }

    @StateObject private var dragBox = Box<Double?>(nil)

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let shown = dragBox.value ?? value
            let frac = total > 0 ? min(max(shown / total, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22)).frame(height: track)
                Capsule().fill(Theme.accent).frame(width: w * frac, height: track)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: min(max(w * frac - knob / 2, 0), w - knob))
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = min(max(g.location.x / w, 0), 1) * total
                        dragBox.value = v
                        onChange(v)
                    }
                    .onEnded { g in
                        let v = min(max(g.location.x / w, 0), 1) * total
                        onEnd(v)
                        dragBox.value = nil
                    }
            )
        }
        .frame(height: knob + 6)
    }
}

struct TopBarButton: View {
    let title: String
    let icon: String
    var active = false
    let action: () -> Void
    @StateObject private var hoverBox = Box(false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 15, weight: .regular))
                Text(title).font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(active ? 0.12 : (hoverBox.value ? 0.09 : 0.05)))
            )
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverBox.value = $0 }
    }
}

struct IconButton: View {
    let icon: String
    var size: CGFloat = 20
    var help: String = ""
    let action: () -> Void
    @StateObject private var hoverBox = Box(false)

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(.white.opacity(hoverBox.value ? 1 : 0.9))
                .frame(width: size + 16, height: size + 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverBox.value = $0 }
        .help(help)
    }
}

/// Local view state (stands in for @State, whose macro plugin is missing from Command Line Tools).
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}
