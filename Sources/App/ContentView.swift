import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Root window: one app, two moods. The tab changes the whole atmosphere (colour, symbol, light),
/// so you know whether you are in Photos or Videos without reading anything.
struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var video: VideoModel = .shared
    @AppStorage("tab") private var tabRaw = AppTab.photos.rawValue
    @State private var targeted = false

    private var tab: Binding<AppTab> {
        Binding(get: { AppTab(rawValue: tabRaw) ?? .photos }, set: { tabRaw = $0.rawValue })
    }
    private var theme: TabTheme { .of(tab.wrappedValue) }

    var body: some View {
        ZStack {
            Atmosphere(theme: theme, tab: tab.wrappedValue)
                .animation(.easeInOut(duration: 0.55), value: tabRaw)
            VStack(spacing: 18) {
                header
                Group {
                    if tab.wrappedValue == .photos {
                        PhotoPanel(model: model, theme: theme, targeted: $targeted, onDrop: route)
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    } else {
                        VideoPanel(model: video, theme: theme, targeted: $targeted, onDrop: route)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.86), value: tabRaw)
                Spacer(minLength: 0)
                Footer(theme: theme)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
        }
        .preferredColorScheme(.dark)
        .tint(theme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .featherpixOpen)) { n in
            if let urls = n.object as? [URL] { route(urls) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.35)).frame(width: 30, height: 30).blur(radius: 10)
                Image(nsImage: AppIcon.image).resizable().interpolation(.high).frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Featherpix").font(.system(size: 17, weight: .semibold)).foregroundStyle(Ink.title)
                Text(tab.wrappedValue == .photos ? L.photosTagline : L.videosTagline)
                    .font(.system(size: 11)).foregroundStyle(Ink.label)
                    .id(tabRaw).transition(.opacity)
            }
            Spacer()
            TabSwitcher(tab: tab, theme: theme)
        }
    }

    /// Whatever is dropped goes where it belongs: images to Photos, videos to Videos.
    private func route(_ urls: [URL]) {
        let vids = urls.filter(isVideoFile)
        let rest = urls.filter { !isVideoFile($0) }
        let hasFolder = rest.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if !vids.isEmpty && rest.isEmpty {
            withAnimation { tabRaw = AppTab.videos.rawValue }
            video.start(vids)
        } else if hasFolder && tab.wrappedValue == .videos && vids.isEmpty {
            video.start(rest)
        } else {
            if !rest.isEmpty { withAnimation { tabRaw = AppTab.photos.rawValue }; model.start(rest) }
            if !vids.isEmpty { video.start(vids) }
        }
    }
}

extension Notification.Name { static let featherpixOpen = Notification.Name("featherpixOpen") }

// MARK: - Photos

struct PhotoPanel: View {
    @ObservedObject var model: AppModel
    let theme: TabTheme
    @Binding var targeted: Bool
    let onDrop: ([URL]) -> Void

