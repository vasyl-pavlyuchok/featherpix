import Foundation

let usage = """
featherpix-cli — make images much lighter, keep them looking good.

Usage: featherpix-cli [image] [options] <file-or-folder>...
       featherpix-cli video [video options] <video>...

  -f, --format webp|avif|jpeg   output format (default webp)
  -p, --preset web|smallest|compatible
                                web = webp 75 ≤1920px · smallest = avif 40 ≤1200px · compatible = jpeg 75 ≤1920px
  -q, --quality 1-100           quality (default: webp 75, avif 45, jpeg 75)
  -w, --max-width N             scale down anything wider than N px (never up)
  -o, --output DIR              write results here instead of next to the originals
  -j, --jobs N                  images in parallel (default: automatic)
      --keep-larger             keep the result even if it is not smaller
      --formats                 list supported input and output formats
      --about                   who made Featherpix and how to reach him
  -h, --help

Video options (MP4, MOV, M4V in · MP4 out):
  -p, --preset web|loop|max     web = H.264 ≤1920px with audio · loop = silent hero loop ≤1280px
                                + poster .webp + <video> snippet · max = original size, high bitrate
  -c, --codec h264|hevc         default h264 (plays everywhere); hevc is smaller, newer browsers
  -w, --max-width N             0 keeps the original width
      --no-audio / --audio      override the preset
  -q, --quality 50-200          % of the preset bitrate (default 100)
  -o, --output DIR              write results here instead of next to the originals
      --keep-larger             keep the result even if it is not smaller

Files are written next to the originals; a folder is mirrored into "<folder> (Featherpix)".
Originals are never modified. Exit code 1 if any image failed.
"""

var o = Options()
var qualitySet = false
var inputs: [URL] = []
var args = Array(CommandLine.arguments.dropFirst())
if args.first == "image" { args.removeFirst() }
if args.first == "video" {
    args.removeFirst()
    runVideo(args)
}
// `featherpix-cli formats` / `featherpix-cli about` only as the sole argument, so a file with that name still works.
if args.count == 1, ["formats", "about"].contains(args[0]), !FileManager.default.fileExists(atPath: args[0]) { args[0] = "--" + args[0] }
func die(_ m: String) -> Never { FileHandle.standardError.write(Data("error: \(m)\n".utf8)); exit(2) }
func next(_ flag: String) -> String { guard !args.isEmpty else { die("\(flag) needs a value") }; return args.removeFirst() }

while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "-h", "--help": print(usage); exit(0)
    case "--formats":
        print("input:  " + FormatsInfo.imageInputs.joined(separator: ", "))
        print("output: " + FormatsInfo.imageOutputs.joined(separator: ", "))
        exit(0)
    case "--about":
        print("Featherpix \(Credits.version) — designed by \(Credits.author)")
        print("Need a custom app for your business? \(Credits.email) (subject: \(Credits.mailSubject))")
        print(Credits.repo)
        exit(0)
    case "-f", "--format":
        guard let f = OutputFormat(rawValue: next(a).lowercased().replacingOccurrences(of: "jpg", with: "jpeg")) else { die("unknown format") }
        o.format = f
    case "-p", "--preset":
        let name = next(a)
        guard let p = Preset.all.first(where: { $0.id == name }) else { die("unknown preset \(name)") }
        o.format = p.format; o.quality = p.quality; o.maxWidth = p.maxWidth; qualitySet = true
    case "-q", "--quality":
        guard let q = Int(next(a)), (1...100).contains(q) else { die("quality must be 1-100") }
        o.quality = q; qualitySet = true
    case "-w", "--max-width":
        guard let w = Int(next(a)), w > 0 else { die("max width must be a positive number") }
        o.maxWidth = w
    case "-o", "--output": o.outputDirectory = URL(fileURLWithPath: next(a))
    case "-j", "--jobs":
        guard let j = Int(next(a)), j > 0 else { die("jobs must be a positive number") }
        o.jobs = j
    case "--keep-larger": o.skipIfLarger = false
    case "--": inputs += args.map { URL(fileURLWithPath: $0) }; args = []
    default:
        if a.hasPrefix("-") { die("unknown option \(a)") }
        inputs.append(URL(fileURLWithPath: a))
    }
}
if !qualitySet { o.quality = o.format.defaultQuality }
if inputs.isEmpty { print(usage); exit(2) }

