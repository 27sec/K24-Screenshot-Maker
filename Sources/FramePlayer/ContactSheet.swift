import AppKit
import CoreGraphics

enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case even = "Evenly spaced"
    case skipEnds = "Skip intro & ending (5%)"
    case skipAds = "Skip first & last 2 min"
    var id: String { rawValue }
}

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg = "JPEG"
    case png = "PNG"
    var id: String { rawValue }
    var fileExtension: String { self == .jpeg ? "jpg" : "png" }
}

/// Columns × rows of the thumbnail grid.
enum SheetLayout: String, CaseIterable, Identifiable, Sendable {
    case g3x3 = "3x3", g3x4 = "3x4", g4x4 = "4x4", g4x5 = "4x5", g5x5 = "5x5"
    var id: String { rawValue }
    var cols: Int { Int(rawValue.prefix(1))! }
    var rows: Int { Int(rawValue.suffix(1))! }
    var count: Int { cols * rows }
    var label: String { "\(cols) × \(rows)" }
}

struct SheetSettings: Sendable {
    var layout: SheetLayout = .g3x4
    var capture: CaptureMode = .even
    var format: OutputFormat = .jpeg
    var width: Int = 1920
    var showTimestamps = true
    var includeFilename = true
    var outputDirectory: URL
}

enum ContactSheet {
    /// Timestamps for `count` frames: evenly dividing the range into count+1 parts
    /// (e.g. a 3:52 video with 12 frames → 00:17, 00:35, 00:53 …).
    static func timestamps(duration: Double, count: Int, mode: CaptureMode) -> [Double] {
        var start = 0.0, end = max(duration, 0.1)
        switch mode {
        case .even: break
        case .skipEnds:
            start = duration * 0.05; end = duration * 0.95
        case .skipAds:
            if duration > 6 * 60 { start = 120; end = duration - 120 }
        }
        let span = max(end - start, 0.1)
        return (0..<count).map { start + span * Double($0 + 1) / Double(count + 1) }
    }

