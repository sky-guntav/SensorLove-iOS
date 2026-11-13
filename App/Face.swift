// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import ARKit
import CoreImage

/// FACE: ARKit's face tracking on the front (TrueDepth) camera, at the page's CAMERA rate. Out, in Sender.space's order: DETECTED,
/// where the head is from the phone (m) and how it is turned (a quaternion), the point it looks at, your left eye then your right,
/// then ARKit's 52 expressions (0 to 1) by its own names. ARKit's front camera world is already your mirror (its frame comes mirrored
/// and it shows it as one): the head goes out as ARKit gives it, and the page's frog moves as your mirror does (move your head to
/// your right: POS X goes up). ARKit's face is that mirror image, so its sides are the image's own: its left eye is your right one.
/// The eyes and the expressions go out under your sides (/face/eyeBlinkLeft is your left eye). With HAND on too, the hands are read
/// on these same frames: one front camera for both.
/// It is also SensorLove's ARKit for VIDEO and DEPTH (NDI.swift): on the front camera for TrueDepth's depth or MATTE (FACE's own
/// values only with FACE on), or, as .world, on the back one for LiDAR's depth, MATTE and where the phone is. ARKit and its frames
/// live on their own queue.
final class Face: NSObject, ARSessionDelegate {
    enum Mode: Equatable { case off, face, world }
    /// What runs (Sender.camera): the mode, FACE's values, and what VIDEO and DEPTH take; how many frames a second for FACE and HAND
    struct Want: Equatable { var mode = Mode.off, face = false, video = false, depth = false, matte = false, fps = 30, smooth = true, big = false }   // big: VIDEO at MAX, ARKit's largest format

    var got: ([Float]) -> Void = { _ in }                      // the 69 values; lost, DETECTED 0 and the rest as they were. On the face queue
    var frames: (CVPixelBuffer, Double, CGImagePropertyOrientation) -> Void = { _, _, _ in }  // each frame it reads and how it stands up, for HAND
    var picture: (NDI.Picture) -> Void = { _ in }              // VIDEO: every frame (NDI keeps its own rate)
    var depth: (NDI.Depth) -> Void = { _ in }                  // DEPTH: every depth frame (LiDAR's 60 a second, TrueDepth's 15)
    var saw: (Data) -> Void = { _ in }                         // REAL: the frame, small, while the page shows it
    var mesh: ([Int]) -> Void = { _ in }                       // REAL: ARKit's face mesh on that frame (Face.mesh)
    var said: (String) -> Void = { _ in }                      // a problem, for the console
    private let session = ARSession(), queue = DispatchQueue(label: "face"), ci = CIContext()
    private var want = Want(), fps = 0, at = 0.0, real = false, sawAt = 0.0, last: [Float] = [], told = false, quarters = 0

