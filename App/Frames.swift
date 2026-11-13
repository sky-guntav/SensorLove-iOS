// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import CoreVideo
import ImageIO
import simd

/// What VIDEO and DEPTH send, worked out apart from NDI so it can be tested: how a camera's stored frame stands up, what that does
/// to its lens (intrinsics) and its pose, the depth's 16-bit code, the colour conversion's numbers, and each frame's metadata.
enum Frames {
    /// How a stored image stands up: quarter turns clockwise, then a mirror (left and right swapped)
    struct Look: Equatable { var turns = 0, mirror = false }

    /// The same as an image orientation (Face's and Hand's): .right, say, is a quarter turn clockwise to stand up
    static func look(_ o: CGImagePropertyOrientation) -> Look {
        switch o {
        case .up: return Look(turns: 0, mirror: false)
        case .upMirrored: return Look(turns: 0, mirror: true)
        case .down: return Look(turns: 2, mirror: false)
        case .downMirrored: return Look(turns: 2, mirror: true)
        case .right: return Look(turns: 1, mirror: false)
        case .leftMirrored: return Look(turns: 1, mirror: true)
        case .left: return Look(turns: 3, mirror: false)
        case .rightMirrored: return Look(turns: 3, mirror: true)
        @unknown default: return Look()
        }
    }

    /// A look turned further, clockwise (the phone held another way round): the mirror stays a mirror of the picture as seen
    static func turned(_ l: Look, by q: Int) -> Look {
        let k = ((q % 4) + 4) % 4
        return Look(turns: (l.turns + (l.mirror ? 4 - k : k)) % 4, mirror: l.mirror)
    }

    /// The size once stood up
    static func size(_ w: Int, _ h: Int, _ l: Look) -> (w: Int, h: Int) { l.turns % 2 == 0 ? (w, h) : (h, w) }

    /// Where a stored pixel lands, standing up (continuous coordinates: 0 to w across, 0 to h down)
    static func place(_ p: SIMD2<Float>, w: Float, h: Float, _ l: Look) -> SIMD2<Float> {
        var q: SIMD2<Float>
        switch l.turns {
        case 1: q = [h - p.y, p.x]
        case 2: q = [w - p.x, h - p.y]
        case 3: q = [p.y, w - p.x]
        default: q = p
        }
        if l.mirror { q.x = (l.turns % 2 == 0 ? w : h) - q.x }
        return q
    }

    /// The stored pixel a stood-up pixel shows (place's inverse, for whole pixels; w, h: the stored size)
    static func source(_ x: Int, _ y: Int, w: Int, h: Int, _ l: Look) -> (x: Int, y: Int) {
        let xm = l.mirror ? size(w, h, l).w - 1 - x : x
        switch l.turns {
        case 1: return (y, h - 1 - xm)
        case 2: return (w - 1 - xm, h - 1 - y)
        case 3: return (w - 1 - y, xm)
        default: return (xm, y)
        }
    }

    /// Stood-up row y as a walk through the stored picture: where it starts and the step from each pixel to the next (source,
    /// with no sums a pixel: DEPTH reads 300 000 a frame)
    static func walk(_ y: Int, w: Int, h: Int, _ l: Look) -> (x: Int, y: Int, dx: Int, dy: Int) {
        let a = source(0, y, w: w, h: h, l), b = source(1, y, w: w, h: h, l)
        return (a.x, a.y, b.x - a.x, b.y - a.y)
    }

    /// The image orientation that stands a stored picture up as this look does (look's inverse: Core Image draws the cards' pictures by it)
    static func orientation(_ l: Look) -> CGImagePropertyOrientation {
        switch (l.turns % 4, l.mirror) {
        case (1, false): return .right
        case (1, true): return .leftMirrored
        case (2, false): return .down
        case (2, true): return .downMirrored
        case (3, false): return .left
        case (3, true): return .rightMirrored
        case (_, true): return .upMirrored
        default: return .up
        }
    }

