// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import AVFoundation
import CoreImage
import ImageIO
import simd
import Vision

/// HAND: one camera (front or back: the page's CAMERA) and Vision's hand pose, two hands at most, at the page's CAMERA rate.
/// H1 is your left hand, H2 your right, as the page draws them (Vision's chirality; not sure yet: the side of the frame it is on). A
/// hand keeps its slot while in view and moves only when Vision has been sure for a moment that it is the other one.
/// Out: each hand's 14 values and the wrists' distance (Sender.space's order), worked out from its 21 joints by the page's own rules
/// (home.html: fingersUp, gestureScores, handSet); the joints go to the page for its picture. ARKit has no hands on an iPhone (its
/// hand tracking is the Vision Pro's): Vision on the camera is the way. When SensorLove's ARKit has the camera (Face: FACE, or VIDEO
/// and DEPTH that need it), the hands are read on its frames (feed). The same capture is VIDEO's camera when ARKit is not needed
/// (NDI.swift): 1080 or 720 lines, Rec.709 video range, its lens with each frame. With DEPTH on the front camera it is the TrueDepth
/// camera, 4:3, and its depth comes too: 640 x 480, 30 a second, lined up with the picture, filtered by iOS (smoothed, holes filled
/// from the picture; its raw stream is much noisier). VIDEO goes at once; each depth frame, a moment later (iOS's filter looks a
/// frame ahead), finds the picture of the same moment among the last few: DEPTH snaps its edges (Frames.Clean) and is made that
/// picture's size along its edges (NDI.sharpen). Not a synchronizer: it would hold VIDEO back until its depth came. The camera and
/// Vision live on their own queue.
final class Hand: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate {
    var got: ([Float], [[[Float]]?]) -> Void = { _, _ in }   // the values, and each slot's joints ([x, y, confidence] × 21) or nil; on the hand queue
    var saw: (Data) -> Void = { _ in }                       // REAL: the frame, small, as a JPEG; on the hand queue, only while the page shows it
    var picture: (NDI.Picture) -> Void = { _ in }            // VIDEO: each frame (NDI keeps its own rate)
    var depth: (NDI.Depth) -> Void = { _ in }                // DEPTH on the front camera without ARKit: each depth frame
    private let session = AVCaptureSession(), output = AVCaptureVideoDataOutput(), depths = AVCaptureDepthDataOutput(), queue = DispatchQueue(label: "hand")
    private let request = VNDetectHumanHandPoseRequest(), ci = CIContext(), gate = DispatchSemaphore(value: 1)
    private var front = true, fps = 0, slots: [Slot?] = [nil, nil], real = false, sawAt = 0.0, ar = false
    private var hand = false, video = false, deep = false, preset = AVCaptureSession.Preset.hd1280x720, quarters = 0
    // DEPTH on: copies of the last pictures, for the depth frame of their moment, in buffers of our own: the camera's pool is small,
    // and holding its own buffers runs it out (VIDEO then stops)
    private var held: [(t: CMTime, px: CVPixelBuffer)] = [], pool: CVPixelBufferPool?, poolKey = (0, 0, OSType(0))

    /// A hand in its slot: its joints, how sure each gesture is (eased like the page's), the gesture it shows, where its wrist was
    private final class Slot {
        var lm: [[Float]] = [], sc = [Float](repeating: 0, count: 8), g = 0, f = [Float](repeating: 0, count: 5)
        var vel: Float = 0, lean: Float = 0.5, t = 0.0, seen = 0.0   // lean: LEFTNESS, Vision's chirality eased (a frame's doubt does not move the hand)
    }

    override init() {
        super.init()
        request.maximumHandCount = 2
    }

