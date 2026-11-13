// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import Accelerate
import CoreML
import QuartzCore
import Vision

/// DEPTH's DETAIL AI: Depth Anything V2 Small, Apple's Core ML conversion (Apache-2.0; ci_post_clone.sh fetches it from Hugging Face,
/// each file checked, and Xcode builds it in), on the Neural Engine. The camera's picture in, as the camera stores it; out its
/// relative 1/distance, 518 x 392, each frame divided by its own largest: no metres, but the edges, hair and folds the depth cameras
/// cannot sample. NDI ties it to the sensor every frame (Frames.fit, NDI.sharpen). Only on one queue (NDI's detail); the first run
/// loads it (seconds: the Neural Engine prepares it)
final class Detail {
    static let built = url != nil   // the model in this build
    static let w = 518, h = 392
    private static let url = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc")
    private var request: VNCoreMLRequest?, tried = false
    private(set) var ms = 0.0   // the last run, for the metadata

    /// The picture's relative 1/distance as floats, w x h, the top row first; nil without the model or if it failed
    func run(_ px: CVPixelBuffer) -> [Float]? {
        if !tried, let url = Detail.url {
            tried = true
            do {
                let c = MLModelConfiguration(); c.computeUnits = .all   // without the GPU, parts of the model fall back to the CPU
                let r = VNCoreMLRequest(model: try VNCoreMLModel(for: try MLModel(contentsOf: url, configuration: c)))
                r.imageCropAndScaleOption = .scaleFill   // the whole picture, edge to edge: lined up with the depth
                request = r
            } catch { NSLog("Depth Anything did not load: %@", "\(error)") }
        }
        guard let request else { return nil }
        let t0 = CACurrentMediaTime()
        do { try VNImageRequestHandler(cvPixelBuffer: px, orientation: .up).perform([request]) } catch { return nil }
        guard let b = (request.results?.first as? VNPixelBufferObservation)?.pixelBuffer else { return nil }
        guard CVPixelBufferGetWidth(b) == Detail.w, CVPixelBufferGetHeight(b) == Detail.h else { return nil }
        CVPixelBufferLockBaseAddress(b, .readOnly); defer { CVPixelBufferUnlockBaseAddress(b, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(b) else { return nil }
        var out = [Float](repeating: 0, count: Detail.w * Detail.h)
        let row = CVPixelBufferGetBytesPerRow(b), format = CVPixelBufferGetPixelFormatType(b)
        let ok = out.withUnsafeMutableBytes { p -> Bool in
            if format == kCVPixelFormatType_OneComponent32Float {   // as floats already: row by row
                for y in 0..<Detail.h { memcpy(p.baseAddress! + y * Detail.w * 4, base + y * row, Detail.w * 4) }
                return true
            }
            guard format == kCVPixelFormatType_OneComponent16Half else { return false }   // the model's GRAYSCALE_FLOAT16
            var src = vImage_Buffer(data: base, height: vImagePixelCount(Detail.h), width: vImagePixelCount(Detail.w), rowBytes: row)
            var dst = vImage_Buffer(data: p.baseAddress, height: vImagePixelCount(Detail.h), width: vImagePixelCount(Detail.w), rowBytes: Detail.w * 4)
            return vImageConvert_Planar16FtoPlanarF(&src, &dst, 0) == kvImageNoError
        }
        ms = (CACurrentMediaTime() - t0) * 1000
        return ok ? out : nil
    }
}