    /// How many quarter turns clockwise a picture standing up in portrait needs to stand up as the phone is held now, from
    /// gravity (CoreMotion's, in g, the phone's x right and y up): 0 upright, 1 the phone's top to the right, 2 upside down, 3 its
    /// top to the left. Flat on its back, or between two ways, it keeps what it had (was)
    static func quarter(gravity g: SIMD3<Float>, was: Int) -> Int {
        let x = -g.x, y = -g.y   // up, on the phone
        guard abs(g.z) < 0.8, abs(abs(x) - abs(y)) > 0.3 else { return was }
        return abs(y) > abs(x) ? (y > 0 ? 0 : 2) : (x > 0 ? 3 : 1)
    }

    /// The lens of the stood-up picture from the stored one's (fx, fy, cx, cy in pixels, as ARKit gives them for that size)
    static func lens(_ k: simd_float3x3, w: Float, h: Float, _ l: Look) -> simd_float3x3 {
        let fx = k[0][0], fy = k[1][1], cx = k[2][0], cy = k[2][1]
        var n: (fx: Float, fy: Float, cx: Float, cy: Float)
        switch l.turns {
        case 1: n = (fy, fx, h - cy, cx)
        case 2: n = (fx, fy, w - cx, h - cy)
        case 3: n = (fy, fx, cy, w - cx)
        default: n = (fx, fy, cx, cy)
        }
        if l.mirror { n.cx = (l.turns % 2 == 0 ? w : h) - n.cx }
        return simd_float3x3([n.fx, 0, 0], [0, n.fy, 0], [n.cx, n.cy, 1])
    }

    /// A lens for the picture scaled by s (its pixels s times as many each way)
    static func scaled(_ k: simd_float3x3, _ s: Float) -> simd_float3x3 { simd_float3x3([k[0][0] * s, 0, 0], [0, k[1][1] * s, 0], [k[2][0] * s, k[2][1] * s, 1]) }

    /// The camera's pose (ARKit's camera to world: x right, y up, looking down -z, for the stored picture) for the stood-up
    /// picture: the same camera, its x and y turned with the picture. A mirror has no true pose: nil
    static func pose(_ m: simd_float4x4, _ l: Look) -> simd_float4x4? {
        guard !l.mirror else { return nil }
        let x = m.columns.0, y = m.columns.1
        switch l.turns {
        case 1: return simd_float4x4(y, -x, m.columns.2, m.columns.3)
        case 2: return simd_float4x4(-x, -y, m.columns.2, m.columns.3)
        case 3: return simd_float4x4(-y, x, m.columns.2, m.columns.3)
        default: return m
        }
    }

    /// Where a world point shows on a picture with this lens and pose (pixels from the top left), nil behind the camera
    static func project(_ p: SIMD3<Float>, k: simd_float3x3, pose: simd_float4x4) -> SIMD2<Float>? {
        let c = pose.inverse * SIMD4<Float>(p, 1)
        guard c.z < 0 else { return nil }
        return [k[0][0] * c.x / -c.z + k[2][0], k[1][1] * -c.y / -c.z + k[2][1]]
    }

    /// DEPTH's code for a distance (near white): 16-bit video range, white (60160) at NEAR metres or closer, fading to dark at FAR;
    /// black (4096) nothing measured, or beyond FAR. It goes by 1 / distance (disparity, what TrueDepth measures): near things get
    /// the codes and a step's error grows with the distance squared, as the cameras' own does. A patch's 0 to 1 is
    /// v = (1/m − 1/far) / (1/near − 1/far). A point in range is never under 32: NDI keeps 11 of the 16 bits
    static func depthCode(_ m: Float, near: Float, far: Float) -> UInt16 {
        guard m.isFinite, m > 0, m <= far, far > near, near > 0 else { return 4096 }
        let v = (1 / max(m, near) - 1 / far) / (1 / near - 1 / far)
        return 4096 + UInt16(max(32, min(56064, (v * 56064).rounded())))
    }

    /// The distance a code stands for (the patch's side of depthCode): m = 1 / (1/far + v (1/near − 1/far)); nil for none
    static func metres(_ c: UInt16, near: Float, far: Float) -> Float? {
        c <= 4096 ? nil : 1 / (1 / far + Float(min(c, 60160) - 4096) / 56064 * (1 / near - 1 / far))
    }

