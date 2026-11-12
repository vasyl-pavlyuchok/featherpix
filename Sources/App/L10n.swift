import Foundation

/// Tiny two-language table (Spanish / English), chosen from the system language.
enum L {
    static let es = (ProcessInfo.processInfo.environment["FEATHERPIX_LANG"] ?? Locale.preferredLanguages.first ?? "en").hasPrefix("es")
    static func t(_ en: String, _ esText: String) -> String { es ? esText : en }

    static var dropTitle: String { t("Drop images or folders here", "Suelta aquí imágenes o carpetas") }
    static var dropHint: String { t("Originals are never touched. Folders are copied to “<folder> (Featherpix)”.",
                                    "Los originales no se tocan. Las carpetas se copian en «<carpeta> (Featherpix)».") }
    static var choose: String { t("Choose…", "Elegir…") }
    static var format: String { t("Format", "Formato") }
    static var quality: String { t("Quality", "Calidad") }
    static var maxWidth: String { t("Max width", "Ancho máximo") }
    static var limitWidth: String { t("Limit width", "Limitar ancho") }
    static var skipLarger: String { t("Keep original if not smaller", "Conservar el original si no se reduce") }
    static var outputNextTo: String { t("Save next to the originals", "Guardar junto a los originales") }
    static var outputChoose: String { t("Save to folder…", "Guardar en carpeta…") }
    static var working: String { t("Optimizing…", "Optimizando…") }
    static var cancel: String { t("Cancel", "Cancelar") }
    static var showInFinder: String { t("Show in Finder", "Mostrar en Finder") }
    static var clear: String { t("Clear", "Limpiar") }
    static var failed: String { t("failed", "fallidas") }
    static var kept: String { t("kept original", "sin cambio") }
    static var images: String { t("images", "imágenes") }
    static var notSmaller: String { t("not smaller — original kept", "no se reducía — se deja el original") }
    static var defaults: String { t("Recommended", "Recomendado") }
    static var presets: String { t("Quick setting", "Ajuste rápido") }
    static func preset(_ id: String) -> (String, String) {
        switch id {
        case "web": return (t("Web", "Web"), "WebP 75 · 1920 px")
        case "smallest": return (t("Smallest", "Máxima reducción"), "AVIF 40 · 1200 px")
        default: return (t("Compatible", "Compatible"), "JPEG 75 · 1920 px")
        }
    }
    static func hint(_ f: OutputFormat) -> String {
        switch f {
        case .webp: return t("Best for the web: works in every browser.", "Lo mejor para la web: funciona en todos los navegadores.")
        case .avif: return t("Smallest files; slower to create.", "Los ficheros más pequeños; tarda algo más.")
        case .jpeg: return t("Maximum compatibility (email, old apps).", "Máxima compatibilidad (correo, apps antiguas).")
        }
    }
}
