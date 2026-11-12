import Foundation

public struct Job: Sendable, Identifiable {
    public let id = UUID()
    public let input: URL
    public let output: URL
    /// Path shown to the user (relative to the dropped folder when there is one).
    public let displayName: String
    /// True when the job came from a dropped folder (output tree is mirrored).
    public let fromFolder: Bool
}

public enum Outcome: Sendable {
    case done(before: Int64, after: Int64, warnings: [String])
    /// The encoded file was not smaller: nothing written (single file) or original copied (folder).
    case keptOriginal(before: Int64, copied: Bool)
    case failed(String)
}

public struct JobResult: Sendable, Identifiable {
    public var id: UUID { job.id }
    public let job: Job
    public let outcome: Outcome

    public var bytesBefore: Int64 {
        switch outcome {
        case .done(let b, _, _), .keptOriginal(let b, _): return b
        case .failed: return 0
        }
    }
    public var bytesAfter: Int64 {
        switch outcome {
        case .done(_, let a, _): return a
        case .keptOriginal(let b, let copied): return copied ? b : 0
        case .failed: return 0
        }
    }
}

public struct Summary: Sendable {
    public var done = 0, kept = 0, failed = 0
    public var before: Int64 = 0, after: Int64 = 0
    public init() {}
    public mutating func add(_ r: JobResult) {
        switch r.outcome {
        case .done: done += 1; before += r.bytesBefore; after += r.bytesAfter
        case .keptOriginal(let b, let copied): kept += 1; if copied { before += b; after += b }
        case .failed: failed += 1
        }
    }
    public var savedFraction: Double { before > 0 ? 1 - Double(after) / Double(before) : 0 }
}

public enum Planner {
    /// Turn dropped files/folders into jobs.
    /// - A file  → output next to it (or in `outputDirectory`).
    /// - A folder → mirrored into a sibling folder "<name> (Featherpix)" (or inside `outputDirectory`).
    /// Originals are never overwritten; name clashes get " (2)", " (3)"…
    public static func plan(_ inputs: [URL], options o: Options) -> (jobs: [Job], skipped: [String]) {
        var jobs: [Job] = []
        var skipped: [String] = []
        var taken = Set<String>()
        let fm = FileManager.default

        func reserve(_ dir: URL, _ base: String) -> URL {
            let ext = o.format.fileExtension
            var n = 1
            while true {
                let name = n == 1 ? "\(base).\(ext)" : "\(base) (\(n)).\(ext)"
                let u = dir.appendingPathComponent(name)
                let key = u.standardizedFileURL.path.lowercased()   // APFS is case-insensitive by default
                if !taken.contains(key) && !fm.fileExists(atPath: u.path) {
                    taken.insert(key); return u
                }
                n += 1
            }
        }
        func isImage(_ u: URL) -> Bool { supportedInputExtensions.contains(u.pathExtension.lowercased()) }

        for raw in inputs {
            let input = raw.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: input.path, isDirectory: &isDir) else {
                skipped.append("\(input.lastPathComponent): not found"); continue
            }
            if !isDir.boolValue {
                guard isImage(input) else { skipped.append("\(input.lastPathComponent): not a supported image"); continue }
                let dir = o.outputDirectory ?? input.deletingLastPathComponent()
                jobs.append(Job(input: input, output: reserve(dir, input.deletingPathExtension().lastPathComponent),
                                displayName: input.lastPathComponent, fromFolder: false))
                continue
            }
            let root = input.resolvingSymlinksInPath()
            let outRoot: URL = {
                if let od = o.outputDirectory { return od.appendingPathComponent(root.lastPathComponent) }
                var u = root.deletingLastPathComponent().appendingPathComponent("\(root.lastPathComponent) (Featherpix)")
                var n = 2
                while fm.fileExists(atPath: u.path) {
                    u = root.deletingLastPathComponent().appendingPathComponent("\(root.lastPathComponent) (Featherpix \(n))")
                    n += 1
                }
                return u
            }()
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                skipped.append("\(root.lastPathComponent): cannot read folder"); continue
            }
            var files: [(URL, String)] = []
            for case let f as URL in en {
                let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if v?.isSymbolicLink == true {
                    // Don't follow links out of the dropped folder.
                    let target = f.resolvingSymlinksInPath().path
                    if !target.hasPrefix(root.path + "/") { skipped.append("\(f.lastPathComponent): link outside folder"); continue }
                } else if v?.isRegularFile != true { continue }
                // Relative path from the enumerator's own depth (robust to /var vs /private/var).
                if isImage(f) { files.append((f, f.pathComponents.suffix(en.level).joined(separator: "/"))) }
            }
            files.sort { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
            for (f, rel) in files {
                let relDir = (rel as NSString).deletingLastPathComponent
                let dir = relDir.isEmpty ? outRoot : outRoot.appendingPathComponent(relDir)
                jobs.append(Job(input: f, output: reserve(dir, f.deletingPathExtension().lastPathComponent),
                                displayName: "\(root.lastPathComponent)/\(rel)", fromFolder: true))
            }
        }
        return (jobs, skipped)
    }
}

public final class Runner: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    /// Process one job. Writes to a temp name and renames, so a crash never leaves a half file.
    public static func process(_ job: Job, options o: Options) -> JobResult {
        let fm = FileManager.default
        let before = (try? fm.attributesOfItem(atPath: job.input.path)[.size] as? Int64) ?? 0
        do {
            try fm.createDirectory(at: job.output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = job.output.deletingLastPathComponent()
                .appendingPathComponent(".featherpix-\(UUID().uuidString).\(o.format.fileExtension)")
            defer { try? fm.removeItem(at: tmp) }
            let warnings = try Pipeline.encode(job.input, to: tmp, options: o)
            let after = (try fm.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
            guard after > 0 else { throw EncodeError("encoder produced an empty file") }
            if o.skipIfLarger && after >= before {
                if job.fromFolder {
                    // Keep the folder complete: copy the original under its own extension.
                    let dest = job.output.deletingPathExtension().appendingPathExtension(job.input.pathExtension)
                    if !fm.fileExists(atPath: dest.path) { try fm.copyItem(at: job.input, to: dest) }
                    return JobResult(job: job, outcome: .keptOriginal(before: before, copied: true))
                }
                return JobResult(job: job, outcome: .keptOriginal(before: before, copied: false))
            }
            try fm.moveItem(at: tmp, to: job.output)
            return JobResult(job: job, outcome: .done(before: before, after: after, warnings: warnings))
        } catch {
            return JobResult(job: job, outcome: .failed("\(error)"))
        }
    }

    /// Run jobs in parallel; `onResult` is called from worker threads, once per job, in completion order.
    public func run(_ jobs: [Job], options o: Options, onResult: @escaping @Sendable (JobResult) -> Void) {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = o.effectiveJobs
        for job in jobs {
            q.addOperation { [self] in
                if self.isCancelled { onResult(JobResult(job: job, outcome: .failed("cancelled"))); return }
                onResult(Runner.process(job, options: o))
            }
        }
        q.waitUntilAllOperationsAreFinished()
    }
}

public func formatBytes(_ b: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
}
