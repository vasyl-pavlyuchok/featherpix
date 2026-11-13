import SwiftUI
import AppKit
import UniformTypeIdentifiers

#if !UI_SNAPSHOT
@main
#endif
struct FeatherpixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Featherpix") {
            ContentView(model: AppModel.shared)
                .frame(minWidth: 560, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L.t("About Featherpix", "Acerca de Featherpix")) { showAbout() }
            }
            CommandGroup(after: .help) {
                Button(L.hireMe) { NSWorkspace.shared.open(Credits.mailURL) }
            }
        }
    }

    @MainActor private func showAbout() {
        let credits = NSMutableAttributedString(string: L.aboutCredits, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
        ])
        let r = (credits.string as NSString).range(of: Credits.email)
        if r.location != NSNotFound { credits.addAttribute(.link, value: Credits.mailURL, range: r) }
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Lets people drop files on the Dock icon or use "Open With".
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppModel.shared.start(urls) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct Row: Identifiable {
    let id: UUID
    let name: String
    let detail: String
    let saved: Double?        // fraction saved, nil when not applicable
    let status: Status
    enum Status { case ok, kept, failed }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @AppStorage("format") var formatRaw = OutputFormat.webp.rawValue
    @AppStorage("quality.webp") var qWebp = OutputFormat.webp.defaultQuality
    @AppStorage("quality.avif") var qAvif = OutputFormat.avif.defaultQuality
    @AppStorage("quality.jpeg") var qJpeg = OutputFormat.jpeg.defaultQuality
    @AppStorage("limitWidth") var limitWidth = true
    @AppStorage("maxWidth") var maxWidth = 1920
    @AppStorage("skipLarger") var skipLarger = true

    @Published var outputDir: URL? = nil
    @Published var running = false
    @Published var total = 0
    @Published var finished = 0
    @Published var rows: [Row] = []
    @Published var summary = Summary()
    @Published var lastOutput: URL? = nil
    @Published var notes: [String] = []
    private var runner: Runner?

    var format: OutputFormat {
        get { OutputFormat(rawValue: formatRaw) ?? .webp }
        set { formatRaw = newValue.rawValue; objectWillChange.send() }
    }
    var quality: Int {
        get { switch format { case .webp: return qWebp; case .avif: return qAvif; case .jpeg: return qJpeg } }
        set {
            switch format { case .webp: qWebp = newValue; case .avif: qAvif = newValue; case .jpeg: qJpeg = newValue }
            objectWillChange.send()
        }
    }

    func apply(_ p: Preset) {
        format = p.format
        quality = p.quality
        if let w = p.maxWidth { maxWidth = w; limitWidth = true } else { limitWidth = false }
        objectWillChange.send()
    }

    func options() -> Options {
        var o = Options()
        o.format = format
        o.quality = quality
        o.maxWidth = limitWidth ? max(16, maxWidth) : nil
        o.skipIfLarger = skipLarger
        o.outputDirectory = outputDir
        return o
    }

    func start(_ urls: [URL]) {
        guard !running, !urls.isEmpty else { return }
        let o = options()
        let (jobs, skipped) = Planner.plan(urls, options: o)
        rows = []; summary = Summary(); finished = 0; total = jobs.count
        notes = skipped
        lastOutput = jobs.first.map { j in
            j.fromFolder ? outputRoot(of: j) : j.output.deletingLastPathComponent()
        }
        guard !jobs.isEmpty else { return }
        running = true
        let r = Runner(); runner = r
        Task.detached(priority: .userInitiated) {
            r.run(jobs, options: o) { res in
                Task { @MainActor in AppModel.shared.add(res) }
            }
            await MainActor.run { AppModel.shared.running = false; AppModel.shared.runner = nil }
        }
    }

    private func outputRoot(of j: Job) -> URL {
        // displayName = "<folder>/<relative path>"; walk up as many levels as the relative path has.
        let depth = j.displayName.split(separator: "/").count - 1
        var u = j.output
        for _ in 0..<depth { u = u.deletingLastPathComponent() }
        return u
    }

    func add(_ r: JobResult) {
        finished += 1
        summary.add(r)
        let row: Row
        switch r.outcome {
        case .done(let b, let a, let w):
            row = Row(id: r.id, name: r.job.displayName,
                      detail: "\(formatBytes(b)) → \(formatBytes(a))" + (w.isEmpty ? "" : " · \(w.joined(separator: "; "))"),
                      saved: b > 0 ? 1 - Double(a) / Double(b) : nil, status: .ok)
        case .keptOriginal(let b, _):
            row = Row(id: r.id, name: r.job.displayName, detail: "\(formatBytes(b)) · \(L.notSmaller)", saved: nil, status: .kept)
        case .failed(let m):
            row = Row(id: r.id, name: r.job.displayName, detail: m, saved: nil, status: .failed)
        }
        rows.insert(row, at: 0)
        if rows.count > 500 { rows.removeLast() }
    }

    func cancel() { runner?.cancel() }

    func chooseInputs() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
        p.allowedContentTypes = [.image, .folder]
        if p.runModal() == .OK { start(p.urls) }
    }

    func chooseOutput() {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        p.prompt = L.t("Use this folder", "Usar esta carpeta")
        if p.runModal() == .OK { outputDir = p.url }
    }
}
