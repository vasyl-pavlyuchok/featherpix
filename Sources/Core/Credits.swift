import Foundation

/// Who made Featherpix and how to reach him. Shared by the app and the CLI.
public enum Credits {
    public static let author = "Vasyl Pavlyuchok"
    public static let email = "vasylpavlyuchok@gmail.com"
    /// A fixed subject lets real requests be told apart from spam with one mail filter.
    public static let mailSubject = "[Featherpix] App a medida"
    public static let repo = "https://github.com/vasyl-pavlyuchok/featherpix"

    public static var mailURL: URL {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [URLQueryItem(name: "subject", value: mailSubject)]
        return c.url!
    }

    public static var version: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { return v }
        // The CLI lives in Featherpix.app/Contents/Resources/bin: read the app's Info.plist.
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let plist = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        if let d = NSDictionary(contentsOf: plist), let v = d["CFBundleShortVersionString"] as? String { return v }
        return "dev"
    }
}

/// Human-readable input/output formats, the single source for UI and CLI.
public enum FormatsInfo {
    public static let imageInputs = ["JPG", "PNG", "HEIC", "TIFF", "WebP", "AVIF", "GIF", "BMP"]
    public static var imageOutputs: [String] { OutputFormat.allCases.map(\.label) }
    public static let videoInputs = ["MP4", "MOV", "M4V"]
    public static let videoOutputs = ["MP4 (H.264)", "MP4 (HEVC)", "WebM (VP9 + Opus)", "WebP poster"]
}
