import Foundation
import CoreGraphics
import ImageIO

enum FFError: LocalizedError {
    case notInstalled
    case failed(String)
    case noFrame

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "ffmpeg not found. Install it with: brew install ffmpeg"
        case .failed(let msg): return "ffmpeg failed: \(msg.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400))"
        case .noFrame: return "Could not read a frame from the video."
        }
    }
}

struct ProbeInfo: Sendable {
    var duration: Double = 0
    var videoCodec: String?
    var width: Int = 0
    var height: Int = 0
    var sarNum: Int = 1
    var sarDen: Int = 1
    var audioCodec: String?
    var fileSize: Int64 = 0
    var fps: Double = 0

    /// "16:9", "4:3" … of the displayed picture.
    var aspectRatioText: String {
        let w = displayWidth, h = height
        guard w > 0, h > 0 else { return "" }
        let r = Double(w) / Double(h)
        for (name, value) in [("16:9", 16.0 / 9), ("4:3", 4.0 / 3), ("21:9", 21.0 / 9), ("1.85:1", 1.85),
                              ("2.39:1", 2.39), ("5:4", 1.25), ("3:2", 1.5), ("1:1", 1.0), ("9:16", 9.0 / 16)]
            where abs(r - value) < 0.02 { return name }
        return String(format: "%.2f:1", r)
    }

    /// Short codec label in the classic thumbnail-sheet style (H264, AC3, MPEG2 …).
    static func shortCodec(_ c: String?) -> String {
        guard let c else { return "-" }
        let map = ["mpeg2video": "MPEG2", "mpeg1video": "MPEG1", "aac_latm": "AAC LATM", "hevc": "HEVC (H265)"]
        return map[c] ?? c.uppercased()
    }

    /// Display width taking anamorphic pixels (e.g. 1440x1080 TV) into account.
    var displayWidth: Int {
        guard sarNum > 0, sarDen > 0 else { return width }
        return Int((Double(width) * Double(sarNum) / Double(sarDen)).rounded())
    }

    var codecDescription: String {
        let names = ["h264": "H.264", "hevc": "HEVC", "mpeg2video": "MPEG-2", "aac": "AAC",
                     "aac_latm": "HE-AAC", "ac3": "AC-3", "eac3": "E-AC-3", "mp2": "MP2", "mp3": "MP3"]
        let v = videoCodec.map { names[$0] ?? $0.uppercased() }
        let a = audioCodec.map { names[$0] ?? $0.uppercased() }
        return [v, a].compactMap { $0 }.joined(separator: " / ")
    }
}

/// Holds a running process so a cancelled Swift task can terminate it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func set(_ p: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        process = p
        return !cancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let p = process, p.isRunning { p.terminate() }
    }
}

enum FF {
    static let ffmpegPath: String? = locate("ffmpeg")
    static let ffprobePath: String? = locate("ffprobe")

    static let videoExtensions: Set<String> = ["ts", "m2ts", "mts", "tp", "trp", "m2t", "mp4", "m4v", "mov",
                                               "mkv", "avi", "mpg", "mpeg", "vob", "webm", "flv", "wmv"]

    private static func locate(_ name: String) -> String? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/local/bin"]
        for d in dirs {
            let p = "\(d)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // MARK: - Process runner

    @discardableResult
    static func run(_ exe: String, _ args: [String], onLine: (@Sendable (String) -> Void)? = nil) async throws -> Data {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: exe)
                    p.arguments = args
                    let out = Pipe(), err = Pipe()
                    p.standardOutput = out
                    p.standardError = err
                    p.standardInput = FileHandle.nullDevice
                    guard box.set(p) else { cont.resume(throwing: CancellationError()); return }
                    do { try p.run() } catch { cont.resume(throwing: error); return }

                    var errData = Data()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        errData = err.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }

                    var data = Data()
                    let handle = out.fileHandleForReading
                    if let onLine {
                        var buffer = Data()
                        while true {
                            let chunk = handle.availableData
                            if chunk.isEmpty { break }
                            buffer.append(chunk)
                            while let nl = buffer.firstIndex(of: 0x0A) {
                                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                                buffer.removeSubrange(buffer.startIndex...nl)
                                onLine(line)
                            }
                        }
                    } else {
                        data = handle.readDataToEndOfFile()
                    }
                    group.wait()
                    p.waitUntilExit()

