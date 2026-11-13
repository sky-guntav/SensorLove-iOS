// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import XCTest
import ImageIO
import simd
@testable import SensorLove

final class FramesTests: XCTestCase {
    private let all: [CGImagePropertyOrientation] = [.up, .upMirrored, .down, .downMirrored, .left, .leftMirrored, .right, .rightMirrored]

    func testLookStandsTheCornersUp() {   // the stored top left, where each orientation's own definition puts it
        let w: Float = 4, h: Float = 3, tl: SIMD2<Float> = [0, 0]
        XCTAssertEqual(Frames.place(tl, w: w, h: h, Frames.look(.right)), [h, 0])         // turned clockwise: the top right
        XCTAssertEqual(Frames.place(tl, w: w, h: h, Frames.look(.left)), [0, w])          // anticlockwise: the bottom left
        XCTAssertEqual(Frames.place(tl, w: w, h: h, Frames.look(.down)), [w, h])
        XCTAssertEqual(Frames.place(tl, w: w, h: h, Frames.look(.upMirrored)), [w, 0])
        XCTAssertEqual(Frames.place(tl, w: w, h: h, Frames.look(.leftMirrored)), [0, 0])  // a quarter turn clockwise, then the mirror
        XCTAssertEqual(Frames.size(1920, 1080, Frames.look(.right)).w, 1080)
    }

    func testTurningFurtherIsTurningThePicture() {   // a look turned by q stands the picture up, then turns it q quarters clockwise
        let w: Float = 8, h: Float = 6, p: SIMD2<Float> = [1, 2]
        for o in all {
            let l = Frames.look(o), s = Frames.size(8, 6, l)
            for q in 0..<4 {
                var e = Frames.place(p, w: w, h: h, l), ew = Float(s.w), eh = Float(s.h)
                for _ in 0..<q { e = [eh - e.y, e.x]; swap(&ew, &eh) }   // one more quarter, clockwise
                XCTAssertEqual(Frames.place(p, w: w, h: h, Frames.turned(l, by: q)), e, "\(o) + \(q)")
            }
        }
    }

    func testSourceIsPlacesInverse() {   // each stood-up pixel finds the stored pixel that lands on it
        let w = 6, h = 4
        for o in all {
            let l = Frames.look(o), s = Frames.size(w, h, l)
            for y in 0..<s.h { for x in 0..<s.w {
                let p = Frames.source(x, y, w: w, h: h, l)
                XCTAssertTrue((0..<w).contains(p.x) && (0..<h).contains(p.y), "\(o)")
                XCTAssertEqual(Frames.place([Float(p.x) + 0.5, Float(p.y) + 0.5], w: Float(w), h: Float(h), l), [Float(x) + 0.5, Float(y) + 0.5], "\(o) \(x) \(y)")
            } }
        }
    }

    func testWalkIsSourceARowAtATime() {   // DEPTH's fast loop: a row's start and step give every pixel source gives
        let w = 6, h = 4
        for o in all {
            let l = Frames.look(o), s = Frames.size(w, h, l)
            for y in 0..<s.h {
                let r = Frames.walk(y, w: w, h: h, l)
                for x in 0..<s.w { XCTAssertTrue(Frames.source(x, y, w: w, h: h, l) == (r.x + x * r.dx, r.y + x * r.dy), "\(o) \(x) \(y)") }
            }
        }
    }

    func testOrientationIsLooksInverse() {   // the cards' pictures (Core Image) stand up as the sent frames do
        for o in all { XCTAssertEqual(Frames.orientation(Frames.look(o)), o) }
    }

    func testQuarterFromGravity() {
        XCTAssertEqual(Frames.quarter(gravity: [0, -1, 0], was: 2), 0)        // upright
        XCTAssertEqual(Frames.quarter(gravity: [1, 0, 0], was: 0), 1)         // its right side down: its top points right
        XCTAssertEqual(Frames.quarter(gravity: [-1, 0, 0], was: 0), 3)        // its left side down
        XCTAssertEqual(Frames.quarter(gravity: [0, 1, 0], was: 0), 2)         // upside down
        XCTAssertEqual(Frames.quarter(gravity: [0.05, -0.1, -0.99], was: 3), 3)   // flat: as it was
        XCTAssertEqual(Frames.quarter(gravity: [0.6, -0.65, 0], was: 1), 1)   // halfway: as it was
    }