    private static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "Tahoma-Bold" : "Tahoma", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    private static func sizeText(_ bytes: Int64) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.groupingSeparator = ","
        let exact = nf.string(from: NSNumber(value: bytes)) ?? "\(bytes)"
        let mb = Double(bytes) / 1_048_576
        let human = mb >= 1024 ? String(format: "%.2fGB", mb / 1024) : String(format: "%.1fMB", mb)
        return "\(human)(\(exact) bytes)"
    }

    /// Header lines in the classic thumbnail-sheet style.
    static func headerLines(url: URL, info: ProbeInfo) -> [String] {
        var res = "Resolution: \(info.displayWidth)×\(info.height)"
        if !info.aspectRatioText.isEmpty { res += "(\(info.aspectRatioText))" }
        if info.fps > 0 { res += ", fps: " + String(format: "%.2f", info.fps).replacingOccurrences(of: ".00", with: "") }
        return [
            "Filename: \(url.lastPathComponent)",
            "Size: \(sizeText(info.fileSize))",
            res,
            "Video Codec: \(ProbeInfo.shortCodec(info.videoCodec)), Audio Codec: \(ProbeInfo.shortCodec(info.audioCodec))",
            "Duration: \(formatTime(info.duration, alwaysHours: true).paddedHours)",
        ]
    }

    /// Creates one contact sheet for `url`, writes it to disk and returns the file URL.
    static func generate(for url: URL, info: ProbeInfo, settings: SheetSettings,
                         progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let cols = settings.layout.cols, rows = settings.layout.rows
        let count = settings.layout.count
        let width = min(max(settings.width, 320), 8000)
        let scale = CGFloat(width) / 1026          // the reference sheet is 1026 px wide
        let gap = max(2, Int((3 * scale).rounded()))
        let cellW = (width - gap * (cols - 1)) / cols
        let times = timestamps(duration: info.duration, count: count, mode: settings.capture)

        // Extract frames, a few at a time.
        var frames = [Int: CGImage]()
        let concurrency = 4
        var done = 0
        for batchStart in stride(from: 0, to: count, by: concurrency) {
            try Task.checkCancellation()
            let batch = batchStart..<min(batchStart + concurrency, count)
            try await withThrowingTaskGroup(of: (Int, CGImage?).self) { group in
                for i in batch {
                    group.addTask {
                        let img = try? await FF.frame(url, at: times[i], width: cellW)
                        try Task.checkCancellation()
                        return (i, img)
                    }
                }
                for try await (i, img) in group {
                    if let img { frames[i] = img }
                    done += 1
                    progress?(Double(done) / Double(count))
                }
            }
        }
        guard let first = frames.values.first else { throw FFError.noFrame }

        let aspect = Double(first.height) / Double(first.width)
        let cellH = Int((Double(cellW) * aspect).rounded())

        let headerFont = font(16 * scale)
        let lineH = (20.5 * scale).rounded()
        let lines = settings.includeFilename ? headerLines(url: url, info: info) : []
        let headerH = lines.isEmpty ? 0 : Int(lineH * CGFloat(lines.count) + 8 * scale)
        let height = headerH + rows * cellH + (rows - 1) * gap

        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FFError.failed("Could not allocate image")
        }
        // Top-left origin for layout.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let headerAttrs: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: NSColor.black]
        for (i, line) in lines.enumerated() {
            NSAttributedString(string: line, attributes: headerAttrs)
                .draw(at: CGPoint(x: 4 * scale, y: 2 * scale + lineH * CGFloat(i)))
        }

        let stampFont = font(max(10, CGFloat(cellW) * 0.04), bold: true)
        let stroke: [NSAttributedString.Key: Any] = [
            .font: stampFont, .foregroundColor: NSColor.black,
            .strokeColor: NSColor.black, .strokeWidth: 22.0,   // positive = outline only, thick halo
        ]
        let fill: [NSAttributedString.Key: Any] = [.font: stampFont, .foregroundColor: NSColor.white]

        for i in 0..<count {
            let col = i % cols, row = i / cols
            let rect = CGRect(x: col * (cellW + gap), y: headerH + row * (cellH + gap), width: cellW, height: cellH)
            if let img = frames[i] {
                ctx.saveGState()
                ctx.translateBy(x: rect.minX, y: rect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.interpolationQuality = .high
                ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
                ctx.restoreGState()
            } else {
                ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
                ctx.fill(rect)
            }
            if settings.showTimestamps {
                let text = formatTime(times[i], alwaysHours: true).paddedHours
                let size = NSAttributedString(string: text, attributes: fill).size()
                let p = CGPoint(x: rect.midX - size.width / 2, y: rect.maxY - size.height - stampFont.pointSize * 0.35)
                NSAttributedString(string: text, attributes: stroke).draw(at: p)
                NSAttributedString(string: text, attributes: fill).draw(at: p)
            }
        }

        guard let cg = ctx.makeImage() else { throw FFError.failed("Could not render sheet") }
        let rep = NSBitmapImageRep(cgImage: cg)
        let data: Data?
        switch settings.format {
        case .jpeg: data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        case .png: data = rep.representation(using: .png, properties: [:])
        }
        guard let data else { throw FFError.failed("Could not encode image") }

        try FileManager.default.createDirectory(at: settings.outputDirectory, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent + "_sheet"
        let out = uniqueURL(in: settings.outputDirectory, base: base, ext: settings.format.fileExtension)
        try data.write(to: out)
        return out
    }

    static func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    static func savePNG(_ image: CGImage, to url: URL) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw FFError.failed("Could not encode image")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

private extension String {
    /// "0:03:52" → "00:03:52"
    var paddedHours: String {
        let parts = split(separator: ":")
        guard parts.count == 3, parts[0].count == 1 else { return self }
        return "0" + self
    }
}