    /// EQ: the greys by how much of the picture is at each distance (Apple's TrueDepth sample, its JET view: histogram equalization;
    /// a face, many pixels within a few centimetres, gets most of them). q: the distances at 33 even shares of the picture, nearest
    /// first (q[0] white, q[32] the darkest); between two of them it is even in metres. Codes for `steps` distances from q[0] to
    /// q[32], to look up
    static func eqCodes(_ q: [Float], steps: Int) -> [UInt16] {
        var out = [UInt16](repeating: 4096, count: steps), k = 0
        let n = q.count - 1, a = q[0], b = q[n]
        for i in 0..<steps {
            let z = a + (b - a) * Float(i) / Float(steps - 1)
            while k < n - 1, z > q[k + 1] { k += 1 }
            let f = q[k + 1] > q[k] ? min(max((z - q[k]) / (q[k + 1] - q[k]), 0), 1) : 0, v = 1 - (Float(k) + f) / Float(n)
            out[i] = 4096 + UInt16(max(32, min(56064, (v * 56064).rounded())))
        }
        return out
    }

    /// DEPTH sent bigger by a whole factor n each way (its long side 1920, VIDEO's largest: TrueDepth x 3, LiDAR x 6): NDI's codec
    /// gives each depth pixel n² times the bits, so the seams of its 8 x 8 blocks show far less, and it lines up with VIDEO pixel for
    /// pixel. A new pixel among neighbours of one
    /// surface (codes within 1024: noise is a few steps of 32, an edge thousands) is their bilinear mix; across an edge or a hole it
    /// copies its own, so nothing new hangs between a face and the wall
    static func enlarge(_ s: UnsafePointer<UInt16>, w: Int, h: Int, by n: Int, into o: UnsafeMutablePointer<UInt16>) {
        func same(_ a: UInt16, _ b: UInt16) -> Bool { a > 4096 && b > 4096 && abs(Int(a) - Int(b)) < 1024 }
        let W = w * n, nn = n * n
        for y in 0..<h {
            let r0 = s + y * w, r1 = s + min(y + 1, h - 1) * w
            for x in 0..<w {
                let x1 = min(x + 1, w - 1), a = r0[x], b = r0[x1], c = r1[x], d = r1[x1]
                let ab = same(a, b), ac = same(a, c), all = ab && ac && same(a, d)
                for j in 0..<n {
                    let line = o + (y * n + j) * W + x * n
                    for i in 0..<n {
                        let ok = i == 0 ? (j == 0 || ac) : j == 0 ? ab : all
                        line[i] = ok ? UInt16((Int(a) * (n - i) * (n - j) + Int(b) * i * (n - j) + Int(c) * (n - i) * j + Int(d) * i * j + nn / 2) / nn) : a
                    }
                }
            }
        }
    }

    /// The distance an EQ code stands for (the patch's side): s = (1 − v) × 32, between q[⌊s⌋] and the next; nil for none
    static func eqMetres(_ c: UInt16, _ q: [Float]) -> Float? {
        guard c > 4096 else { return nil }
        let n = q.count - 1, s = (1 - Float(min(c, 60160) - 4096) / 56064) * Float(n), k = min(Int(s), n - 1)
        return q[k] + (s - Float(k)) * (q[k + 1] - q[k])
    }