    static let can = ARFaceTrackingConfiguration.isSupported   // a TrueDepth camera
    static let lidar = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)   // a LiDAR scanner (Pro iPhones)
    static let people = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)   // MATTE on the back camera

    override init() {
        super.init()
        session.delegate = self; session.delegateQueue = queue
    }

    /// What the page wants now (main thread): the mode (the camera allowed, SensorLove on the screen), and what each takes
    func run(_ w: Want) {
        queue.async {
            let was = self.want
            guard w.mode != .off, w.mode != .face || Face.can else {
                if w.mode == .face, !self.told { self.told = true; self.said("FACE · THIS PHONE CAN'T TRACK A FACE (IT NEEDS A TRUEDEPTH CAMERA)") }
                if was.mode != .off { self.session.pause(); self.lost() }
                self.want = Want()
                return
            }
            self.want = w
            if !w.face, was.face { self.lost() }   // ARKit stays for VIDEO, DEPTH or HAND: FACE alone stops
            guard w.mode != was.mode || w.fps != was.fps || w.depth != was.depth || w.matte != was.matte || w.big != was.big else { return }
            let rate = w.fps > 30 ? 60 : 30   // 15: every other of 30
            func pick(_ all: [ARConfiguration.VideoFormat], _ aspect: (CGSize) -> Bool) -> ARConfiguration.VideoFormat? {   // at the rate and shape; big: the largest, else ARKit's first
                let fit = all.filter { $0.framesPerSecond == rate && aspect($0.imageResolution) }
                return w.big ? fit.max { $0.imageResolution.width < $1.imageResolution.width } : fit.first
            }
            let c: ARConfiguration
            if w.mode == .face {
                let f = ARFaceTrackingConfiguration()
                if let v = pick(ARFaceTrackingConfiguration.supportedVideoFormats, { $0.width * 9 == $0.height * 16 }) { f.videoFormat = v }   // 16:9, the page's frame
                f.isLightEstimationEnabled = false
                if w.matte, ARFaceTrackingConfiguration.supportsFrameSemantics(.personSegmentation) { f.frameSemantics.insert(.personSegmentation) }
                c = f
            } else {
                let f = ARWorldTrackingConfiguration()
                if let v = pick(ARWorldTrackingConfiguration.supportedVideoFormats, { $0.width * 3 == $0.height * 4 }) { f.videoFormat = v }   // 4:3, as LiDAR's depth is: one view for both
                f.isLightEstimationEnabled = false; f.planeDetection = []; f.environmentTexturing = .none
                if w.depth, Face.lidar { f.frameSemantics.insert(.sceneDepth) }   // each frame's own (the smoothed one lags behind motion); DEPTH steadies it (Frames.Clean)
                if w.matte, Face.people { f.frameSemantics.insert(.personSegmentationWithDepth) }
                c = f
            }
            self.session.run(c, options: was.mode == w.mode ? [] : [.resetTracking, .removeExistingAnchors])
            self.fps = w.fps
        }
    }

    func show(_ on: Bool) { queue.async { self.real = on } }   // the page's REAL is on the screen (main thread)

    func turned(_ q: Int) { queue.async { self.quarters = q } }   // how the phone is held now (Frames.quarter): VIDEO and DEPTH stand up with it

    func session(_ s: ARSession, didUpdate f: ARFrame) {
        let t = f.timestamp
        let vp = CGSize(width: f.camera.imageResolution.height, height: f.camera.imageResolution.width)   // portrait, the frame's own shape: nothing cropped
        let o = Face.orientation(f.displayTransform(for: .portrait, viewportSize: vp))   // ARKit's own way to stand its frame up (.right on the phone): a mirror, as HAND's own camera shows it
        if want.video || want.depth { send(f, t, o) }
        guard t - at >= 1 / Double(max(fps, 1)) - 0.004 else { return }   // CAMERA's rate
        at = t
        frames(f.capturedImage, t, o)
        let show = real && t - sawAt >= 1.0 / 32   // REAL: the page draws 30 a second
        if show, let d = Hand.picture(f.capturedImage, o, ci) { sawAt = t; saw(d) }
        guard want.face else { return }   // ARKit runs for VIDEO, DEPTH or HAND only
        guard let a = f.anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first, a.isTracked else { return lost() }
        let m = f.camera.viewMatrix(for: .portrait) * a.transform
        var v: [Float] = [1]
        v += Face.head(m)
        v += [a.lookAtPoint.x, a.lookAtPoint.y, a.lookAtPoint.z]
        for e in [a.rightEyeTransform, a.leftEyeTransform] { v += [e.columns.3.x, e.columns.3.y, e.columns.3.z] }   // your left eye first: ARKit's right one
        v += Face.shapes.map { a.blendShapes[$0]?.floatValue ?? 0 }
        last = v; got(v)
        if show { mesh(Face.mesh(a, f.camera, vp)) }
    }

    /// VIDEO and DEPTH: the frame as it stands up, turned as the phone is held, its lens and (world tracking) where the phone is.
    /// DEPTH is LiDAR's (metres, with ARKit's confidence) or TrueDepth's (15 a second, made metres; no confidence)
    private func send(_ f: ARFrame, _ t: Double, _ o: CGImagePropertyOrientation) {
        let look = Frames.turned(Frames.look(o), by: quarters), world = want.mode == .world
        if want.video { picture(NDI.Picture(px: f.capturedImage, t: t, look: look, k: f.camera.intrinsics, pose: world ? f.camera.transform : nil, ar: want.matte ? f : nil)) }
        guard want.depth else { return }
        if world, let d = f.sceneDepth {
            let k = Frames.scaled(f.camera.intrinsics, Float(CVPixelBufferGetWidth(d.depthMap)) / Float(f.camera.imageResolution.width))
            depth(NDI.Depth(px: d.depthMap, sure: d.confidenceMap, guide: f.capturedImage, t: t, look: look, k: k, pose: f.camera.transform, steady: want.smooth))   // made the picture's size along its edges (NDI.sharpen), the confidence its weights; SMOOTH: steadied
        } else if !world, let d = f.capturedDepthData {
            let m = d.depthDataType == kCVPixelFormatType_DepthFloat32 ? d : d.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            let k = m.cameraCalibrationData.map { c in Frames.scaled(c.intrinsicMatrix, Float(CVPixelBufferGetWidth(m.depthDataMap)) / Float(c.intrinsicMatrixReferenceDimensions.width)) }
            depth(NDI.Depth(px: m.depthDataMap, sure: nil, t: t, look: look, k: k, pose: nil))
        }
    }

    func session(_ s: ARSession, didFailWithError e: Error) { said("FACE · " + e.localizedDescription.uppercased()) }

    private func lost() { if last.first == 1 { last[0] = 0; got(last) } }   // only DETECTED changes: a patch knows the values stopped

    /// The head from the phone: position x, y, z (m; in front, so z is below 0), then the turn as a quaternion x, y, z, w (none when
    /// you look straight at the phone: z about -0.37 and no turn). m: the face in ARKit's portrait camera space, already your mirror,
    /// as it is. w kept positive (q and -q are one turn: no jumps in a patch)
    static func head(_ m: simd_float4x4) -> [Float] {
        let p = m.columns.3, q = simd_quatf(m).vector
        return [p.x, p.y, p.z] + (q.w < 0 ? [-q.x, -q.y, -q.z, -q.w] : [q.x, q.y, q.z, q.w])
    }

    /// REAL: each point of ARKit's face mesh where ARKit shows it on its frame in portrait (vp, as the picture is stood up): x, y in
    /// thousandths of the picture's width and height
    static func mesh(_ a: ARFaceAnchor, _ c: ARCamera, _ vp: CGSize) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(a.geometry.vertices.count * 2)
        for v in a.geometry.vertices {
            let w = a.transform * simd_float4(v, 1), p = c.projectPoint(simd_float3(w.x, w.y, w.z), orientation: .portrait, viewportSize: vp)
            out.append(Int((p.x / vp.width * 1000).rounded())); out.append(Int((p.y / vp.height * 1000).rounded()))
        }
        return out
    }

    /// How to stand ARKit's frame up as it shows it in portrait, from its display transform (a quarter turn, maybe mirrored; normalized
    /// coordinates, from the top left): x' = c·y + tx, y' = b·x + ty
    static func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        t.c < 0 ? (t.b > 0 ? .right : .rightMirrored) : (t.b > 0 ? .leftMirrored : .left)
    }


    /// ARKit's 52 expressions in Sender.space's order (its Swift names are the OSC names: eyeBlinkLeft, jawOpen…), each side read
    /// from ARKit's other one: its face is your mirror image, so its eyeBlinkRight is your left eye and its jawLeft your jaw to your right
    static let shapes: [ARFaceAnchor.BlendShapeLocation] = [.eyeBlinkRight, .eyeLookDownRight, .eyeLookInRight, .eyeLookOutRight, .eyeLookUpRight, .eyeSquintRight, .eyeWideRight,
        .eyeBlinkLeft, .eyeLookDownLeft, .eyeLookInLeft, .eyeLookOutLeft, .eyeLookUpLeft, .eyeSquintLeft, .eyeWideLeft,
        .jawForward, .jawRight, .jawLeft, .jawOpen, .mouthClose, .mouthFunnel, .mouthPucker, .mouthRight, .mouthLeft,
        .mouthSmileRight, .mouthSmileLeft, .mouthFrownRight, .mouthFrownLeft, .mouthDimpleRight, .mouthDimpleLeft,
        .mouthStretchRight, .mouthStretchLeft, .mouthRollLower, .mouthRollUpper, .mouthShrugLower, .mouthShrugUpper,
        .mouthPressRight, .mouthPressLeft, .mouthLowerDownRight, .mouthLowerDownLeft, .mouthUpperUpRight, .mouthUpperUpLeft,
        .browDownRight, .browDownLeft, .browInnerUp, .browOuterUpRight, .browOuterUpLeft, .cheekPuff, .cheekSquintRight,
        .cheekSquintLeft, .noseSneerRight, .noseSneerLeft, .tongueOut]
}
