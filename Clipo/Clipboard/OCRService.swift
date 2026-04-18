import AppKit
import Foundation
import Vision

/// Runs on-device text recognition against image bytes using the Vision
/// framework. Fully local (no network) and off the main thread, so even
/// a run of screenshots won't block the clipboard engine or the UI.
///
/// Typical cost on Apple Silicon:
/// - Small screenshot (1000×800):  40–120 ms
/// - Retina screenshot (2880×1800): 200–500 ms
/// - 4K (3840×2160):                400 ms – 1 s
///
/// We guard against runaway cost with a pixel-count cap — anything above
/// `ocrMaxPixels` (default 10 MP) short-circuits to nil so a 50-MP RAW
/// paste doesn't stall a laptop fan.
enum OCRService {
    /// Async entry point. Returns the concatenated recognized text, or nil
    /// when the image can't be decoded, is over the pixel budget, or
    /// contains no readable text. Never throws — caller treats nil as "no
    /// searchable text available."
    static func extractText(from imageData: Data, maxPixels: Int) async -> String? {
        // Cheap pixel-count gate using CGImageSourceCopyPropertiesAtIndex —
        // avoids fully decoding the bitmap just to ask "is this too big?"
        guard let size = pixelSize(of: imageData) else { return nil }
        let pixels = size.width * size.height
        if maxPixels > 0, pixels > maxPixels { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let request = VNRecognizeTextRequest { req, _ in
                guard let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let lines = observations.compactMap { obs -> String? in
                    obs.topCandidates(1).first?.string
                }
                let joined = lines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: joined.isEmpty ? nil : joined)
            }
            // `.accurate` is slower (~2×) than `.fast` but produces dramatically
            // better results on screenshots with small fonts or stylised UI.
            // Latency is still well under the "user notices" threshold since
            // we run off-main and the result only appears in search.
            request.recognitionLevel = .accurate
            request.revision = VNRecognizeTextRequestRevision3

            // Without explicit languages Vision defaults to English only —
            // Chinese / Japanese / Korean screenshots come back empty.
            // Revision 3 supports a broad set of scripts; list the ones
            // that actually share glyph space with the user's likely
            // content. Ordering matters as a tie-breaker for ambiguous
            // glyphs: we put the user's preferred language first so a
            // Chinese user's mixed CN/EN screenshots favour Chinese over
            // a plausible English reading of the same shapes.
            request.recognitionLanguages = Self.recognitionLanguages
            // Disable correction on the auto-detect path — the model's
            // language-corrector is tuned for Latin scripts and can
            // over-rewrite CJK text. Re-enable later if we add a toggle.
            request.usesLanguageCorrection = false
            if #available(macOS 14.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(data: imageData, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Candidate language list seeded from the user's preferred locales.
    /// Always falls back to a broad superset so a rarely-used language
    /// still has a chance. Cached: the list doesn't change over the
    /// lifetime of the process (language changes require relaunch).
    private static let recognitionLanguages: [String] = {
        // Languages Revision 3 actually supports on macOS 14+.
        let supported: Set<String> = [
            "en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR",
            "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR",
            "ru-RU", "uk-UA"
        ]
        // Pull the user's preferred languages, map to BCP-47 tags Vision
        // understands. Locale.preferredLanguages returns things like
        // "zh-Hans-CN" or "en-US"; trim the region for the CJK codes.
        var ordered: [String] = []
        for raw in Locale.preferredLanguages {
            let normalised = Self.mapToVisionLanguage(raw)
            if let n = normalised, supported.contains(n), !ordered.contains(n) {
                ordered.append(n)
            }
        }
        // Append anything the user didn't pick — widens the net without
        // changing tie-breaker priority.
        for lang in ["en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"] {
            if !ordered.contains(lang) { ordered.append(lang) }
        }
        return ordered
    }()

    /// Map a `Locale.preferredLanguages` entry to the BCP-47 tag Vision
    /// expects. "zh-Hans-CN" → "zh-Hans"; "en-GB" → "en-US" (Vision
    /// doesn't have per-region English models); unknown scripts returns
    /// nil so the caller can skip them.
    private static func mapToVisionLanguage(_ raw: String) -> String? {
        let parts = raw.split(separator: "-").map(String.init)
        guard let primary = parts.first?.lowercased() else { return nil }
        switch primary {
        case "en": return "en-US"
        case "fr": return "fr-FR"
        case "it": return "it-IT"
        case "de": return "de-DE"
        case "es": return "es-ES"
        case "pt": return "pt-BR"
        case "ru": return "ru-RU"
        case "uk": return "uk-UA"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "zh":
            // Preserve the script tag (Hans/Hant) when present so CN vs TW
            // screenshots pick the right model.
            if parts.count >= 2 {
                let script = parts[1]
                if script.caseInsensitiveCompare("Hant") == .orderedSame {
                    return "zh-Hant"
                }
                if script.caseInsensitiveCompare("Hans") == .orderedSame {
                    return "zh-Hans"
                }
            }
            return "zh-Hans"
        default:
            return nil
        }
    }

    /// Pixel dimensions from the raw image data without building an NSImage.
    /// Uses ImageIO which reads only the header for most formats.
    private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard w > 0, h > 0 else { return nil }
        return (w, h)
    }
}
