import Foundation

let usage = """
featherpix-cli — make images much lighter, keep them looking good.

Usage: featherpix-cli [options] <file-or-folder>...

  -f, --format webp|avif|jpeg   output format (default webp)
  -p, --preset web|smallest|compatible
                                web = webp 75 ≤1920px · smallest = avif 40 ≤1200px · compatible = jpeg 75 ≤1920px
  -q, --quality 1-100           quality (default: webp 75, avif 45, jpeg 75)
  -w, --max-width N             scale down anything wider than N px (never up)
  -o, --output DIR              write results here instead of next to the originals
  -j, --jobs N                  images in parallel (default: automatic)
      --keep-larger             keep the result even if it is not smaller
  -h, --help

Files are written next to the originals; a folder is mirrored into "<folder> (Featherpix)".
Originals are never modified. Exit code 1 if any image failed.
"""

var o = Options()
var qualitySet = false
var inputs: [URL] = []
var args = Array(CommandLine.arguments.dropFirst())
func die(_ m: String) -> Never { FileHandle.standardError.write(Data("error: \(m)\n".utf8)); exit(2) }
func next(_ flag: String) -> String { guard !args.isEmpty else { die("\(flag) needs a value") }; return args.removeFirst() }

while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "-h", "--help": print(usage); exit(0)
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