    /// DETAIL's tie to the sensor: the network's relative 1/distance (net: nw x nh floats, the top row first, the whole picture as the
    /// depth sees it) as a line s·net + t of the sensor's 1/distance (metres in: w x h, 0 none). Least squares on a grid of about
    /// 160 x 120 of the sensor's pixels, then three times again on the 80% nearest the line (the rest is where the two disagree:
    /// edges, glass, the network's guesses). err: half the pixels are within it of the line (0.01: 1%). Nil when there is no line
    /// (too few pixels). NDI takes it when it rises and err is under 60% (a line is only the start: sharpen adds the sensor's own
    /// shape at large). Fresh each frame: the network divides each frame by its own largest, so its scale moves with whatever comes
    /// nearest
    static func fit(_ m: UnsafePointer<Float>, w: Int, h: Int, net: [Float], nw: Int, nh: Int) -> (s: Float, t: Float, err: Float)? {
        let step = max(1, w / 160)
        var x: [Float] = [], z: [Float] = []
        for j in stride(from: step / 2, to: h, by: step) {
            let q = (Float(j) + 0.5) / Float(h) * Float(nh) - 0.5, j0 = min(max(Int(q.rounded(.down)), 0), nh - 1), j1 = min(j0 + 1, nh - 1)
            let fq = min(max(q - Float(j0), 0), 1)
            for i in stride(from: step / 2, to: w, by: step) {
                let v = m[j * w + i]
                guard v.isFinite, v > 0 else { continue }
                let u = (Float(i) + 0.5) / Float(w) * Float(nw) - 0.5, i0 = min(max(Int(u.rounded(.down)), 0), nw - 1), i1 = min(i0 + 1, nw - 1)
                let fu = min(max(u - Float(i0), 0), 1)
                let a = net[j0 * nw + i0] * (1 - fu) + net[j0 * nw + i1] * fu, b = net[j1 * nw + i0] * (1 - fu) + net[j1 * nw + i1] * fu   // the network there, between its pixels
                x.append(a * (1 - fq) + b * fq); z.append(1 / v)
            }
        }
        guard x.count >= 200 else { return nil }
        var keep = [Bool](repeating: true, count: x.count), s: Float = 0, t: Float = 0, err: Float = 1
        for round in 0..<4 {
            var n = 0.0, sx = 0.0, sxx = 0.0, sz = 0.0, sxz = 0.0
            for k in x.indices where keep[k] { let a = Double(x[k]), b = Double(z[k]); n += 1; sx += a; sxx += a * a; sz += b; sxz += a * b }
            let det = n * sxx - sx * sx
            guard n >= 100, det > 1e-12 else { return nil }
            s = Float((n * sxz - sx * sz) / det); t = Float((sz - Double(s) * sx) / n)
            let e = x.indices.map { abs(s * x[$0] + t - z[$0]) / z[$0] }, sorted = e.sorted()
            err = sorted[sorted.count / 2]
            if round < 3 { let cut = sorted[sorted.count * 4 / 5]; for k in x.indices { keep[k] = e[k] <= cut } }
        }
        return (s, t, err)
    }

    /// DEPTH cleaned on the phone, the depth cameras' own way (Intel's RealSense chain), in 1/distance, where their noise is even:
    /// each pixel against its 3 x 3. At an edge (its nearest and farthest neighbours more than 6% apart) it goes to the side it is
    /// nearer, so nothing hangs between a face and the wall and no hole opens; inside a surface it is the mean of the ones within 2%
    /// of it. A hole with 5 measured neighbours takes the farthest, twice over (from the background: a face does not grow). Steady,
    /// for depth no one smoothed over time (LiDAR's sceneDepth): a pixel within 1.5% of where it was moves 40% of the way, farther is
    /// motion and is taken as it is (ARKit's smoothed depth lags behind motion), a hole keeps its last value two frames. TrueDepth's
    /// raw stream is noisier than iOS's own filter leaves it, so that filter stays on. Its buffers are its own, valid until the next run
    final class Clean {
        private var n = 0, d: UnsafeMutablePointer<Float>?, out: UnsafeMutablePointer<Float>?, prev: UnsafeMutablePointer<Float>?, age: UnsafeMutablePointer<UInt8>?
        static let edge: Float = 0.06, surface: Float = 0.02, still: Float = 0.015, ease: Float = 0.4

        deinit { [d, out, prev].forEach { $0?.deallocate() }; age?.deallocate() }

