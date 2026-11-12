import Foundation

public enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case webp, avif, jpeg
    public var id: String { rawValue }
    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    public var label: String { switch self { case .webp: return "WebP"; case .avif: return "AVIF"; case .jpeg: return "JPEG" } }
    /// Defaults measured on a real batch of 325 UI reference images (see docs/benchmark.md).
    public var defaultQuality: Int {
        switch self {
        case .webp: return 75
        case .avif: return 45
        case .jpeg: return 75
        }
    }
}

public struct Options: Sendable {
    public var format: OutputFormat = .webp
    /// 1...100, higher = better quality and bigger file.
    public var quality: Int = 75
    /// Images wider than this are scaled down (never up). nil = keep the original width.
    public var maxWidth: Int? = nil
    /// If the result is not smaller than the original, don't keep it.
    public var skipIfLarger: Bool = true
    /// Explicit output folder. nil = next to the originals (see Planner).
    public var outputDirectory: URL? = nil
    /// Parallel images. 0 = automatic.
    public var jobs: Int = 0

    public init() {}

    public var effectiveJobs: Int {
        if jobs > 0 { return jobs }
        let cores = ProcessInfo.processInfo.activeProcessorCount
        // avifenc is itself multi-threaded; give each image a few cores.
        return format == .avif ? max(1, cores / 2) : max(1, cores)
    }
}

/// Refuse to decode anything bigger than this (decompression bombs).
public let maxInputPixels = 200_000_000

public let supportedInputExtensions: Set<String> = [
    "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "avif", "gif", "bmp",
]

/// One-click settings, measured on the real batch (docs/benchmark.md).
public struct Preset: Identifiable, Sendable {
    public let id: String
    public let format: OutputFormat
    public let quality: Int
    public let maxWidth: Int?
    public static let all: [Preset] = [
        Preset(id: "web", format: .webp, quality: 75, maxWidth: 1920),
        Preset(id: "smallest", format: .avif, quality: 40, maxWidth: 1200),
        Preset(id: "compatible", format: .jpeg, quality: 75, maxWidth: 1920),
    ]
}