    /// What the page wants now (main thread): HAND, VIDEO and DEPTH (the camera allowed, SensorLove on the screen), which camera, how
    /// many frames a second, VIDEO's 1080 or 720; ar: SensorLove's ARKit has the camera: HAND reads its frames (feed), VIDEO and DEPTH
    /// take them there. DEPTH here is the depth camera of that side: TrueDepth on the front, LiDAR on the back (AVFoundation's LiDAR
    /// depth camera, sharper and quicker than ARKit's; ARKit's only with MATTE on the back)
    func run(hand: Bool, video: Bool, depth: Bool, front: Bool, fps: Int, ar: Bool, hd: Bool, max: Bool, smooth: Bool) {
        queue.async {
            if smooth != self.depths.isFilteringEnabled { self.depths.isFilteringEnabled = smooth }   // SMOOTH: switched as it runs, as Apple's TrueDepth sample does
            let was = self.hand, deep = depth && !ar
            self.ar = hand && ar; self.hand = hand; self.video = video && !ar
            if was && !hand { self.slots = [nil, nil]; self.got(Hand.values([nil, nil]), [nil, nil]) }   // off: nothing in view
            guard (hand || video || deep) && !ar else {
                if self.session.isRunning { self.session.stopRunning() }
                if hand { self.front = front }
                return
            }
            let preset: AVCaptureSession.Preset = video && max ? .hd4K3840x2160 : video && hd ? .hd1920x1080 : .hd1280x720   // VIDEO's MAX 4K, or 1080; Vision reads hands fine on 720
            if front != self.front || self.session.inputs.isEmpty || preset != self.preset || deep != self.deep { self.camera(front, preset, deep: deep, hd: video && (hd || max)) }
            if fps != self.fps, !deep { self.rate(fps) }   // with depth the format's own 30: rates set by hand lose depth frames
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func show(_ on: Bool) { queue.async { self.real = on } }   // the page's REAL is on the screen: frames for it (main thread)

    func turned(_ q: Int) { queue.async { self.quarters = q } }   // how the phone is held now (Frames.quarter): VIDEO stands up with it

    private func camera(_ front: Bool, _ preset: AVCaptureSession.Preset, deep: Bool, hd: Bool) {
        session.beginConfiguration()
        session.automaticallyConfiguresCaptureDeviceForWideColor = false   // Rec.709, what NDI reads (newer phones would pick P3)
        session.inputs.forEach(session.removeInput)
        let d = deep ? AVCaptureDevice.default(front ? .builtInTrueDepthCamera : .builtInLiDARDepthCamera, for: .video, position: front ? .front : .back) : AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
        let f = deep ? d.flatMap { Hand.depthFormat($0, hd: hd) } : nil
        session.sessionPreset = f != nil ? .inputPriority : [preset, .hd1920x1080, .hd1280x720].first(where: session.canSetSessionPreset) ?? .high   // depth: the format picked below, not a preset
        if let d, let i = try? AVCaptureDeviceInput(device: d), session.canAddInput(i) { session.addInput(i) }
        if !session.outputs.contains(output), session.canAddOutput(output) {
            output.alwaysDiscardsLateVideoFrames = true   // a frame Vision has no time for is dropped, not queued: the hands stay current
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]   // 420v: NDI's video range already
            output.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(output)
        }
        if f != nil, !session.outputs.contains(depths), session.canAddOutput(depths) {
            depths.alwaysDiscardsLateDepthData = true   // filtering: SMOOTH (run)
            depths.setDelegate(self, callbackQueue: queue)
            session.addOutput(depths)
        } else if f == nil, session.outputs.contains(depths) { session.removeOutput(depths) }
        if let d, let f, (try? d.lockForConfiguration()) != nil {
            d.activeFormat = f.video; d.activeDepthDataFormat = f.depth
            d.unlockForConfiguration()
        }
        if let c = output.connection(with: .video), c.isCameraIntrinsicMatrixDeliverySupported { c.isCameraIntrinsicMatrixDeliveryEnabled = true }   // VIDEO's lens, on each frame
        session.commitConfiguration()
        held = []
        if let d, d.activeFormat.supportedColorSpaces.contains(.sRGB), (try? d.lockForConfiguration()) != nil { d.activeColorSpace = .sRGB; d.unlockForConfiguration() }
        self.front = front; self.preset = preset; self.deep = deep; fps = 0; slots = [nil, nil]   // a new camera: its rate set again, the hands found again
    }

    /// The depth camera's 4:3 video format at 30 a second with its widest depth in metres (DepthFloat32 or 16: TrueDepth 640 x 480,
    /// LiDAR 320 x 240), its height nearest 1440 (VIDEO's 1080, stood up) or 960, video range first; with that depth format
    static func depthFormat(_ d: AVCaptureDevice, hd: Bool) -> (video: AVCaptureDevice.Format, depth: AVCaptureDevice.Format)? {
        func dims(_ f: AVCaptureDevice.Format) -> CMVideoDimensions { CMVideoFormatDescriptionGetDimensions(f.formatDescription) }
        let want: Int32 = hd ? 1440 : 960
        let metres = [kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DepthFloat16]   // LiDAR's may come only as 16-bit (Apple's sample takes it): the delegate makes it 32
        func f32(_ f: AVCaptureDevice.Format) -> Int { CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_DepthFloat32 ? 1 : 0 }
        let all = d.formats.compactMap { f -> (video: AVCaptureDevice.Format, depth: AVCaptureDevice.Format)? in
            let v = dims(f)
            guard v.width * 3 == v.height * 4, f.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 }),
                  let z = f.supportedDepthDataFormats.filter({ metres.contains(CMFormatDescriptionGetMediaSubType($0.formatDescription)) }).max(by: { (dims($0).width, f32($0)) < (dims($1).width, f32($1)) }) else { return nil }
            return (f, z)
        }
        func v(_ f: AVCaptureDevice.Format) -> Bool { CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange }   // 420v: no conversion
        let widest = all.map { dims($0.depth).width }.max() ?? 0
        return all.filter { dims($0.depth).width == widest }.min { a, b in
            let da = abs(dims(a.video).height - want), db = abs(dims(b.video).height - want)
            return da != db ? da < db : v(a.video) && !v(b.video)
        }
    }

    private func rate(_ n: Int) {
        guard let d = (session.inputs.first as? AVCaptureDeviceInput)?.device, (try? d.lockForConfiguration()) != nil else { return }
        if d.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= Double(n) }) {
            d.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(n)); d.activeVideoMaxFrameDuration = d.activeVideoMinFrameDuration
        }
        d.unlockForConfiguration()
        fps = n
    }

    func captureOutput(_ o: AVCaptureOutput, didOutput b: CMSampleBuffer, from c: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(b) else { return }
        if deep, let c = copy(px) { held.append((CMSampleBufferGetPresentationTimeStamp(b), c)); if held.count > 3 { held.removeFirst() } }
        frame(b, px)
    }

    /// The camera's picture copied into a buffer of our own (a pool of them, the size and kind of the camera's), so the camera's own
    /// goes back at once
    private func copy(_ px: CVPixelBuffer) -> CVPixelBuffer? {
        let key = (CVPixelBufferGetWidth(px), CVPixelBufferGetHeight(px), CVPixelBufferGetPixelFormatType(px))
        if pool == nil || key != poolKey {
            let a: [String: Any] = [kCVPixelBufferWidthKey as String: key.0, kCVPixelBufferHeightKey as String: key.1, kCVPixelBufferPixelFormatTypeKey as String: key.2,
                                    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](), kCVPixelBufferMetalCompatibilityKey as String: true]   // the GPU reads it as the camera's
            pool = nil; poolKey = key
            CVPixelBufferPoolCreate(nil, nil, a as CFDictionary, &pool)
        }
        var out: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess, let out else { return nil }
        CVPixelBufferLockBaseAddress(px, .readOnly); CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []); CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        for p in 0..<CVPixelBufferGetPlaneCount(px) {
            guard let s = CVPixelBufferGetBaseAddressOfPlane(px, p), let d = CVPixelBufferGetBaseAddressOfPlane(out, p) else { return nil }
            let sr = CVPixelBufferGetBytesPerRowOfPlane(px, p), dr = CVPixelBufferGetBytesPerRowOfPlane(out, p), rows = CVPixelBufferGetHeightOfPlane(px, p)
            if sr == dr { memcpy(d, s, sr * rows) } else { for y in 0..<rows { memcpy(d + y * dr, s + y * sr, min(sr, dr)) } }
        }
        return out
    }

    /// DEPTH's frame: with the picture of its moment (the same time), or the newest if that one is gone; it and the older ones are
    /// let go then
    func depthDataOutput(_ o: AVCaptureDepthDataOutput, didOutput d: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        guard let i = held.lastIndex(where: { $0.t == timestamp }) ?? held.indices.last else { return }
        let px = held[i].px
        held.removeFirst(i + 1)
        depthFrame(d, timestamp, guide: px)
    }

    private func frame(_ b: CMSampleBuffer, _ px: CVPixelBuffer) {
        let t = CMSampleBufferGetPresentationTimeStamp(b).seconds, up: CGImagePropertyOrientation = front ? .leftMirrored : .right   // upright as the phone is held, the front camera's mirrored
        if video { picture(NDI.Picture(px: px, t: t, look: Frames.turned(Frames.look(up), by: quarters), k: Hand.lens(b), pose: nil, ar: nil)) }
        if hand { see(px, t, up, mirror: front) }
    }

    /// DEPTH's frame from the depth camera and the picture of that moment (its guide): in metres, stood up as the picture is (it is
    /// lined up with it), its lens from the calibration
    private func depthFrame(_ d: AVDepthData, _ t: CMTime, guide: CVPixelBuffer) {
        let m = d.depthDataType == kCVPixelFormatType_DepthFloat32 ? d : d.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let k = m.cameraCalibrationData.map { c in Frames.scaled(c.intrinsicMatrix, Float(CVPixelBufferGetWidth(m.depthDataMap)) / Float(c.intrinsicMatrixReferenceDimensions.width)) }
        depth(NDI.Depth(px: m.depthDataMap, sure: nil, guide: guide, t: t.seconds, look: Frames.turned(Frames.look(front ? .leftMirrored : .right), by: quarters), k: k, pose: nil))
    }

    /// The lens of a frame (pixels of its picture), when the camera gives it
    static func lens(_ b: CMSampleBuffer) -> simd_float3x3? {
        guard let d = CMGetAttachment(b, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) as? Data,
              d.count >= MemoryLayout<matrix_float3x3>.size else { return nil }
        return d.withUnsafeBytes { $0.loadUnaligned(as: matrix_float3x3.self) }
    }

    /// ARKit's frame (from its queue), with the way ARKit stands it up: one at a time, a frame that comes while Vision is busy is
    /// dropped, like the camera's late ones. ARKit's front frame comes mirrored already: stood up its own way it is a mirror, as
    /// HAND's own camera shows it; the back one is not
    func feed(_ px: CVPixelBuffer, _ t: Double, _ o: CGImagePropertyOrientation) {
        guard gate.wait(timeout: .now()) == .success else { return }
        queue.async { if self.ar { self.see(px, t, o, mirror: Frames.look(o).mirror) }; self.gate.signal() }
    }

    /// A frame, how it stands up in portrait (o: as the page draws it) and whether that is a mirror (Vision then takes your right hand for a left)
    private func see(_ px: CVPixelBuffer, _ t: Double, _ o: CGImagePropertyOrientation, mirror: Bool) {
        var found: [VNHumanHandPoseObservation] = []
        do { try VNImageRequestHandler(cvPixelBuffer: px, orientation: o).perform([request]); found = request.results ?? [] } catch {}
        var free = found.compactMap { h in Hand.joints(h).map { (lm: $0, left: Hand.left(h.chirality, mirrored: mirror)) } }
        for i in 0..<2 {   // each hand in view keeps its slot: the one nearest where its wrist was (a frame or two lost is not leaving)
            guard let s = slots[i] else { continue }
            if let j = free.indices.min(by: { Hand.far(free[$0].lm[0], s.lm[0]) < Hand.far(free[$1].lm[0], s.lm[0]) }), Hand.far(free[j].lm[0], s.lm[0]) < 0.3 {
                Hand.set(s, free.remove(at: j), t)
            } else if t - s.seen > 0.2 { slots[i] = nil }
        }
        for h in free {   // a new hand: its side's slot (Vision not sure: the side of the frame it is on), or the other one if that is taken
            let s = Slot(); Hand.set(s, h, t)
            let i = s.lean == 0.5 ? (h.lm[0][0] < 0.5 ? 0 : 1) : s.lean > 0.5 ? 0 : 1
            if slots[i] == nil { slots[i] = s } else if slots[1 - i] == nil { slots[1 - i] = s }
        }
        if Hand.swaps(slots.enumerated().map { i, s in s.map { $0.lean > 0.7 ? 0 : $0.lean < 0.3 ? 1 : i } }) { slots.swapAt(0, 1) }
        got(Hand.values(slots), slots.map { $0?.lm })
        if real, !ar, t - sawAt >= 1.0 / 32, let d = Hand.picture(px, o, ci) { sawAt = t; saw(d) }   // the page draws 30 a second (with FACE on, FACE sends it)
    }

    /// Whether H1 and H2 trade places, from the slot each hand wants (nil: no hand there): a hand Vision is sure is the other one moves
    /// to its own slot if that is free or its hand wants this one; two hands sure of the same side stay where they are
    static func swaps(_ w: [Int?]) -> Bool { w[0] == 1 && (w[1] == nil || w[1] == 0) || w[1] == 0 && w[0] == nil }

    /// REAL's picture: the frame stood up as Vision read it (o), 108 wide: the page blurs it behind the dots anyway
    static func picture(_ px: CVPixelBuffer, _ o: CGImagePropertyOrientation, _ ci: CIContext) -> Data? {
        let i = CIImage(cvPixelBuffer: px).oriented(o), s = 108 / i.extent.width
        let small = i.transformed(by: CGAffineTransform(scaleX: s, y: s))
        return ci.jpegRepresentation(of: small, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.5])
    }

    /// Vision's 21 joints in MediaPipe's order, [x, y, confidence], 0 to 1 on the upright frame, y down; nil without a wrist
    private static let order: [VNHumanHandPoseObservation.JointName] = [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip, .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip, .ringMCP, .ringPIP, .ringDIP, .ringTip, .littleMCP, .littlePIP, .littleDIP, .littleTip]

    private static func joints(_ o: VNHumanHandPoseObservation) -> [[Float]]? {
        guard let p = try? o.recognizedPoints(.all) else { return nil }
        let lm = order.map { n in p[n].map { [Float($0.location.x), Float(1 - $0.location.y), $0.confidence] } ?? [0, 0, 0] }
        return lm[0][2] > 0.3 ? lm : nil
    }

    /// LEFTNESS: 1 your left hand, 0 your right, 0.5 not known. Vision reads the front camera's mirrored frame, where your right hand is a left one
    static func left(_ c: VNChirality, mirrored: Bool) -> Float { c == .unknown ? 0.5 : (c == .left) != mirrored ? 1 : 0 }

    private static func far(_ a: [Float], _ b: [Float]) -> Float { hypot(a[0] - b[0], a[1] - b[1]) }

    /// The page's handSet: gesture scores eased .3 of the way each 30th of a second, a .22 lead to change gesture; the pinch between
    /// the thumb's tip and the index's; the wrist's speed (frame widths a second)
    private static func set(_ s: Slot, _ h: (lm: [[Float]], left: Float), _ t: Double) {
        let lm = h.lm, sc = scores(lm), a = s.t > 0 ? 1 - pow(0.7, Float(min(t - s.t, 0.5) * 30)) : 1 - 0.7
        s.sc = zip(s.sc, sc).map { $0 + ($1 - $0) * a }
        var best = 0
        for j in 1..<8 where s.sc[j] > s.sc[best] { best = j }
        if best == s.g || s.sc[best] >= s.sc[s.g] + 0.22 { s.g = best }
        s.f = up(lm).map { $0 ? 1 : 0 }
        if s.t > 0, t > s.t { s.vel = far(lm[0], s.lm[0]) / Float(t - s.t) }
        if s.t == 0 { s.lean = h.left } else if h.left != 0.5 { s.lean += (h.left - s.lean) * a }   // eased like the gestures: ~4 frames of the other hand to cross .3
        s.lm = lm; s.t = t; s.seen = t
    }

    /// Each hand's ACTIVE, GESTURE, VELOCITY, LEFTNESS, RIGHTNESS, PINCH X, Y, ROT, DIST, THUMB … PINKY; then the wrists' distance
    private static func values(_ slots: [Slot?]) -> [Float] {
        var out: [Float] = []
        for s in slots {
            guard let s, s.lm.count == 21 else { out += [Float](repeating: 0, count: 14); continue }
            let a = s.lm[4], b = s.lm[8]
            out += [1, Float(s.g), s.vel, s.lean, 1 - s.lean, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, atan2(b[1] - a[1], b[0] - a[0]), hypot(b[0] - a[0], b[1] - a[1])] + s.f
        }
        let w = slots.compactMap { $0?.lm.first }
        return out + [w.count == 2 ? far(w[0], w[1]) : 0]
    }

    /// The page's fingersUp: a finger is up when its tip is 1.2 x farther from the wrist than its base (the thumb's base is its CMC)
    static func up(_ lm: [[Float]]) -> [Bool] {
        [(4, 1), (8, 5), (12, 9), (16, 13), (20, 17)].map { far(lm[$0.0], lm[0]) > far(lm[$0.1], lm[0]) * 1.2 }
    }

    /// The page's gestureScores: 0 NONE, 1 FIST, 2 OPEN PALM, 3 POINT UP, 4 THUMB DOWN, 5 THUMB UP, 6 VICTORY, 7 I LOVE YOU
    static func scores(_ lm: [[Float]]) -> [Float] {
        let f = up(lm), n = Float(f.filter { $0 }.count)
        let th = f[0], ix = f[1], md = f[2], rg = f[3], pk = f[4]
        let ty = lm[4][1], high = ty < lm[0][1] - 0.04 && ty < lm[1][1] - 0.03, low = ty > lm[0][1] + 0.04 && ty > lm[1][1] + 0.03, pd = far(lm[4], lm[8])
        var s = [Float](repeating: 0, count: 8)
        if n >= 4 { s[2] = n / 5 }
        if 5 - n >= 4 { s[1] = (5 - n) / 5 }
        if !th && ix && !md && !rg && !pk { s[3] = 1 }
        if ix && !md && !rg && !pk && pd > 0.08 { s[3] = max(s[3], 0.8) }
        if th && !ix && !md && !rg && !pk && high { s[5] = 1 }
        if th && !ix && !md && !rg && !pk && low { s[4] = 1 }
        if !th && ix && md && !rg && !pk { s[6] = 1 }
        if ix && md && !rg && !pk { s[6] = max(s[6], 0.85) }
        if th && ix && !md && !rg && pk { s[7] = 1 }
        if s.max()! <= 0.5 { s[0] = 1 }
        return s
    }
}