        /// Metres in (row bytes apart; 0 or not finite: none; sure: a byte a pixel, below 1 none), metres out: w x h floats, 0 none
        func run(_ m: UnsafeRawPointer, row: Int, sure: (UnsafeRawPointer, Int, Int), w: Int, h: Int, steady: Bool) -> UnsafeMutablePointer<Float> {
            if n != w * h {
                [d, out, prev].forEach { $0?.deallocate() }; age?.deallocate()
                n = w * h
                d = .allocate(capacity: n); out = .allocate(capacity: n); prev = .allocate(capacity: n); age = .allocate(capacity: n)
                prev!.update(repeating: 0, count: n); age!.update(repeating: 0, count: n)
            }
            let d = d!, out = out!, prev = prev!, age = age!
            for y in 0..<h {   // 1/distance, 0 none
                var p = m + y * row, c = sure.0 + y * sure.1
                for x in 0..<w {
                    let z = p.load(as: Float.self)
                    d[y * w + x] = c.load(as: UInt8.self) >= 1 && z.isFinite && z > 0 ? 1 / z : 0
                    p += 4; c += sure.2
                }
            }
            for y in 0..<h {
                for x in 0..<w {
                    let c = d[y * w + x]
                    var lo = Float.infinity, hi: Float = 0, k = 0, sum: Float = 0, used: Float = 0
                    for yy in max(y - 1, 0)...min(y + 1, h - 1) {
                        for xx in max(x - 1, 0)...min(x + 1, w - 1) {
                            let v = d[yy * w + xx]
                            guard v > 0 else { continue }
                            lo = min(lo, v); hi = max(hi, v); k += 1
                            if c > 0, abs(v - c) <= Clean.surface * c { sum += v; used += 1 }
                        }
                    }
                    out[y * w + x] = c > 0 ? (hi - lo > Clean.edge * hi ? (hi - c < c - lo ? hi : lo) : sum / used) : k >= 5 ? lo : 0
                }
            }
            for _ in 0..<2 {   // the holes left: from the farther side, inward
                for y in 0..<h {
                    for x in 0..<w where out[y * w + x] == 0 {
                        var lo = Float.infinity, k = 0
                        for yy in max(y - 1, 0)...min(y + 1, h - 1) { for xx in max(x - 1, 0)...min(x + 1, w - 1) where out[yy * w + xx] > 0 { lo = min(lo, out[yy * w + xx]); k += 1 } }
                        if k >= 5 { out[y * w + x] = lo }
                    }
                }
            }
            for i in 0..<n {
                let c = out[i], p = prev[i]
                if c > 0 { if steady, p > 0, abs(c - p) <= Clean.still * p { out[i] = p + Clean.ease * (c - p) }; age[i] = 0 }
                else if steady, p > 0, age[i] < 2 { out[i] = p; age[i] += 1 }
                prev[i] = out[i]
                out[i] = out[i] > 0 ? 1 / out[i] : 0
            }
            return out
        }
    }

    /// A Y'CbCr standard's luma weights (Kr, Kb)
    enum Standard { case bt601, bt709, bt2020 }
    static func weights(_ s: Standard) -> (kr: Double, kb: Double) {
        switch s {
        case .bt601: return (0.299, 0.114)
        case .bt709: return (0.2126, 0.0722)
        case .bt2020: return (0.2627, 0.0593)
        }
    }

    /// The standard NDI reads a size in: SD BT.601, HD Rec.709, above 1920 x 1080 Rec.2020 (frame-types, docs.ndi.video)
    static func standard(w: Int, h: Int) -> Standard { w > 1920 || h > 1080 ? .bt2020 : w > 720 || h > 576 ? .bt709 : .bt601 }

