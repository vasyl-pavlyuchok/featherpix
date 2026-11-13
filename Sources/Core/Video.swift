import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Options

public enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264, hevc, vp9
    public var id: String { rawValue }
    public var label: String {
        switch self { case .h264: return "MP4 · H.264"; case .hevc: return "MP4 · HEVC"; case .vp9: return "WebM · VP9" }
    }
    /// HEVC and VP9 need roughly 55–60 % of the H.264 bitrate for the same look.
    var efficiency: Double {
        switch self { case .h264: return 1.0; case .hevc: return 0.6; case .vp9: return 0.55 }
    }
    var avCodec: AVVideoCodecType { self == .hevc ? .hevc : .h264 }
    public var fileExtension: String { self == .vp9 ? "webm" : "mp4" }
    /// H.264 and HEVC come from macOS (VideoToolbox); VP9 from the bundled LGPL ffmpeg.
    public var usesFFmpeg: Bool { self == .vp9 }
}

public enum VideoPreset: String, CaseIterable, Identifiable, Sendable {
    /// Plays everywhere, keeps audio, ≤ 1920 px.
    case web
    /// Silent hero loop for a web page, ≤ 1280 px, + poster image + <video> snippet.
    case loop
    /// Keeps size and audio, generous bitrate.
    case max
    public var id: String { rawValue }
    /// Bits per pixel per frame for H.264. Tuned for the web; see docs/benchmark.md.
    var bitsPerPixel: Double {
        switch self { case .web: return 0.075; case .loop: return 0.05; case .max: return 0.16 }
    }
    public var defaultMaxWidth: Int? { switch self { case .web: return 1920; case .loop: return 1280; case .max: return nil } }
    public var keepsAudio: Bool { self != .loop }
    public var makesPoster: Bool { self == .loop }
    /// VP9 constant-quality level (lower = better); the bitrate acts as a ceiling.
    var vp9CRF: Int { switch self { case .web: return 33; case .loop: return 37; case .max: return 26 } }
}

public struct VideoOptions: Sendable {
    public var preset: VideoPreset = .web
    public var codec: VideoCodec = .h264
    /// nil = preset default; 0 = keep original width.
    public var maxWidth: Int? = nil
    /// nil = preset default.
    public var keepAudio: Bool? = nil
    /// Quality multiplier on the preset bitrate (0.5 … 2.0).
    public var qualityFactor: Double = 1.0
    public var skipIfLarger: Bool = true
    public var outputDirectory: URL? = nil
    /// WebM only: also write an H.264 MP4 for browsers without VP9 (older iPhones).
    public var mp4Fallback: Bool = true
    public init() {}

    var effectiveMaxWidth: Int? {
        if let w = maxWidth { return w > 0 ? w : nil }
        return preset.defaultMaxWidth
    }
    var effectiveAudio: Bool { keepAudio ?? preset.keepsAudio }
}

public let supportedVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]

public func isVideoFile(_ u: URL) -> Bool { supportedVideoExtensions.contains(u.pathExtension.lowercased()) }

// MARK: - Results

public struct VideoResult: Sendable {
    public enum Kind: Sendable {
        case done(before: Int64, after: Int64)
        case notSmaller(before: Int64, after: Int64)
        case failed(String)
        case cancelled
    }
    public let input: URL
    public let output: URL?
    public let poster: URL?
    public let kind: Kind
    public let info: String
    /// Ready-to-paste <video> tag (loop preset).
    public let htmlSnippet: String?
    /// WebM only: the H.264 MP4 written next to it for older browsers.
    public var fallback: URL? = nil
}

// MARK: - Engine

