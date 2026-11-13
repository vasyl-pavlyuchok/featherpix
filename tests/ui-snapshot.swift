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
        let videoTab = CommandLine.arguments.contains("--video")
        UserDefaults.standard.set(videoTab ? "videos" : "photos", forKey: "tab")
        if videoTab && CommandLine.arguments.contains("--results") && !CommandLine.arguments.contains("--webm") {
            let v = VideoModel.shared
            v.rows = [VideoRow(name: "portada-gemini.mp4", progress: 1, state: .ok,
                               detail: "4,1 MB → 612 KB · 1280×720 · 24 fps · MP4 · H.264 · 480 kb/s · sin audio", saved: 0.85)]
            v.before = 4_100_000; v.after = 612_000
            v.snippet = "<video autoplay muted loop playsinline preload=\"metadata\" poster=\"portada-gemini-poster.webp\">\n  <source src=\"portada-gemini-loop.mp4\" type=\"video/mp4\">\n</video>"
            v.lastOutput = URL(fileURLWithPath: "/tmp")
        }
        // Snapshots must not inherit settings from a previous run.
        UserDefaults.standard.set(VideoCodec.h264.rawValue, forKey: "video.codec")
        UserDefaults.standard.set(VideoPreset.web.rawValue, forKey: "video.preset")
        if videoTab && CommandLine.arguments.contains("--webm") {
            UserDefaults.standard.set(VideoCodec.vp9.rawValue, forKey: "video.codec")
            UserDefaults.standard.set(VideoPreset.loop.rawValue, forKey: "video.preset")
            if CommandLine.arguments.contains("--results") {
                let v = VideoModel.shared
                v.rows = [VideoRow(name: "portada-gemini.mp4", progress: 1, state: .ok,
                                   detail: "4,1 MB → 164 KB · 1280×720 · 24 fps · WebM · VP9 · sin audio · + MP4 de respaldo", saved: 0.96)]
                v.before = 4_100_000; v.after = 164_000
                v.snippet = "<video autoplay muted loop playsinline preload=\"metadata\" poster=\"portada-gemini-poster.webp\">\n  <source src=\"portada-gemini-loop.webm\" type=\"video/webm\">\n  <source src=\"portada-gemini-loop.mp4\" type=\"video/mp4\">\n</video>"
            }
        }
        if videoTab && CommandLine.arguments.contains("--working") {
            let v = VideoModel.shared
            v.running = true
            v.rows = [VideoRow(name: "portada-gemini.mp4", progress: 0.62, state: .working),
                      VideoRow(name: "reel-cliente.mov", state: .waiting)]
        }
        if !videoTab && CommandLine.arguments.contains("--results") {
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
        let host = NSHostingView(rootView: ContentView(model: m).frame(width: 680, height: 780).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSApp.appearance
        host.frame = NSRect(x: 0, y: 0, width: 680, height: 780)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))   // let the savings counter finish
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
