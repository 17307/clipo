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
            request.usesLanguageCorrection = true
            request.revision = VNRecognizeTextRequestRevision3

            let handler = VNImageRequestHandler(data: imageData, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
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