public final class VideoEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var process: Process?
    public init() {}

    public func cancel() {
        lock.lock(); cancelled = true; let r = reader; let w = writer; let p = process; lock.unlock()
        r?.cancelReading(); w?.cancelWriting()
        if let p { Self.stop(p) }
    }

    /// SIGTERM, then SIGKILL if ffmpeg is still alive 3 s later (a stuck decoder ignores one SIGTERM).
    static func stop(_ p: Process) {
        guard p.isRunning else { return }
        p.terminate()
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { kill(pid, SIGKILL) } }
    }

    /// Every ffmpeg still running, so the app can stop them when it quits.
    private static let runningLock = NSLock()
    nonisolated(unsafe) private static var running: [ObjectIdentifier: Process] = [:]
    public static func stopAll() {
        runningLock.lock(); let all = Array(running.values); runningLock.unlock()
        for p in all where p.isRunning { p.terminate(); kill(p.processIdentifier, SIGKILL) }
    }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    /// Output next to the input (or in outputDirectory): "<name>-web.mp4", "<name>-loop.mp4"…
    public static func outputURL(for input: URL, options o: VideoOptions, ext: String = "mp4", suffix: String? = nil) -> URL {
        let dir = o.outputDirectory ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent + "-" + (suffix ?? o.preset.rawValue)
        var n = 1
        while true {
            let name = n == 1 ? "\(base).\(ext)" : "\(base) (\(n)).\(ext)"
            let u = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }

    /// Encode one video. `progress` gets 0…1 from the worker thread.
    public func encode(_ input: URL, options o: VideoOptions, progress: @escaping @Sendable (Double) -> Void = { _ in }) -> VideoResult {
        let fm = FileManager.default
        let before = (try? fm.attributesOfItem(atPath: input.path)[.size] as? Int64) ?? 0
        let out = Self.outputURL(for: input, options: o, ext: o.codec.fileExtension)
        let wantsFallback = o.codec == .vp9 && o.mp4Fallback
        var tmps: [URL] = []
        defer { for t in tmps { try? fm.removeItem(at: t) } }
        func temp(_ ext: String) -> URL {
            let u = out.deletingLastPathComponent().appendingPathComponent(".featherpix-\(UUID().uuidString).\(ext)")
            tmps.append(u); return u
        }
        func cancelledResult() -> VideoResult { VideoResult(input: input, output: nil, poster: nil, kind: .cancelled, info: "", htmlSnippet: nil) }
        do {
            if let d = o.outputDirectory { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
            let tmp = temp(o.codec.fileExtension)
            let share = wantsFallback ? 0.7 : 1.0
            let info: String
            if o.codec.usesFFmpeg {
                info = try transcodeWebM(input, to: tmp, options: o, progress: { progress($0 * share) })
            } else {
                info = try transcode(input, to: tmp, options: o, progress: progress)
            }
            if isCancelled { return cancelledResult() }
            let after = (try fm.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
            guard after > 0 else { throw EncodeError("the encoder produced an empty file") }
            // Make sure what we wrote is a playable video before keeping it.
            if o.codec.usesFFmpeg { try verifyWebM(tmp) } else { try Self.verifyPlayable(tmp) }
            if o.skipIfLarger && after >= before {
                return VideoResult(input: input, output: nil, poster: nil, kind: .notSmaller(before: before, after: after), info: info, htmlSnippet: nil)
            }
            // WebM: the MP4 fallback for browsers without VP9, written before anything is moved into place.
            var fallbackTmp: URL? = nil
            if wantsFallback {
                var fo = o; fo.codec = .h264
                let t2 = temp("mp4")
                _ = try transcode(input, to: t2, options: fo, progress: { progress(share + $0 * (1 - share)) })
                if isCancelled { return cancelledResult() }
                try Self.verifyPlayable(t2)
                fallbackTmp = t2
            }
            try fm.moveItem(at: tmp, to: out)
            var fallback: URL? = nil
            if let t2 = fallbackTmp {
                let fb = Self.outputURL(for: input, options: o, ext: "mp4")
                try fm.moveItem(at: t2, to: fb)
                fallback = fb
            }
            var poster: URL? = nil
            var html: String? = nil
            if o.preset.makesPoster {
                // AVFoundation cannot read WebM: take the frame from the MP4 fallback or the original.
                let frameSource = o.codec.usesFFmpeg ? (fallback ?? input) : out
                poster = try? Self.makePoster(from: frameSource, near: input, options: o)
                html = Self.snippet(sources: [out] + (fallback.map { [$0] } ?? []), poster: poster)
            }
            var r = VideoResult(input: input, output: out, poster: poster, kind: .done(before: before, after: after), info: info, htmlSnippet: html)
            r.fallback = fallback
            return r
        } catch {
            if isCancelled { return cancelledResult() }
            return VideoResult(input: input, output: nil, poster: nil, kind: .failed("\(error)"), info: "", htmlSnippet: nil)
        }
    }

    // MARK: transcode

    private func transcode(_ input: URL, to output: URL, options o: VideoOptions, progress: @escaping @Sendable (Double) -> Void) throws -> String {
        let asset = AVURLAsset(url: input, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let vTrack = asset.tracks(withMediaType: .video).first else { throw EncodeError("no video track") }
        let aTrack = o.effectiveAudio ? asset.tracks(withMediaType: .audio).first : nil
        let duration = asset.duration.seconds
        guard duration.isFinite, duration > 0 else { throw EncodeError("cannot read the video length") }

        // Size in the track's natural orientation; the rotation is kept as a transform.
        let natural = vTrack.naturalSize
        let t = vTrack.preferredTransform
        let rotated = abs(t.b) == 1 && abs(t.c) == 1
        let displayW = Int(rotated ? natural.height : natural.width)
        var scale = 1.0
        if let mw = o.effectiveMaxWidth, displayW > mw { scale = Double(mw) / Double(displayW) }
        func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        let w = even(Double(natural.width) * scale), h = even(Double(natural.height) * scale)
        if w * h > maxInputPixels { throw EncodeError("video too large") }

        var fps = Double(vTrack.nominalFrameRate)
        if !fps.isFinite || fps <= 0 { fps = 30 }
        var bitrate = o.preset.bitsPerPixel * o.codec.efficiency * max(0.5, min(2.0, o.qualityFactor)) * Double(w * h) * fps
        // Never ask for more than the source carries: that only makes the file bigger.
        let srcRate = Double(vTrack.estimatedDataRate)
        if srcRate > 0 { bitrate = min(bitrate, srcRate * 0.95) }
        bitrate = max(150_000, bitrate)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        lock.lock(); self.reader = reader; self.writer = writer; lock.unlock()
        defer { lock.lock(); self.reader = nil; self.writer = nil; lock.unlock() }

        let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { throw EncodeError("cannot read the video track") }
        reader.add(vOut)

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: Int(bitrate),
            AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
            AVVideoMaxKeyFrameIntervalKey: Int((fps * 2).rounded()),
        ]
        if o.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        }
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: o.codec.avCodec,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: compression,
        ])
        vIn.transform = t
        vIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn) else { throw EncodeError("this Mac cannot encode \(o.codec.label)") }
        writer.add(vIn)

        var aOut: AVAssetReaderTrackOutput? = nil
        var aIn: AVAssetWriterInput? = nil
        if let a = aTrack {
            let ro = AVAssetReaderTrackOutput(track: a, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            let wi = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: o.preset == .max ? 192_000 : 128_000,
            ])
            wi.expectsMediaDataInRealTime = false
            if reader.canAdd(ro) && writer.canAdd(wi) { reader.add(ro); writer.add(wi); aOut = ro; aIn = wi }
        }

        // "Software: Featherpix" in the file's metadata (the author line is the app's, not the user's).
        let sw = AVMutableMetadataItem()
        sw.keySpace = .common; sw.key = AVMetadataKey.commonKeySoftware as NSString
        sw.value = "Featherpix \(Credits.version)" as NSString
        writer.metadata = [sw]
        writer.shouldOptimizeForNetworkUse = true   // moov atom first: starts playing before it finishes loading

        guard reader.startReading() else { throw EncodeError(reader.error?.localizedDescription ?? "cannot start reading") }
        guard writer.startWriting() else { throw EncodeError(writer.error?.localizedDescription ?? "cannot start writing") }
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        let pump: (AVAssetReaderTrackOutput, AVAssetWriterInput, String, Bool) -> Void = { out, inp, label, isVideo in
            group.enter()
            let q = DispatchQueue(label: "featherpix.\(label)")
            var finished = false
            inp.requestMediaDataWhenReady(on: q) { [weak self] in
                while inp.isReadyForMoreMediaData && !finished {
                    if self?.isCancelled == true || reader.status != .reading {
                        finished = true; inp.markAsFinished(); group.leave(); return
                    }
                    guard let buf = out.copyNextSampleBuffer() else {
                        finished = true; inp.markAsFinished(); group.leave(); return
                    }
                    if isVideo {
                        let pts = CMSampleBufferGetPresentationTimeStamp(buf).seconds
                        if pts.isFinite { progress(min(1, max(0, pts / duration))) }
                    }
                    if !inp.append(buf) {
                        finished = true; inp.markAsFinished(); group.leave(); return
                    }
                }
            }
        }
        pump(vOut, vIn, "video", true)
        if let ao = aOut, let ai = aIn { pump(ao, ai, "audio", false) }
        group.wait()

        if isCancelled { writer.cancelWriting(); throw EncodeError("cancelled") }
        if reader.status == .failed { writer.cancelWriting(); throw EncodeError(reader.error?.localizedDescription ?? "read failed") }
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw EncodeError(writer.error?.localizedDescription ?? "write failed") }
        progress(1)

        let outW = rotated ? h : w, outH = rotated ? w : h
        let audioNote = aIn != nil ? "audio AAC" : "sin audio"
        return "\(outW)×\(outH) · \(Int(fps.rounded())) fps · \(o.codec.label) · \(Int(bitrate / 1000)) kb/s · \(audioNote)"
    }

    // MARK: WebM (VP9 + Opus) through the bundled LGPL ffmpeg

    /// Plan sizes with AVFoundation (same rules as MP4), then let ffmpeg do the work.
    /// Hardening (council PR117): no stdin, only file/pipe protocols, input forced to the MOV demuxer,
    /// paths passed as "file:" URLs so a name can never be read as an option or another protocol.
    private func transcodeWebM(_ input: URL, to output: URL, options o: VideoOptions, progress: @escaping @Sendable (Double) -> Void) throws -> String {
        let asset = AVURLAsset(url: input, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let vTrack = asset.tracks(withMediaType: .video).first else { throw EncodeError("no video track") }
        let hasAudio = o.effectiveAudio && !asset.tracks(withMediaType: .audio).isEmpty
        let duration = asset.duration.seconds
        guard duration.isFinite, duration > 0 else { throw EncodeError("cannot read the video length") }

        // ffmpeg applies the rotation itself, so plan in display orientation.
        let natural = vTrack.naturalSize
        let t = vTrack.preferredTransform
        let rotated = abs(t.b) == 1 && abs(t.c) == 1
        let dispW = Double(rotated ? natural.height : natural.width)
        let dispH = Double(rotated ? natural.width : natural.height)
        var scale = 1.0
        if let mw = o.effectiveMaxWidth, Int(dispW) > mw { scale = Double(mw) / dispW }
        func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        let w = even(dispW * scale), h = even(dispH * scale)
        if w * h > maxInputPixels { throw EncodeError("video too large") }

        var fps = Double(vTrack.nominalFrameRate)
        if !fps.isFinite || fps <= 0 { fps = 30 }
        let q = max(0.5, min(2.0, o.qualityFactor))
        var bitrate = o.preset.bitsPerPixel * o.codec.efficiency * q * Double(w * h) * fps
        let srcRate = Double(vTrack.estimatedDataRate)
        if srcRate > 0 { bitrate = min(bitrate, srcRate * 0.95) }
        bitrate = max(100_000, bitrate)
        let crf = max(15, min(50, o.preset.vp9CRF - Int((log2(q) * 6).rounded())))
        // Hard limits so a hostile file cannot run forever or fill the disk.
        let inputSize = (try? FileManager.default.attributesOfItem(atPath: input.path)[.size] as? Int64) ?? 0
        let maxOut = max(inputSize * 2, 50_000_000)

        var args = ["-nostdin", "-hide_banner", "-loglevel", "error",
                    "-protocol_whitelist", "file,pipe", "-max_pixels", "\(maxInputPixels)",
                    "-f", "mov", "-i", "file:" + input.path,
                    "-map", "0:v:0"]
        if hasAudio { args += ["-map", "0:a:0"] }
        args += ["-vf", "scale=\(w):\(h):flags=lanczos,setsar=1,format=yuv420p",
                 "-c:v", "libvpx-vp9", "-crf", "\(crf)", "-b:v", "\(Int(bitrate / 1000))k",
                 "-deadline", "good", "-cpu-used", "2", "-row-mt", "1", "-tile-columns", "2",
                 "-auto-alt-ref", "1", "-lag-in-frames", "25", "-g", "\(Int((fps * 4).rounded()))"]
        args += hasAudio ? ["-c:a", "libopus", "-b:a", o.preset == .max ? "160k" : "96k", "-ac", "2"] : ["-an"]
        args += ["-map_metadata", "-1", "-metadata", "comment=Featherpix \(Credits.version)",
                 "-t", String(format: "%.3f", duration + 1), "-fs", "\(maxOut)",
                 "-progress", "pipe:1", "-nostats", "-f", "webm", "file:" + output.path]
        try runFFmpeg(args, timeout: duration * 40 + 300) { line in
            if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) {
                progress(min(1, max(0, us / 1_000_000 / duration)))
            }
        }
        if isCancelled { throw EncodeError("cancelled") }
        progress(1)
        let audioNote = hasAudio ? "audio Opus" : "sin audio"
        return "\(w)×\(h) · \(Int(fps.rounded())) fps · \(o.codec.label) · ≤\(Int(bitrate / 1000)) kb/s · \(audioNote)"
    }

    /// Decode the whole WebM once: proves it is complete and playable.
    private func verifyWebM(_ url: URL) throws {
        try runFFmpeg(["-nostdin", "-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file,pipe",
                       "-f", "matroska", "-i", "file:" + url.path,
                       "-c:v", "wrapped_avframe", "-c:a", "pcm_s16le", "-f", "null", "-"], timeout: 600, onLine: { _ in })
    }

    /// Runs the bundled ffmpeg with an argument array (never a shell); stdout lines go to `onLine`.
    private func runFFmpeg(_ args: [String], timeout: TimeInterval, onLine: @escaping (String) -> Void) throws {
        let p = Process()
        p.executableURL = try Tools.url("ffmpeg")
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        let errBox = OutputBox(), outBox = OutputBox()
        err.fileHandleForReading.readabilityHandler = { h in errBox.append(h.availableData, keepLast: 8_000) }
        out.fileHandleForReading.readabilityHandler = { h in
            for line in outBox.lines(from: h.availableData) { onLine(line) }
        }
        lock.lock()
        if cancelled { lock.unlock(); throw EncodeError("cancelled") }
        process = p
        lock.unlock()
        defer { lock.lock(); process = nil; lock.unlock() }
        try p.run()
        let key = ObjectIdentifier(p)
        Self.runningLock.lock(); Self.running[key] = p; Self.runningLock.unlock()
        defer { Self.runningLock.lock(); Self.running[key] = nil; Self.runningLock.unlock() }
        // A cancel that arrived between `process = p` and `run()` found nothing running: honour it now.
        if isCancelled { Self.stop(p) }
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while p.isRunning {
            if !timedOut && Date() > deadline { timedOut = true; Self.stop(p) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        if isCancelled { throw EncodeError("cancelled") }
        if timedOut { throw EncodeError("ffmpeg took too long and was stopped") }
        if p.terminationStatus != 0 {
            let last = errBox.text.split(separator: "\n").last.map(String.init) ?? "exit \(p.terminationStatus)"
            throw EncodeError("ffmpeg failed: \(last)")
        }
    }

    // MARK: checks and extras

    static func verifyPlayable(_ url: URL) throws {
        let a = AVURLAsset(url: url)
        guard let v = a.tracks(withMediaType: .video).first, a.duration.seconds > 0, v.naturalSize.width > 0
        else { throw EncodeError("the result is not a playable video") }
    }

    /// First frame as WebP, using the same encoder as the Photos tab.
    static func makePoster(from video: URL, near input: URL, options vo: VideoOptions) throws -> URL {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        gen.appliesPreferredTrackTransform = true
        if let mw = vo.effectiveMaxWidth { gen.maximumSize = CGSize(width: mw, height: mw * 4) }
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        let img = try gen.copyCGImage(at: .zero, actualTime: nil)
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("featherpix-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }
        let png = tmpDir.appendingPathComponent("poster.png")
        try Pipeline.writeImageIO(img, type: .png, to: png, quality: nil)
        let dest = outputURL(for: input, options: vo, ext: "webp", suffix: "poster")
        var io = Options(); io.format = .webp; io.quality = 72
        _ = try Pipeline.encode(png, to: dest, options: io)
        return dest
    }

    /// The best format goes first; the browser takes the first one it can play.
    static func snippet(sources: [URL], poster: URL?) -> String {
        let p = poster.map { " poster=\"\(attr($0.lastPathComponent))\"" } ?? ""
        let lines = sources.map { u -> String in
            let type = u.pathExtension.lowercased() == "webm" ? "video/webm" : "video/mp4"
            return "  <source src=\"\(attr(u.lastPathComponent))\" type=\"\(type)\">"
        }
        return (["<video autoplay muted loop playsinline preload=\"metadata\"\(p)>"] + lines + ["</video>"]).joined(separator: "\n")
    }
}

/// A file name made safe for an HTML attribute that holds a URL: percent-encoded, then HTML-escaped.
/// (A video called `x" onerror="…` must not become code on the user's web page.)
func attr(_ name: String) -> String {
    var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "\"'<>&?#%")
    let enc = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    return enc.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

/// Thread-safe accumulator for a child process's output.
final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var pending = ""
    func append(_ d: Data, keepLast: Int) {
        lock.lock(); data.append(d); if data.count > keepLast { data = data.suffix(keepLast) }; lock.unlock()
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    func lines(from d: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pending += String(decoding: d, as: UTF8.self)
        var parts = pending.components(separatedBy: "\n")
        pending = parts.removeLast()
        return parts
    }
}
