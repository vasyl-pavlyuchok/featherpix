import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Options

public enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264, hevc
    public var id: String { rawValue }
    public var label: String { self == .h264 ? "MP4 · H.264" : "MP4 · HEVC" }
    /// HEVC needs roughly 60 % of the H.264 bitrate for the same look.
    var efficiency: Double { self == .h264 ? 1.0 : 0.6 }
    var avCodec: AVVideoCodecType { self == .h264 ? .h264 : .hevc }
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
}

// MARK: - Engine

public final class VideoEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    public init() {}

    public func cancel() {
        lock.lock(); cancelled = true; let r = reader; let w = writer; lock.unlock()
        r?.cancelReading(); w?.cancelWriting()
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
        let out = Self.outputURL(for: input, options: o)
        do {
            if let d = o.outputDirectory { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
            let tmp = out.deletingLastPathComponent().appendingPathComponent(".featherpix-\(UUID().uuidString).mp4")
            defer { try? fm.removeItem(at: tmp) }
            let info = try transcode(input, to: tmp, options: o, progress: progress)
            if isCancelled { return VideoResult(input: input, output: nil, poster: nil, kind: .cancelled, info: "", htmlSnippet: nil) }
            let after = (try fm.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
            guard after > 0 else { throw EncodeError("the encoder produced an empty file") }
            // Make sure what we wrote is a playable video before keeping it.
            try Self.verifyPlayable(tmp)
            if o.skipIfLarger && after >= before {
                return VideoResult(input: input, output: nil, poster: nil, kind: .notSmaller(before: before, after: after), info: info, htmlSnippet: nil)
            }
            try fm.moveItem(at: tmp, to: out)
            var poster: URL? = nil
            var html: String? = nil
            if o.preset.makesPoster {
                poster = try? Self.makePoster(from: out, near: input, options: o)
                html = Self.snippet(video: out, poster: poster)
            }
            return VideoResult(input: input, output: out, poster: poster, kind: .done(before: before, after: after), info: info, htmlSnippet: html)
        } catch {
            if isCancelled { return VideoResult(input: input, output: nil, poster: nil, kind: .cancelled, info: "", htmlSnippet: nil) }
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

    static func snippet(video: URL, poster: URL?) -> String {
        let p = poster.map { " poster=\"\($0.lastPathComponent)\"" } ?? ""
        return """
        <video autoplay muted loop playsinline preload="metadata"\(p)>
          <source src="\(video.lastPathComponent)" type="video/mp4">
        </video>
        """
    }
}