                    if p.terminationReason == .uncaughtSignal {
                        cont.resume(throwing: CancellationError())
                    } else if p.terminationStatus == 0 {
                        cont.resume(returning: data)
                    } else {
                        cont.resume(throwing: FFError.failed(String(decoding: errData.suffix(3000), as: UTF8.self)))
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    // MARK: - Probe

    static func probe(_ url: URL) async throws -> ProbeInfo {
        guard let ffprobe = ffprobePath else { throw FFError.notInstalled }
        let data = try await run(ffprobe, ["-v", "error", "-print_format", "json",
                                           "-show_format", "-show_streams", url.path])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FFError.failed("Unreadable ffprobe output")
        }
        var info = ProbeInfo()
        if let format = json["format"] as? [String: Any] {
            info.duration = Double(format["duration"] as? String ?? "") ?? 0
            info.fileSize = Int64(format["size"] as? String ?? "") ?? 0
        }
        let streams = json["streams"] as? [[String: Any]] ?? []
        if let v = streams.first(where: { ($0["codec_type"] as? String) == "video" && ($0["width"] as? Int ?? 0) > 0 }) {
            info.videoCodec = v["codec_name"] as? String
            info.width = v["width"] as? Int ?? 0
            info.height = v["height"] as? Int ?? 0
            if let sar = v["sample_aspect_ratio"] as? String {
                let parts = sar.split(separator: ":").compactMap { Int($0) }
                if parts.count == 2, parts[0] > 0, parts[1] > 0 { info.sarNum = parts[0]; info.sarDen = parts[1] }
            }
            if info.duration == 0, let d = v["duration"] as? String { info.duration = Double(d) ?? 0 }
            for key in ["avg_frame_rate", "r_frame_rate"] where info.fps == 0 {
                let parts = (v[key] as? String ?? "").split(separator: "/").compactMap { Double($0) }
                if parts.count == 2, parts[1] > 0, parts[0] > 0 { info.fps = parts[0] / parts[1] }
            }
        }
        if let a = streams.first(where: { ($0["codec_type"] as? String) == "audio" }) {
            info.audioCodec = a["codec_name"] as? String
        }
        if info.fileSize == 0 {
            info.fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        return info
    }

    // MARK: - Single frame

    /// Extracts one frame (square pixels, deinterlaced) scaled to `width`.
    static func frame(_ url: URL, at seconds: Double, width: Int) async throws -> CGImage {
        guard let ffmpeg = ffmpegPath else { throw FFError.notInstalled }
        var t = max(0, seconds)
        for attempt in 0..<3 {
            let filter = "yadif=deint=interlaced,scale=trunc(iw*sar/2)*2:ih,setsar=1,scale=\(max(16, width)):-2"
            let args = ["-v", "error", "-ss", String(format: "%.3f", t), "-i", url.path,
                        "-map", "0:v:0", "-frames:v", "1", "-an", "-sn", "-dn",
                        "-vf", filter, "-f", "image2pipe", "-c:v", "png", "-"]
            if let data = try? await run(ffmpeg, args), !data.isEmpty,
               let src = CGImageSourceCreateWithData(data as CFData, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return img
            }
            try Task.checkCancellation()
            // Seeking near the end of a broken recording may yield nothing; step back and retry.
            t = max(0, t - Double(5 * (attempt + 1)))
        }
        throw FFError.noFrame
    }

    /// Removes the MP4 cache the AVPlayer-based player used to create (mpv plays files directly now).
    static func removeLegacyPlaybackCache() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: base.appendingPathComponent("FramePlayer/Playback", isDirectory: true))
    }
}

func formatTime(_ seconds: Double, alwaysHours: Bool = false) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "00:00" }
    let total = Int(seconds)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    if h > 0 || alwaysHours { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%02d:%02d", m, s)
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