    func testLensAndPoseFollowThePicture() {   // a point seen by the stored camera lands where the stood-up lens and pose put it
        let k = simd_float3x3([1450, 0, 0], [0, 1452, 0], [962, 718, 1]), w: Float = 1920, h: Float = 1440
        let pose = simd_float4x4(simd_quatf(angle: 0.7, axis: simd_normalize([0.3, 1, 0.2]))) * simd_float4x4([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0.2, -0.1, 0.4, 1])
        let points: [SIMD3<Float>] = [[0.1, 0.2, -1.5], [-0.4, 0.1, -2], [0.3, -0.25, -1]].map { (pose * SIMD4<Float>($0, 1)).xyz }   // in front of it
        for o in all {
            let l = Frames.look(o), k2 = Frames.lens(k, w: w, h: h, l)
            var p2 = Frames.pose(pose, Frames.Look(turns: l.turns, mirror: false))!
            if l.mirror { p2.columns.0 = -p2.columns.0 }   // a mirror is the camera's x the other way (no true pose: Frames.pose says nil)
            XCTAssertEqual(Frames.pose(pose, l) == nil, l.mirror)
            for p in points {
                let a = Frames.place(Frames.project(p, k: k, pose: pose)!, w: w, h: h, l), b = Frames.project(p, k: k2, pose: p2)!
                XCTAssertEqual(a.x, b.x, accuracy: 0.01, "\(o)"); XCTAssertEqual(a.y, b.y, accuracy: 0.01, "\(o)")
            }
        }
    }

    func testDepthCode() {
        XCTAssertEqual(Frames.depthCode(0, near: 0.5, far: 5), 4096)        // nothing measured: black
        XCTAssertEqual(Frames.depthCode(.nan, near: 0.5, far: 5), 4096)
        XCTAssertEqual(Frames.depthCode(9, near: 0.5, far: 5), 4096)        // beyond FAR: black too
        XCTAssertEqual(Frames.depthCode(0.5, near: 0.5, far: 5), 60160)     // NEAR: white (video range)
        XCTAssertEqual(Frames.depthCode(0.2, near: 0.5, far: 5), 60160)     // closer: white too
        XCTAssertEqual(Frames.depthCode(5, near: 0.5, far: 5), 4096 + 32)   // FAR: as dark as NDI still tells from black
        XCTAssertEqual(Frames.depthCode(1 / 1.1, near: 0.5, far: 5), 4096 + 28032)   // halfway in 1/m: 1.1 between 2 and 0.2
        XCTAssertEqual(Frames.depthCode(1, near: 0, far: 5), 4096)          // no near: nothing (1/0)
        for m: Float in [0.61, 1.234, 4.9] { XCTAssertEqual(Frames.metres(Frames.depthCode(m, near: 0.5, far: 5), near: 0.5, far: 5)!, m, accuracy: m * m * 3e-5) }   // 16 bits: a step's error grows with m²
        XCTAssertNil(Frames.metres(4096, near: 0.5, far: 5))
        // a face's 10 cm at half a metre, FAR 5 m: 4 times the codes metres gave it (0 to 5 m, linear)
        let face = Int(Frames.depthCode(0.45, near: 0.2, far: 5)) - Int(Frames.depthCode(0.55, near: 0.2, far: 5))
        XCTAssertGreaterThan(face, 4 * 56064 / 50)
    }

    func testCleanSnapsEdgesFillsHolesAndSteadies() {   // a face at 0.5 m before a wall at 1.5 m, a flying pixel between them, a pinhole in the face
        let w = 8, h = 6, c = Frames.Clean(), all: UInt8 = 1
        var m = [Float](repeating: 1.5, count: w * h)
        for y in 0..<h { for x in 0..<4 { m[y * w + x] = 0.5 } }
        m[2 * w + 4] = 1.0; m[3 * w + 1] = .nan
        func run(_ m: [Float]) -> [Float] {
            withUnsafePointer(to: all) { s in m.withUnsafeBytes { Array(UnsafeBufferPointer(start: c.run($0.baseAddress!, row: w * 4, sure: (UnsafeRawPointer(s), 0, 0), w: w, h: h, steady: true), count: w * h)) } }
        }
        let a = run(m)
        for (i, v) in a.enumerated() { XCTAssertTrue(abs(v - 0.5) < 0.001 || abs(v - 1.5) < 0.001, "pixel \(i) hangs at \(v)") }   // nothing between face and wall
        XCTAssertEqual(a[2 * w + 4], 1.5, accuracy: 0.001)   // the flying pixel went to the side it was nearer (in 1/distance)
        XCTAssertEqual(a[3 * w + 1], 0.5, accuracy: 0.001)   // the pinhole: filled
        m[3 * w + 1] = 0.5; m[4 * w + 1] = 0.502             // 2 mm of noise: mostly averaged away, in space and over time
        XCTAssertEqual(run(m)[4 * w + 1], 0.5, accuracy: 0.0005)
        let moved = m.map { $0 == 0.5 || $0 == 0.502 ? Float(0.55) : $0 }   // the face moved 5 cm: taken as it is, no trail
        XCTAssertEqual(run(moved)[3 * w + 1], 0.55, accuracy: 0.0005)
    }