    /// The stored picture's standard, from its attachment (ARKit's and the camera's say), or `fallback`
    static func standard(of px: CVPixelBuffer, _ fallback: Standard) -> Standard {
        guard let m = CVBufferCopyAttachment(px, kCVImageBufferYCbCrMatrixKey, nil) as? String else { return fallback }
        if m == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) { return .bt709 }
        if m == (kCVImageBufferYCbCrMatrix_ITU_R_2020 as String) { return .bt2020 }
        if m == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String) || m == (kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 as String) { return .bt601 }
        return fallback
    }

    /// The colour conversion as one affine map: the stored picture's Y, Cb, Cr as the GPU reads them (0 to 1) to NDI's 8-bit codes
    /// (video range: Y 16 to 235, Cb and Cr 16 to 240), through R'G'B'. Rows for Y, Cb, Cr: (y, cb, cr, 1) dotted with each
    static func convert(from a: Standard, full: Bool, to b: Standard) -> [SIMD4<Float>] {
        let (yo, ys, cs): (Double, Double, Double) = full ? (0, 255, 255) : (16, 219, 224)
        let (ar, ab) = weights(a), ag = 1 - ar - ab
        // the stored code (0 to 1) to R'G'B' (0 to 1): R = Y + crR·Cr, G = Y + cbG·Cb + crG·Cr, B = Y + cbB·Cb (Y and C centred)
        let crR = 2 * (1 - ar), cbB = 2 * (1 - ab), cbG = -2 * ab * (1 - ab) / ag, crG = -2 * ar * (1 - ar) / ag
        func rgb(_ v: SIMD4<Double>) -> SIMD3<Double> {   // v: (y, cb, cr, 1) in 0 to 1
            let y = (v.x * 255 - yo) / ys, cb = (v.y * 255 - 128) / cs, cr = (v.z * 255 - 128) / cs
            return [y + crR * cr, y + cbG * cb + crG * cr, y + cbB * cb]
        }
        let (br, bb) = weights(b), bg = 1 - br - bb
        func out(_ c: SIMD3<Double>) -> SIMD3<Double> {
            let y = br * c.x + bg * c.y + bb * c.z
            return [16 + 219 * y, 128 + 224 * (c.z - y) / (2 * (1 - bb)), 128 + 224 * (c.x - y) / (2 * (1 - br))]
        }
        // affine: read it off at the origin and along each axis
        let o = out(rgb([0, 0, 0, 1])), dy = out(rgb([1, 0, 0, 1])) - o, db = out(rgb([0, 1, 0, 1])) - o, dr = out(rgb([0, 0, 1, 1])) - o
        return (0..<3).map { i in SIMD4<Float>(Float(dy[i]), Float(db[i]), Float(dr[i]), Float(o[i])) }
    }

    /// One frame's metadata, attached to it in NDI: one element of attributes (NDI's rules: no declaration, no namespace, not
    /// starting ndi or ntk). TouchDesigner shows it in an Info DAT on the NDI In TOP. frame counts this source's frames; t is
    /// ARKit's or the camera's clock (seconds), the same on both sources; the lens is the sent picture's, in its pixels; the pose,
    /// when known, is where that camera is (metres) and how it is turned (a quaternion), x right, y up, looking down -z
    static func meta(_ source: String, frame: Int, t: Double, w: Int, h: Int, k: simd_float3x3?, pose: simd_float4x4?, range: (near: Float, far: Float)?, eq: [Float]? = nil) -> String {
        func n(_ v: Float) -> String { String(format: "%.5g", v) }
        var s = "<sensorlove v=\"3\" source=\"\(source)\" frame=\"\(frame)\" t=\"\(String(format: "%.6f", t))\" w=\"\(w)\" h=\"\(h)\""
        if let k { s += " fx=\"\(n(k[0][0]))\" fy=\"\(n(k[1][1]))\" cx=\"\(n(k[2][0]))\" cy=\"\(n(k[2][1]))\"" }
        if let range { s += " near=\"\(n(range.near))\" far=\"\(n(range.far))\"" + (eq.map { " code=\"eq\" eq=\"" + $0.map(n).joined(separator: " ") + "\"" } ?? " code=\"(1/m-1/far)/(1/near-1/far)\"") }
        if let pose {
            let p = pose.columns.3, q = simd_quatf(pose).vector, r = q.w < 0 ? -q : q   // w kept positive: no jumps in a patch
            s += " px=\"\(n(p.x))\" py=\"\(n(p.y))\" pz=\"\(n(p.z))\" qx=\"\(n(r.x))\" qy=\"\(n(r.y))\" qz=\"\(n(r.z))\" qw=\"\(n(r.w))\""
        }
        return s + "/>"
    }
}
