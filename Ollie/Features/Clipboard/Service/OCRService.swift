import AppKit
import Vision

enum OCRService {
    @MainActor
    static func recognizeText(from image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                guard !Task.isCancelled else { return nil }
                let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                return text?.isEmpty == false ? text : nil
            } catch { return nil }
        }.value
    }
}