    private func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { set($0); model.objectWillChange.send() })
    }

    var body: some View {
        VStack(spacing: 14) {
            DropZone(theme: theme, targeted: $targeted, onDrop: onDrop) {
                VStack(spacing: 10) {
                    Image(systemName: "photo.stack").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(theme.accent)
                    Text(L.dropTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(Ink.title)
                    Text(L.dropHint).font(.system(size: 12)).foregroundStyle(Ink.body).multilineTextAlignment(.center)
                    Text(L.formatsLine).font(.system(size: 11)).foregroundStyle(Ink.label)
                    Button(L.choose) { model.chooseInputs() }.buttonStyle(AccentButtonStyle(theme: theme)).padding(.top, 4)
                        .disabled(model.running)
                }
                .padding(.horizontal, 20)
            }

            if model.total > 0 && !model.running && model.summary.before > 0 {
                resultCard
            } else if model.running {
                progressCard
            } else {
                settings
            }
            if !model.rows.isEmpty || !model.notes.isEmpty { list }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: L.presets)
            HStack(spacing: 8) {
                ForEach(Preset.all) { p in
                    let (title, sub) = L.preset(p.id)
                    let on = model.format == p.format && model.quality == p.quality && (p.maxWidth == nil ? !model.limitWidth : (model.limitWidth && model.maxWidth == p.maxWidth))
                    Chip(title: title, subtitle: sub, on: on, theme: theme) { model.apply(p) }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: L.format)
                    HStack(spacing: 6) {
                        ForEach(OutputFormat.allCases) { f in
                            Chip(title: f.label, on: model.format == f, theme: theme) { model.format = f }
                        }
                    }
                    Text(L.hint(model.format)).font(.system(size: 11)).foregroundStyle(Ink.label)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionLabel(text: L.quality)
                        Spacer()
                        Text("\(model.quality)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(theme.accentHi).monospacedDigit()
                    }
                    Slider(value: bind({ Double(model.quality) }, { model.quality = Int($0.rounded()) }), in: 30...95, step: 1)
                    HStack(spacing: 8) {
                        Toggle(L.limitWidth, isOn: bind({ model.limitWidth }, { model.limitWidth = $0 }))
                            .toggleStyle(.switch).controlSize(.mini)
                        TextField("", value: bind({ model.maxWidth }, { model.maxWidth = max(16, $0) }), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 64).disabled(!model.limitWidth)
                        Text("px").foregroundStyle(Ink.label)
                    }
                    .font(.system(size: 12)).foregroundStyle(Ink.lead)
                }
            }
            Divider().overlay(Ink.hairline)
            HStack {
                Toggle(L.skipLarger, isOn: bind({ model.skipLarger }, { model.skipLarger = $0 })).toggleStyle(.switch).controlSize(.mini)
                Spacer()
                if let d = model.outputDir {
                    Label(d.lastPathComponent, systemImage: "folder").lineLimit(1)
                    Button(L.outputNextTo) { model.outputDir = nil }.buttonStyle(.link)
                } else {
                    Button(L.outputChoose) { model.chooseOutput() }.buttonStyle(.link)
                }
            }
            .font(.system(size: 12)).foregroundStyle(Ink.lead)
        }
        .padding(18)
        .glass(theme)
        .disabled(model.running)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.working).font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.title)
                Spacer()
                Text("\(model.finished)/\(model.total)").monospacedDigit().foregroundStyle(Ink.body)
                Button(L.cancel) { model.cancel() }.buttonStyle(QuietButtonStyle())
            }
            GlowBar(value: Double(model.finished) / Double(max(1, model.total)), theme: theme)
        }
        .padding(18).glass(theme)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SavingsHero(before: model.summary.before, after: model.summary.after, theme: theme)
            HStack(spacing: 8) {
                let s = model.summary
                Text("\(s.done + s.kept + s.failed) \(L.images)" + (s.kept > 0 ? " · \(s.kept) \(L.kept)" : "") + (s.failed > 0 ? " · \(s.failed) \(L.failed)" : ""))
                    .font(.system(size: 12)).foregroundStyle(Ink.body)
                Spacer()
                if let out = model.lastOutput {
                    Button(L.showInFinder) { NSWorkspace.shared.activateFileViewerSelecting([out]) }.buttonStyle(AccentButtonStyle(theme: theme))
                }
                Button(L.again) { model.rows = []; model.total = 0; model.notes = []; model.summary = Summary() }.buttonStyle(QuietButtonStyle())
            }
        }
        .padding(18).glass(theme)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(model.notes, id: \.self) { n in
                    ResultLine(icon: "minus.circle", tint: Ink.label, name: n, detail: "", saved: nil, theme: theme)
                }
                ForEach(model.rows) { r in
                    ResultLine(icon: r.status == .ok ? "checkmark.circle.fill" : r.status == .kept ? "equal.circle" : "xmark.octagon.fill",
                               tint: r.status == .ok ? theme.accent : r.status == .kept ? Ink.label : Color(hex: 0xF66E60),
                               name: r.name, detail: r.detail, saved: r.saved, theme: theme)
                }
            }
            .padding(10)
        }
        .frame(minHeight: 120, maxHeight: 220)
        .glass(theme, radius: 16)
    }
}

// MARK: - Videos

