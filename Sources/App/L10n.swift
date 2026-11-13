import Foundation

/// Tiny two-language table (Spanish / English), chosen from the system language.
enum L {
    static let es = (ProcessInfo.processInfo.environment["FEATHERPIX_LANG"] ?? Locale.preferredLanguages.first ?? "en").hasPrefix("es")
    static func t(_ en: String, _ esText: String) -> String { es ? esText : en }

    static var dropTitle: String { t("Drop images or folders here", "Suelta aquí imágenes o carpetas") }
    static var dropHint: String { t("Originals are never touched. Folders are copied to “<folder> (Featherpix)”.",
                                    "Los originales no se tocan. Las carpetas se copian en «<carpeta> (Featherpix)».") }
    static var formatsLine: String {
        t("In: ", "Entrada: ") + FormatsInfo.imageInputs.joined(separator: ", ")
            + t("  ·  Out: ", "  ·  Salida: ") + FormatsInfo.imageOutputs.joined(separator: ", ")
    }
    static var designedBy: String { t("Designed by", "Diseñado por") }
    static var hireMe: String { t("Need a custom app for your business? Write to me", "¿Necesitas una app a medida para tu empresa? Escríbeme") }
    static var hireMeShort: String { t("Custom apps", "Apps a medida") }
    static var aboutCredits: String {
        t("Designed by \(Credits.author).\n\nNeed a custom app for your business? Write to \(Credits.email) with the subject “\(Credits.mailSubject)” and tell me what you need.\n\nFree and open source (MIT).",
          "Diseñado por \(Credits.author).\n\n¿Necesitas una app a medida para tu empresa? Escríbeme a \(Credits.email) con el asunto «\(Credits.mailSubject)» y cuéntame qué necesitas.\n\nGratis y de código abierto (MIT).")
    }
    static var photos: String { t("Photos", "Fotos") }
    static var videos: String { t("Videos", "Vídeos") }
    static var photosTagline: String { t("Lighter images, same look", "Imágenes más ligeras, mismo aspecto") }
    static var videosTagline: String { t("Lighter videos for the web", "Vídeos ligeros para la web") }
    static var saved: String { t("SAVED", "AHORRADO") }
    static var again: String { t("New batch", "Nuevo lote") }
    static var dropVideoTitle: String { t("Drop videos here", "Suelta aquí tus vídeos") }
    static var dropVideoHint: String { t("Originals are never touched. Results go next to them as “<name>-web.mp4”.",
                                         "Los originales no se tocan. El resultado se guarda al lado como «<nombre>-web.mp4».") }
    static var videoFormatsLine: String { t("In: MP4, MOV, M4V  ·  Out: MP4 (H.264 or HEVC) or WebM (VP9)", "Entrada: MP4, MOV, M4V  ·  Salida: MP4 (H.264 o HEVC) o WebM (VP9)") }
    static var videoUse: String { t("What is it for?", "¿Para qué es?") }
    static func videoPreset(_ p: VideoPreset) -> (String, String) {
        switch p {
        case .web: return (t("Web", "Web"), t("≤1920 px · with audio", "≤1920 px · con audio"))
        case .loop: return (t("Hero loop", "Portada en bucle"), t("≤1280 px · silent · poster", "≤1280 px · sin audio · póster"))
        case .max: return (t("Best quality", "Máxima calidad"), t("original size", "tamaño original"))
        }
    }
    static var outputFormat: String { t("Output", "Salida") }
    static func codecHint(_ c: VideoCodec) -> String {
        switch c {
        case .h264: return t("Plays in every browser and device.", "Se ve en cualquier navegador y dispositivo.")
        case .hevc: return t("About 40 % smaller; Safari, Chrome and Edge on recent devices.", "Un 40 % más ligero; Safari, Chrome y Edge en equipos recientes.")
        case .vp9: return t("The lightest for the web. Adds an MP4 copy for older iPhones.", "Lo más ligero para la web. Añade una copia MP4 para iPhone antiguos.")
        }
    }
    static func codecChip(_ c: VideoCodec) -> (String, String) {
        switch c { case .h264: return ("MP4", "H.264"); case .hevc: return ("HEVC", "H.265"); case .vp9: return ("WebM", "VP9") }
    }
    static var withFallback: String { t("+ MP4 fallback", "+ MP4 de respaldo") }
    static var keepAudio: String { t("Keep audio", "Conservar el audio") }
    static var forYourWeb: String { t("Paste into your page", "Para pegar en tu web") }
    static var copyHTML: String { t("Copy HTML", "Copiar HTML") }
    static var copied: String { t("Copied ✓", "Copiado ✓") }
    static var notAVideo: String { t("not a supported video (MP4, MOV, M4V)", "no es un vídeo admitido (MP4, MOV, M4V)") }
    static var cancelled: String { t("cancelled", "cancelado") }
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