    func testEQSpreadsTheGreysByHistogram() {   // Apple's TrueDepth sample's look: where many pixels are, many greys
        let q = (0...32).map { i -> Float in i < 24 ? 0.40 + 0.005 * Float(i) : 0.52 + 0.2 * Float(i - 24) }   // a face: 3/4 of the picture within 12 cm, then the room to 2.1 m
        let lut = Frames.eqCodes(q, steps: 4096)
        XCTAssertEqual(lut.first, 60160); XCTAssertEqual(lut.last, 4096 + 32)        // nearest white, farthest the darkest grey
        XCTAssertTrue(zip(lut, lut.dropFirst()).allSatisfy { $0 >= $1 })              // farther is never brighter
        let face = Int(lut[0]) - Int(lut[Int((0.515 - 0.40) / (q[32] - 0.40) * 4095)])   // the face's 11.5 cm: most of the greys
        XCTAssertGreaterThan(face, 56064 * 2 / 3)
        for z: Float in [0.41, 0.47, 1.3] {                                          // the table decodes back to metres
            let c = lut[Int(((z - q[0]) / (q[32] - q[0]) * 4095).rounded())]
            XCTAssertEqual(Frames.eqMetres(c, q)!, z, accuracy: 0.003)
        }
        let s = Frames.meta("DEPTH", frame: 1, t: 0, w: 2, h: 2, k: nil, pose: nil, range: (q[0], q[32]), eq: q)
        XCTAssertTrue(s.contains(" code=\"eq\" eq=\"0.4 0.405 ") && s.utf8.count < 1024)
    }

    func testEnlargeKeepsEdgesAndSmoothsSurfaces() {   // DEPTH sent bigger: a face (about 50000) beside the wall (10000)
        let s: [UInt16] = [50000, 50064, 10000,
                           50032, 50096, 10000]
        var o = [UInt16](repeating: 0, count: 6 * 4), o3 = [UInt16](repeating: 0, count: 9 * 6)
        s.withUnsafeBufferPointer { p in o.withUnsafeMutableBufferPointer { Frames.enlarge(p.baseAddress!, w: 3, h: 2, by: 2, into: $0.baseAddress!) } }
        s.withUnsafeBufferPointer { p in o3.withUnsafeMutableBufferPointer { Frames.enlarge(p.baseAddress!, w: 3, h: 2, by: 3, into: $0.baseAddress!) } }
        XCTAssertEqual(o3[1], 50021)                     // a third of the way from 50000 to 50064
        XCTAssertTrue(o3.allSatisfy { $0 < 11024 || $0 > 48976 })
        XCTAssertEqual(o[1], 50032)                      // between two face pixels: their mean
        XCTAssertEqual(o[3], 50064)                      // between the face and the wall: its own
        XCTAssertEqual(o[6 + 1], 50048)                  // amid four of the face: the mean of the four
        XCTAssertTrue(o.allSatisfy { $0 < 11024 || $0 > 48976 })   // nothing new hangs between face and wall
    }