struct VideoPanel: View {
    @ObservedObject var model: VideoModel
    let theme: TabTheme
    @Binding var targeted: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 14) {
            DropZone(theme: theme, targeted: $targeted, onDrop: onDrop) {
                VStack(spacing: 10) {
                    Image(systemName: "film.stack").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(theme.accent)
                    Text(L.dropVideoTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(Ink.title)
                    Text(L.dropVideoHint).font(.system(size: 12)).foregroundStyle(Ink.body).multilineTextAlignment(.center)
                    Text(L.videoFormatsLine).font(.system(size: 11)).foregroundStyle(Ink.label)
                    Button(L.choose) { model.chooseInputs() }.buttonStyle(AccentButtonStyle(theme: theme)).padding(.top, 4)
                        .disabled(model.running)
                }
                .padding(.horizontal, 20)
            }
            if model.running {
                progressCard
            } else if model.after > 0 {
                resultCard
            } else {
                settings
            }
            if !model.rows.isEmpty || !model.notes.isEmpty { list }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: L.videoUse)
            HStack(spacing: 8) {
                ForEach(VideoPreset.allCases) { p in
                    let (title, sub) = L.videoPreset(p)
                    Chip(title: title, subtitle: sub, on: model.preset == p, theme: theme) { model.preset = p }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: L.outputFormat)
                    HStack(spacing: 6) {
                        ForEach(VideoCodec.allCases) { c in
                            Chip(title: c == .h264 ? "MP4" : "HEVC", subtitle: c == .h264 ? "H.264" : "H.265", on: model.codec == c, theme: theme) { model.codec = c }
                        }
                        Chip(title: "WebM", subtitle: L.soon, on: false, theme: theme, disabled: true) {}
                            .help(L.webmSoon)
                    }
                    Text(L.codecHint(model.codec)).font(.system(size: 11)).foregroundStyle(Ink.label)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionLabel(text: L.quality)
                        Spacer()
                        Text("\(model.quality) %").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(theme.accentHi).monospacedDigit()
                    }
                    Slider(value: Binding(get: { Double(model.quality) }, set: { model.quality = Int($0.rounded()) }), in: 50...200, step: 5)
                    Toggle(L.keepAudio, isOn: Binding(get: { model.preset == .loop ? false : model.keepAudio }, set: { model.keepAudio = $0 }))
                        .toggleStyle(.switch).controlSize(.mini).disabled(model.preset == .loop)
                        .font(.system(size: 12)).foregroundStyle(Ink.lead)
                }
            }
            Divider().overlay(Ink.hairline)
            HStack {
                Toggle(L.skipLarger, isOn: $model.skipLarger).toggleStyle(.switch).controlSize(.mini)
                Spacer()
                if let d = model.outputDir {
                    Label(d.lastPathComponent, systemImage: "folder").lineLimit(1)
                    Button(L.outputNextTo) { model.outputDir = nil }.buttonStyle(.link)
                } else {
                    Button(L.outputChoose) { model.chooseOutput() }.buttonStyle(.link)
                }
            }
            .font(.system(size: 12)).foregroundStyle(Ink.lead)
        }
        .padding(18)
        .glass(theme)
    }

    private var progressCard: some View {
        let done = model.rows.filter { [.ok, .kept, .failed, .cancelled].contains($0.state) }.count
        let current = model.rows.first { $0.state == .working }
        let overall = (Double(done) + (current?.progress ?? 0)) / Double(max(1, model.rows.count))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(current.map { "\(L.working) \($0.name)" } ?? L.working)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.title).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(Int(overall * 100)) %").monospacedDigit().foregroundStyle(theme.accentHi)
                Button(L.cancel) { model.cancel() }.buttonStyle(QuietButtonStyle())
            }
            GlowBar(value: overall, theme: theme)
        }
        .padding(18).glass(theme)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SavingsHero(before: model.before, after: model.after, theme: theme)
            if let s = model.snippet {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: L.forYourWeb)
                    Text(s).font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.lead)
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
                }
            }
            HStack(spacing: 8) {
                Spacer()
                if model.snippet != nil {
                    Button(model.copied ? L.copied : L.copyHTML) { model.copySnippet() }.buttonStyle(QuietButtonStyle())
                }
                if let out = model.lastOutput {
                    Button(L.showInFinder) { NSWorkspace.shared.activateFileViewerSelecting([out]) }.buttonStyle(AccentButtonStyle(theme: theme))
                }
                Button(L.again) { model.rows = []; model.before = 0; model.after = 0; model.snippet = nil; model.notes = [] }.buttonStyle(QuietButtonStyle())
            }
        }
        .padding(18).glass(theme)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(model.notes, id: \.self) { n in
                    ResultLine(icon: "minus.circle", tint: Ink.label, name: n, detail: "", saved: nil, theme: theme)
                }
                ForEach(model.rows) { r in
                    ResultLine(icon: icon(r.state), tint: tint(r.state), name: r.name, detail: r.detail, saved: r.saved, theme: theme,
                               progress: r.state == .working ? r.progress : nil)
                }
            }
            .padding(10)
        }
        .frame(minHeight: 90, maxHeight: 200)
        .glass(theme, radius: 16)
    }

    private func icon(_ s: VideoRow.State) -> String {
        switch s {
        case .waiting: return "clock"
        case .working: return "circle.dotted"
        case .ok: return "checkmark.circle.fill"
        case .kept: return "equal.circle"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle"
        }
    }
    private func tint(_ s: VideoRow.State) -> Color {
        switch s {
        case .ok, .working: return theme.accent
        case .failed: return theme.accentHi
        default: return Ink.label
        }
    }
}

// MARK: - Shared rows and bars

struct ResultLine: View {
    let icon: String
    let tint: Color
    let name: String
    let detail: String
    let saved: Double?
    let theme: TabTheme
    var progress: Double? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Ink.title).lineLimit(1).truncationMode(.middle)
                if let p = progress {
                    GlowBar(value: p, theme: theme, height: 3)
                } else if !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Ink.body).lineLimit(2)
                }
            }
            Spacer()
            if let s = saved {
                Text(String(format: "−%.0f %%", s * 100)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(s > 0 ? theme.accentHi : Ink.label)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.025)))
    }
}

struct GlowBar: View {
    let value: Double
    let theme: TabTheme
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [theme.accent, theme.accentHi], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * min(1, max(0, value))))
                    .shadow(color: theme.accent.opacity(0.7), radius: 6)
                    .animation(.easeOut(duration: 0.25), value: value)
            }
        }
        .frame(height: height)
    }
}

enum AppIcon {
    /// The real feather icon (from the bundle); the snapshot tool falls back to the repo copy.
    static let image: NSImage = {
        if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let i = NSImage(contentsOf: u) { return i }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIcon.icns")
        return NSImage(contentsOf: repo) ?? NSApp.applicationIconImage
    }()
}
