// Renders ContentView off-screen to PNG (no screen-recording permission needed).
// Build: swiftc -D UI_SNAPSHOT -parse-as-library Sources/Core/*.swift Sources/App/*.swift tests/ui-snapshot.swift -o /tmp/snap
import SwiftUI
import AppKit

@main
struct Snap {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ui.png"
        let dark = CommandLine.arguments.contains("--dark")
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let m = AppModel.shared
        if CommandLine.arguments.contains("--results") {
            m.total = 325; m.finished = 325
            var s = Summary()
            for i in 0..<3 {
                let j = Job(input: URL(fileURLWithPath: "/x/a\(i).jpg"), output: URL(fileURLWithPath: "/x/a\(i).webp"),
                            displayName: "laminas/ejemplo-\(i).jpg", fromFolder: true)
                let r = JobResult(job: j, outcome: i == 2 ? .keptOriginal(before: 40_000, copied: true)
                                                         : .done(before: 120_000, after: 31_000, warnings: []))
                s.add(r); m.add(r)
            }
            m.summary = s
            m.lastOutput = URL(fileURLWithPath: "/tmp")
        }
        let host = NSHostingView(rootView: ContentView(model: m).frame(width: 600, height: m.total > 0 ? 760 : 520).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSApp.appearance
        host.frame = NSRect(x: 0, y: 0, width: 600, height: m.total > 0 ? 760 : 520)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