let (jobs, skipped) = Planner.plan(inputs, options: o)
for s in skipped { FileHandle.standardError.write(Data("skip: \(s)\n".utf8)) }
if jobs.isEmpty { die("no supported images found") }

let lock = NSLock()
var summary = Summary()
let start = Date()
Runner().run(jobs, options: o) { r in
    lock.lock(); defer { lock.unlock() }
    summary.add(r)
    switch r.outcome {
    case .done(let b, let a, let w):
        let pct = b > 0 ? Int((1 - Double(a) / Double(b)) * 100) : 0
        print("ok    \(r.job.displayName)  \(formatBytes(b)) → \(formatBytes(a))  (-\(pct)%)" + (w.isEmpty ? "" : "  [\(w.joined(separator: "; "))]"))
    case .keptOriginal(let b, let copied):
        print("kept  \(r.job.displayName)  \(formatBytes(b))  (not smaller\(copied ? ", original copied" : ""))")
    case .failed(let m):
        print("FAIL  \(r.job.displayName)  \(m)")
    }
}
let secs = Date().timeIntervalSince(start)
print(String(format: "\n%d done, %d kept, %d failed · %@ → %@ (-%.0f%%) · %.1fs",
             summary.done, summary.kept, summary.failed, formatBytes(summary.before), formatBytes(summary.after),
             summary.savedFraction * 100, secs))
exit(summary.failed > 0 ? 1 : 0)


// MARK: - video

func runVideo(_ argv: [String]) -> Never {
    var a = argv
    var vo = VideoOptions()
    var files: [URL] = []
    func val(_ f: String) -> String { guard !a.isEmpty else { die("\(f) needs a value") }; return a.removeFirst() }
    while !a.isEmpty {
        let x = a.removeFirst()
        switch x {
        case "-h", "--help": print(usage); exit(0)
        case "-p", "--preset":
            guard let p = VideoPreset(rawValue: val(x)) else { die("preset must be web, loop or max") }
            vo.preset = p
        case "-c", "--codec":
            guard let c = VideoCodec(rawValue: val(x).lowercased().replacingOccurrences(of: "h265", with: "hevc")) else { die("codec must be h264 or hevc") }
            vo.codec = c
        case "-w", "--max-width":
            guard let w = Int(val(x)), w >= 0 else { die("max width must be 0 or a positive number") }
            vo.maxWidth = w
        case "--no-audio": vo.keepAudio = false
        case "--audio": vo.keepAudio = true
        case "-q", "--quality":
            guard let q = Int(val(x)), (50...200).contains(q) else { die("video quality must be 50-200") }
            vo.qualityFactor = Double(q) / 100
        case "-o", "--output": vo.outputDirectory = URL(fileURLWithPath: val(x))
        case "--keep-larger": vo.skipIfLarger = false
        case "--": files += a.map { URL(fileURLWithPath: $0) }; a = []
        default:
            if x.hasPrefix("-") { die("unknown option \(x)") }
            files.append(URL(fileURLWithPath: x))
        }
    }
    let vids = files.filter { isVideoFile($0) && FileManager.default.fileExists(atPath: $0.path) }
    for f in files where !vids.contains(f) { FileHandle.standardError.write(Data("skip: \(f.lastPathComponent): not a supported video (MP4, MOV, M4V)\n".utf8)) }
    if vids.isEmpty { die("no supported videos found") }
    var failed = 0
    for v in vids {
        let r = VideoEngine().encode(v, options: vo)
        switch r.kind {
        case .done(let b, let af):
            let pct = b > 0 ? Int((1 - Double(af) / Double(b)) * 100) : 0
            print("ok    \(v.lastPathComponent)  \(formatBytes(b)) → \(formatBytes(af))  (-\(pct)%)  \(r.info)")
            if let o = r.output { print("      → \(o.path)") }
            if let p = r.poster { print("      → \(p.path)") }
            if let h = r.htmlSnippet { print(h) }
        case .notSmaller(let b, let af):
            print("kept  \(v.lastPathComponent)  \(formatBytes(b))  (result \(formatBytes(af)) was not smaller; nothing written)")
        case .failed(let m): failed += 1; print("FAIL  \(v.lastPathComponent)  \(m)")
        case .cancelled: failed += 1; print("CANCELLED  \(v.lastPathComponent)")
        }
    }
    exit(failed > 0 ? 1 : 0)
}