    func testFitTiesTheNetworkToTheSensor() {   // DETAIL: the sensor's 1/distance is 0.5 × the network's + 0.25, a tenth of the pixels wild, one none
        let nw = 52, nh = 39, w = 64, h = 48
        let net = (0..<(nw * nh)).map { k in 1 + Float(k % nw) / Float(nw) + Float(k / nw) / Float(nh) }   // a slope both ways: bilinear is exact on it
        var m = [Float](repeating: 0, count: w * h)
        for j in 0..<h {
            for i in 0..<w {
                let u = min(max((Float(i) + 0.5) / Float(w) * Float(nw) - 0.5, 0), Float(nw - 1)), q = min(max((Float(j) + 0.5) / Float(h) * Float(nh) - 0.5, 0), Float(nh - 1))
                m[j * w + i] = (i * 7 + j * 3) % 10 == 0 ? 3 : 1 / (0.5 * (1 + u / Float(nw) + q / Float(nh)) + 0.25)
            }
        }
        m[5] = 0
        guard let f = m.withUnsafeBufferPointer({ Frames.fit($0.baseAddress!, w: w, h: h, net: net, nw: nw, nh: nh) }) else { return XCTFail("no fit") }
        XCTAssertEqual(f.s, 0.5, accuracy: 0.001)
        XCTAssertEqual(f.t, 0.25, accuracy: 0.001)
        XCTAssertLessThan(f.err, 0.001)
        XCTAssertNil([Float](repeating: 0, count: w * h).withUnsafeBufferPointer { Frames.fit($0.baseAddress!, w: w, h: h, net: net, nw: nw, nh: nh) })   // nothing measured
    }

    func testColourConversion() {
        func apply(_ m: [SIMD4<Float>], _ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(m.map { simd_dot($0, SIMD4(v, 1)) }) }
        func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ why: String) { for i in 0..<3 { XCTAssertEqual(a[i], b[i], accuracy: 0.05, why) } }
        let same = Frames.convert(from: .bt709, full: false, to: .bt709)
        near(apply(same, [235, 128, 128] / 255), [235, 128, 128], "709 video range stays itself: white")
        near(apply(same, [16, 200, 60] / 255), [16, 200, 60], "and any colour")
        let ar = Frames.convert(from: .bt601, full: true, to: .bt709)   // ARKit's camera (420f) to NDI's
        near(apply(ar, [1, 128.0 / 255, 128.0 / 255]), [235, 128, 128], "full-range white to video-range white")
        near(apply(ar, [0, 128.0 / 255, 128.0 / 255]), [16, 128, 128], "black")
        near(apply(ar, [76.245 / 255, 84.97 / 255, 255.5 / 255]), [62.56, 102.34, 240], "601 full-range red is 709's red")
    }

    func testNDIReadsTheStandardFromTheSize() {
        XCTAssertEqual(Frames.standard(w: 1920, h: 1080), .bt709)
        XCTAssertEqual(Frames.standard(w: 1080, h: 1920), .bt2020)   // standing up, an HD picture is taller than HD: NDI reads it as UHD
        XCTAssertEqual(Frames.standard(w: 1280, h: 720), .bt709)
        XCTAssertEqual(Frames.standard(w: 640, h: 480), .bt601)
        XCTAssertEqual(Frames.standard(w: 256, h: 192), .bt601)
    }

    func testMetadata() {
        let k = simd_float3x3([212.4, 0, 0], [0, 212.6, 0], [128.1, 95.7, 1])
        let flipped = simd_float4x4(simd_quatf(ix: 0, iy: 0, iz: 1, r: 0)) * simd_float4x4(simd_quatf(angle: 0.2, axis: [0, 0, 1]))   // a turn whose quaternion comes out with w below 0 or above
        let s = Frames.meta("DEPTH", frame: 42, t: 5321.204118, w: 256, h: 192, k: k, pose: flipped, range: (0.42, 5))
        XCTAssertTrue(s.hasPrefix("<sensorlove v=\"3\" source=\"DEPTH\" frame=\"42\" t=\"5321.204118\" w=\"256\" h=\"192\" fx=\"212.4\""))
        XCTAssertTrue(s.hasSuffix("/>") && s.contains(" near=\"0.42\" far=\"5\" code=\"(1/m-1/far)/(1/near-1/far)\"") && s.contains(" qw=\"") && !s.contains(" qw=\"-"))
        XCTAssertLessThan(s.utf8.count, 1024)                                  // NDI wants metadata small
        XCTAssertTrue(s.allSatisfy(\.isASCII))
        XCTAssertFalse(Frames.meta("VIDEO", frame: 0, t: 0, w: 2, h: 2, k: nil, pose: nil, range: nil).contains("fx="))
    }
}

private extension SIMD4 where Scalar == Float { var xyz: SIMD3<Float> { [x, y, z] } }
