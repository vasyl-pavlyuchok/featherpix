import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false

    private func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { set($0); model.objectWillChange.send() })
    }

    var body: some View {
        VStack(spacing: 16) {
            dropZone
            settings
            if model.total > 0 || !model.notes.isEmpty { results }
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
    }

    // MARK: footer (signature + contact)
    private var footer: some View {
        HStack(spacing: 6) {
            Text(L.designedBy).foregroundStyle(.tertiary)
            Text(Credits.author).fontWeight(.medium).foregroundStyle(.secondary)
            Spacer()
            Link(destination: Credits.mailURL) {
                Label(L.hireMe, systemImage: "envelope")
            }
            .foregroundStyle(.secondary)
            .help(Credits.email)
        }
        .font(.caption)
        .padding(.top, 2)
    }

    // MARK: drop zone
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            VStack(spacing: 10) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(targeted ? Color.accentColor : .secondary)
                Text(L.dropTitle).font(.title3.weight(.semibold))
                Text(L.dropHint).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(L.formatsLine).font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                Button(L.choose) { model.chooseInputs() }
                    .controlSize(.large)
                    .disabled(model.running)
            }
            .padding(24)
        }
        .frame(height: 226)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            guard !model.running else { return false }
            var urls: [URL] = []
            let group = DispatchGroup()
            let lock = NSLock()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { lock.lock(); urls.append(url); lock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) { model.start(urls) }
            return true
        }
    }

    // MARK: settings
    private var settings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(L.presets).frame(width: 110, alignment: .leading)
                    ForEach(Preset.all) { p in
                        let (title, sub) = L.preset(p.id)
                        Button { model.apply(p) } label: {
                            VStack(spacing: 1) {
                                Text(title).font(.callout.weight(.medium))
                                Text(sub).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                    }
                }
                Divider()
                HStack {
                    Text(L.format).frame(width: 110, alignment: .leading)
                    Picker("", selection: bind({ model.format }, { model.format = $0 })) {
                        ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 280)
                    Spacer()
                }
                Text(L.hint(model.format)).font(.caption).foregroundStyle(.secondary).padding(.leading, 110)

                HStack {
                    Text(L.quality).frame(width: 110, alignment: .leading)
                    Slider(value: bind({ Double(model.quality) }, { model.quality = Int($0.rounded()) }), in: 30...95, step: 1)
                    Text("\(model.quality)").monospacedDigit().frame(width: 32, alignment: .trailing)
                    Button(L.defaults) { model.quality = model.format.defaultQuality }
                        .buttonStyle(.link).font(.caption)
                }

                HStack {
                    Text(L.maxWidth).frame(width: 110, alignment: .leading)
                    Toggle(L.limitWidth, isOn: bind({ model.limitWidth }, { model.limitWidth = $0 }))
                    TextField("", value: bind({ model.maxWidth }, { model.maxWidth = max(16, $0) }), format: .number.grouping(.never))
                        .frame(width: 70).disabled(!model.limitWidth)
                    Text("px").foregroundStyle(.secondary)
                    Menu("") {
                        ForEach([1200, 1600, 1920, 2560, 3840], id: \.self) { w in
                            Button("\(w) px") { model.maxWidth = w; model.limitWidth = true; model.objectWillChange.send() }
                        }
                    }
                    .menuStyle(.borderlessButton).frame(width: 28).disabled(!model.limitWidth)
                    Spacer()
                }

                Toggle(L.skipLarger, isOn: bind({ model.skipLarger }, { model.skipLarger = $0 }))
                    .padding(.leading, 110)

                HStack {
                    Text("").frame(width: 110)
                    if let d = model.outputDir {
                        Label(d.lastPathComponent, systemImage: "folder").lineLimit(1).truncationMode(.middle)
                        Button(L.outputNextTo) { model.outputDir = nil }.buttonStyle(.link)
                    } else {
                        Text(L.outputNextTo).foregroundStyle(.secondary)
                        Button(L.outputChoose) { model.chooseOutput() }.buttonStyle(.link)
                    }
                    Spacer()
                }
                .font(.callout)
            }
            .padding(8)
            .disabled(model.running)
        }
    }

    // MARK: results
    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if model.running {
                    ProgressView(value: Double(model.finished), total: Double(max(model.total, 1)))
                    Text("\(model.finished)/\(model.total)").monospacedDigit().foregroundStyle(.secondary)
                    Button(L.cancel) { model.cancel() }
                } else {
                    summaryLine
                    Spacer()
                    if let out = model.lastOutput {
                        Button(L.showInFinder) { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                    }
                    Button(L.clear) { model.rows = []; model.total = 0; model.notes = [] }
                }
            }
            List {
                ForEach(model.notes, id: \.self) { n in
                    Label(n, systemImage: "minus.circle").foregroundStyle(.secondary).font(.callout)
                }
                ForEach(model.rows) { r in
                    HStack {
                        Image(systemName: r.status == .ok ? "checkmark.circle.fill" : r.status == .kept ? "equal.circle" : "xmark.octagon.fill")
                            .foregroundStyle(r.status == .ok ? .green : r.status == .kept ? .secondary : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).lineLimit(1).truncationMode(.middle)
                            Text(r.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if let s = r.saved {
                            Text(String(format: "−%.0f %%", s * 100)).monospacedDigit()
                                .foregroundStyle(s > 0 ? .green : .orange)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 160)
        }
    }

    private var summaryLine: some View {
        let s = model.summary
        var parts = ["\(s.done + s.kept + s.failed) \(L.images)",
                     "\(formatBytes(s.before)) → \(formatBytes(s.after))"]
        if s.kept > 0 { parts.append("\(s.kept) \(L.kept)") }
        if s.failed > 0 { parts.append("\(s.failed) \(L.failed)") }
        return HStack(spacing: 8) {
            Text(parts.joined(separator: " · "))
            if s.before > 0 {
                Text(String(format: "−%.0f %%", s.savedFraction * 100))
                    .font(.headline).foregroundStyle(.green)
            }
        }
    }
}
