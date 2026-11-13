import SwiftUI
import AppKit

struct VideoRow: Identifiable {
    let id = UUID()
    let name: String
    var progress: Double = 0
    var state: State = .waiting
    var detail: String = ""
    var saved: Double? = nil
    enum State { case waiting, working, ok, kept, failed, cancelled }
}

@MainActor
final class VideoModel: ObservableObject {
    static let shared = VideoModel()

    @AppStorage("video.preset") var presetRaw = VideoPreset.web.rawValue
    @AppStorage("video.codec") var codecRaw = VideoCodec.h264.rawValue
    @AppStorage("video.audio") var keepAudio = true
    @AppStorage("video.quality") var quality = 100          // % of the preset bitrate
    @AppStorage("video.skipLarger") var skipLarger = true

    @Published var outputDir: URL? = nil
    @Published var running = false
    @Published var rows: [VideoRow] = []
    @Published var before: Int64 = 0
    @Published var after: Int64 = 0
    @Published var lastOutput: URL? = nil
    @Published var snippet: String? = nil
    @Published var notes: [String] = []
    @Published var copied = false
    private var engine: VideoEngine?
    private var stop = false

    var preset: VideoPreset {
        get { VideoPreset(rawValue: presetRaw) ?? .web }
        set { presetRaw = newValue.rawValue; keepAudio = newValue.keepsAudio; objectWillChange.send() }
    }
    var codec: VideoCodec {
        get { VideoCodec(rawValue: codecRaw) ?? .h264 }
        set { codecRaw = newValue.rawValue; objectWillChange.send() }
    }

    func options() -> VideoOptions {
        var o = VideoOptions()
        o.preset = preset
        o.codec = codec
        o.keepAudio = preset == .loop ? false : keepAudio
        o.qualityFactor = Double(quality) / 100
        o.skipIfLarger = skipLarger
        o.outputDirectory = outputDir
        return o
    }

    /// Files and folders → the videos inside (one level of folders is enough for footage).
    static func collect(_ urls: [URL]) -> (videos: [URL], skipped: [String]) {
        var vids: [URL] = [], skipped: [String] = []
        let fm = FileManager.default
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let items = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                vids += items.filter(isVideoFile).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else if isVideoFile(u) {
                vids.append(u)
            } else {
                skipped.append("\(u.lastPathComponent): \(L.notAVideo)")
            }
        }
        return (vids, skipped)
    }

    func start(_ urls: [URL]) {
        guard !running else { return }
        let (vids, skipped) = Self.collect(urls)
        notes = skipped
        guard !vids.isEmpty else { return }
        rows = vids.map { VideoRow(name: $0.lastPathComponent) }
        before = 0; after = 0; snippet = nil; lastOutput = nil; copied = false
        running = true; stop = false
        let o = options()
        Task.detached(priority: .userInitiated) {
            for (i, v) in vids.enumerated() {
                if await MainActor.run(body: { VideoModel.shared.stop }) {
                    await MainActor.run { VideoModel.shared.rows[i].state = .cancelled }
                    continue
                }
                let e = VideoEngine()
                await MainActor.run { VideoModel.shared.engine = e; VideoModel.shared.rows[i].state = .working }
                let gate = ProgressGate()
                let r = e.encode(v, options: o) { p in
                    guard gate.pass(p) else { return }
                    Task { @MainActor in VideoModel.shared.rows[i].progress = p }
                }
                await MainActor.run { VideoModel.shared.finish(i, r) }
            }
            await MainActor.run { VideoModel.shared.running = false; VideoModel.shared.engine = nil }
        }
    }

    private func finish(_ i: Int, _ r: VideoResult) {
        guard rows.indices.contains(i) else { return }
        rows[i].progress = 1
        switch r.kind {
        case .done(let b, let a):
            rows[i].state = .ok
            rows[i].saved = b > 0 ? 1 - Double(a) / Double(b) : nil
            rows[i].detail = "\(formatBytes(b)) → \(formatBytes(a)) · \(r.info)"
            before += b; after += a
            lastOutput = r.output
            if let s = r.htmlSnippet { snippet = s }
        case .notSmaller(let b, _):
            rows[i].state = .kept
            rows[i].detail = "\(formatBytes(b)) · \(L.notSmaller)"
        case .failed(let m):
            rows[i].state = .failed; rows[i].detail = m
        case .cancelled:
            rows[i].state = .cancelled; rows[i].detail = L.cancelled
        }
    }

    func cancel() { stop = true; engine?.cancel() }

    func copySnippet() {
        guard let s = snippet else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        withAnimation { copied = true }
    }

    func chooseInputs() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
        p.allowedContentTypes = [.movie, .folder]
        if p.runModal() == .OK { start(p.urls) }
    }

    func chooseOutput() {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        p.prompt = L.t("Use this folder", "Usar esta carpeta")
        if p.runModal() == .OK { outputDir = p.url }
    }
}

/// Lets through at most one progress update per 1 %.
final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0
    func pass(_ p: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard p - last >= 0.01 || p >= 1 else { return false }
        last = p; return true
    }
}
