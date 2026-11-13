import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct EncodeError: Error, CustomStringConvertible {
    public let description: String
    init(_ d: String) { description = d }
}

/// Finds the bundled tools next to the real executable: Contents/Resources/bin (CLI) or ../Resources/bin (app).
/// Never argv[0], the current directory, an environment variable or $PATH: we only run what we ship.
public enum Tools {
    /// Absolute path of the running executable with symlinks resolved (a symlink in /usr/local/bin is followed).
    static var executable: URL? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(getpid(), &buf, UInt32(buf.count)) > 0 {
            let path = String(cString: buf)
            if path.hasPrefix("/") { return URL(fileURLWithPath: path).resolvingSymlinksInPath() }
        }
        return nil
    }
    public static func url(_ name: String) throws -> URL {
        guard let exe = executable else { throw EncodeError("cannot locate the Featherpix executable") }
        let dir = exe.deletingLastPathComponent()
        let candidates = [dir.appendingPathComponent(name),
                          dir.appendingPathComponent("../Resources/bin/\(name)").standardizedFileURL]
        for c in candidates where c.path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: c.path) { return c }
        throw EncodeError("encoder \(name) not found (looked in \(candidates.map(\.path)))")
    }
}

struct Decoded {
    let image: CGImage      // sRGB, already oriented and resized
    let hasAlpha: Bool
}

enum Pipeline {
    /// Decode, apply EXIF orientation, downscale to maxWidth (never upscale), convert to sRGB.
    static func decode(_ url: URL, maxWidth: Int?) throws -> Decoded {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw EncodeError("cannot open image") }
        guard CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? Int,
              let ph = props[kCGImagePropertyPixelHeight] as? Int, pw > 0, ph > 0
        else { throw EncodeError("not a readable image") }
        if pw * ph > maxInputPixels { throw EncodeError("image too large (\(pw)×\(ph) px)") }

        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        let (w, h) = orientation >= 5 ? (ph, pw) : (pw, ph)   // size as displayed
        var tw = w, th = h
        if let mw = maxWidth, mw > 0, w > mw {
            tw = mw
            th = max(1, Int((Double(h) * Double(mw) / Double(w)).rounded()))
        }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(tw, th),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary)
        else { throw EncodeError("decode failed") }

        let hasAlpha: Bool = {
            switch oriented.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: return false
            default: return true
            }
        }()
        // Redraw at the exact target size into sRGB (fixes colour for P3/Adobe RGB inputs,
        // because cwebp/avifenc ignore the embedded profile).
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: tw * 4,
                                  space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw EncodeError("cannot allocate \(tw)×\(th) canvas") }
        ctx.interpolationQuality = .high
        ctx.draw(oriented, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let out = ctx.makeImage() else { throw EncodeError("render failed") }
        return Decoded(image: out, hasAlpha: hasAlpha)
    }

    /// Straight (un-premultiplied) RGBA bytes, top row first.
    static func rgba(_ img: CGImage, flattenOnWhite: Bool) -> [UInt8] {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        buf.withUnsafeMutableBytes { p in
            let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            if flattenOnWhite {
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        if !flattenOnWhite {   // un-premultiply
            var i = 0
            while i < buf.count {
                let a = Int(buf[i + 3])
                if a > 0 && a < 255 {
                    for k in 0..<3 { buf[i + k] = UInt8(min(255, (Int(buf[i + k]) * 255 + a / 2) / a)) }
                }
                i += 4
            }
        }
        return buf
    }

    /// PAM (P7) is read natively by cwebp, so cwebp needs no PNG/JPEG libraries.
    static func writePAM(_ img: CGImage, alpha: Bool, to url: URL) throws {
        let w = img.width, h = img.height
        let px = rgba(img, flattenOnWhite: !alpha)
        var data = Data("P7\nWIDTH \(w)\nHEIGHT \(h)\nDEPTH \(alpha ? 4 : 3)\nMAXVAL 255\nTUPLTYPE \(alpha ? "RGB_ALPHA" : "RGB")\nENDHDR\n".utf8)
        if alpha {
            data.append(contentsOf: px)
        } else {
            var rgb = [UInt8](repeating: 0, count: w * h * 3)
            var j = 0
            for i in stride(from: 0, to: px.count, by: 4) {
                rgb[j] = px[i]; rgb[j + 1] = px[i + 1]; rgb[j + 2] = px[i + 2]; j += 3
            }
            data.append(contentsOf: rgb)
        }
        try data.write(to: url)
    }

    /// Binary PPM (P6), flattened on white; cjpeg reads it natively.
    static func writePPM(_ img: CGImage, to url: URL) throws {
        let w = img.width, h = img.height
        let px = rgba(img, flattenOnWhite: true)
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        var j = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            rgb[j] = px[i]; rgb[j + 1] = px[i + 1]; rgb[j + 2] = px[i + 2]; j += 3
        }
        var data = Data("P6\n\(w) \(h)\n255\n".utf8)
        data.append(contentsOf: rgb)
        try data.write(to: url)
    }

    static func writeImageIO(_ img: CGImage, type: UTType, to url: URL, quality: Double?) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw EncodeError("cannot create \(type.identifier) writer") }
        var props: [CFString: Any] = [:]
        if let q = quality { props[kCGImageDestinationLossyCompressionQuality] = q }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw EncodeError("write failed") }
    }

    /// Run a bundled encoder with an argument array (never through a shell).
    static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 300) throws {
        let p = Process()
        p.executableURL = try Tools.url(tool)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if Date() > deadline { p.terminate(); throw EncodeError("\(tool) timed out") }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            let last = msg.split(separator: "\n").last.map(String.init) ?? "exit \(p.terminationStatus)"
            throw EncodeError("\(tool) failed: \(last)")
        }
    }

    /// Encode `input` into `output` (a temp path the caller renames). Returns warnings.
    static func encode(_ input: URL, to output: URL, options o: Options) throws -> [String] {
        var warnings: [String] = []
        let d = try decode(input, maxWidth: o.maxWidth)
        let q = max(1, min(100, o.quality))
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("featherpix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        switch o.format {
        case .jpeg:
            if d.hasAlpha { warnings.append("transparency flattened on white (JPEG has no alpha)") }
            let ppm = tmpDir.appendingPathComponent("in.ppm")
            try writePPM(d.image, to: ppm)
            try run("cjpeg", ["-quality", String(q), "-optimize", "-progressive", "-outfile", output.path, ppm.path])
        case .webp:
            let pam = tmpDir.appendingPathComponent("in.pam")
            try writePAM(d.image, alpha: d.hasAlpha, to: pam)
            try run("cwebp", ["-quiet", "-q", String(q), "-m", "6", "-mt", "-sharp_yuv",
                              "-metadata", "none", pam.path, "-o", output.path])
        case .avif:
            let png = tmpDir.appendingPathComponent("in.png")
            try writeImageIO(d.image, type: .png, to: png, quality: nil)
            try run("avifenc", ["-q", String(q), "-s", "6", "-j", "all", "-y", "420",
                                "--ignore-exif", "--ignore-xmp", "--ignore-icc", png.path, output.path])
        }
        return warnings
    }
}
