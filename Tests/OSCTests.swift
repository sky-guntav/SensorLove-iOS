// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import XCTest
import ARKit
import CoreImage
import UIKit
import Vision
@testable import SensorLove

final class OSCTests: XCTestCase {
    func testOSCQueryHostInfo() {   // DESTINATIONS' FOUND: where an OSCQuery server's OSC goes
        let full = Data("HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{\"NAME\":\"MadMapper\",\"OSC_PORT\":8010,\"OSC_TRANSPORT\":\"TCP\",\"OSC_IP\":\"0.0.0.0\"}".utf8)
        let o = Finder.hostInfo(full)
        XCTAssertEqual(o?.name, "MadMapper"); XCTAssertEqual(o?.port, 8010); XCTAssertEqual(o?.tcp, true); XCTAssertNil(o?.ip)   // 0.0.0.0: the server's own address
        let bare = Finder.hostInfo(Data("HTTP/1.0 200 OK\r\n\r\n{}".utf8))
        XCTAssertNotNil(bare); XCTAssertNil(bare?.port); XCTAssertEqual(bare?.tcp, false)   // nothing said: the HTTP port, over UDP
        XCTAssertNil(Finder.hostInfo(full.prefix(full.count - 5)))   // the body not all there yet
        XCTAssertNil(Finder.hostInfo(Data("HTTP/1.0 404 Not Found\r\n\r\n<html></html>".utf8)))   // not OSCQuery
    }

    func testMessageBytes() {
        // "/a" ended and padded to 4, ",f" the same, then 1.0 as a big-endian float
        XCTAssertEqual([UInt8](OSC.message("/a", [1])), [0x2f, 0x61, 0, 0, 0x2c, 0x66, 0, 0, 0x3f, 0x80, 0, 0])
        XCTAssertEqual(OSC.message("/abc", []).count, 12)   // "/abc" needs a whole 4 more for its zero; "," pads to 4
        XCTAssertEqual([UInt8](OSC.message("/a", [], text: "İz")), [0x2f, 0x61, 0, 0, 0x2c, 0x73, 0, 0, 0xc4, 0xb0, 0x7a, 0])   // ",s", then the text's UTF-8 (İ is two bytes), ended and padded
    }

    func testBundlesFitOneDatagramEach() {
        let m = (0..<100).map { OSC.message("/sensorlove/touch/\($0)", [0, 0, 0.5, 10]) }
        let b = OSC.bundles(m)
        XCTAssertGreaterThan(b.count, 1)
        XCTAssertTrue(b.allSatisfy { $0.count <= OSC.maxPacket && $0.prefix(8) == Data("#bundle\0".utf8) })
        XCTAssertEqual(b.reduce(0) { $0 + $1.count - 16 }, m.reduce(0) { $0 + 4 + $1.count })   // every message in, once, after its size
        XCTAssertEqual(OSC.bundles([]), [])
    }

    func testPrefixAndSLIP() {
        XCTAssertEqual(OSC.address("/sensorlove/gyro/x", prefix: "/phone1"), "/sensorlove/phone1/gyro/x")   // after the root: /sensorlove/* catches every phone
        XCTAssertEqual(OSC.address("/sensorlove/gyro/x", prefix: "phone1/"), "/sensorlove/phone1/gyro/x")
        XCTAssertEqual(OSC.address("/sensorlove/gyro/x", prefix: ""), "/sensorlove/gyro/x")
        XCTAssertEqual([UInt8](OSC.slip(Data([1, 0xC0, 2, 0xDB]))), [0xC0, 1, 0xDB, 0xDC, 2, 0xDB, 0xDD, 0xC0])   // END and ESC inside are escaped
        let tcp = OSC.packets([.init(address: "/a", values: [1])], prefix: "", json: false, tcp: true, time: 0)
        XCTAssertEqual(tcp.count, 1)
        XCTAssertEqual(tcp[0].first, 0xC0)
        XCTAssertEqual(tcp[0].last, 0xC0)
    }

    func testJSONIsOneObjectPerTick() {
        let m: [OSC.Message] = [
            .init(address: "/sensorlove/touch/count", values: [1]),
            .init(address: "/sensorlove/touch/1/x", values: [0.1]),
            .init(address: "/sensorlove/touch/1/radius", values: [9]),
            .init(address: "/sensorlove/mic", values: [.nan]),
            .init(address: "/sensorlove/time/hour", values: [14]),
        ]
        let data = OSC.packets(m, prefix: "/p", json: true, tcp: false, time: 2)
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0].last, 10)
        let o = try? JSONSerialization.jsonObject(with: data[0]) as? [String: Any]
        let touch = o?["touch"] as? [String: Any]
        XCTAssertEqual(o?["prefix"] as? String, "p")
        XCTAssertEqual(touch?["count"] as? Double, 1)
        XCTAssertEqual((touch?["1"] as? [String: Any])?["x"] as? Double, 0.1)   // the Float's own digits, not 0.10000000149
        XCTAssertEqual((touch?["1"] as? [String: Any])?["radius"] as? Double, 9)
        XCTAssertEqual(o?["mic"] as? Double, 0)        // NaN goes as 0: it is no JSON
        XCTAssertEqual(o?["timestamp"] as? Double, 2)   // the tick's clock, beside TIME's values, not under them
        XCTAssertEqual((o?["time"] as? [String: Any])?["hour"] as? Double, 14)
        let place = OSC.packets([.init(address: "/sensorlove/location/lat", values: [41]), .init(address: "/sensorlove/location/address", text: "Fatih")], prefix: "", json: true, tcp: false, time: 0)
        let location = (try? JSONSerialization.jsonObject(with: place[0]) as? [String: Any])?["location"] as? [String: Any]
        XCTAssertEqual(location?["address"] as? String, "Fatih")   // a text beside the numbers
        XCTAssertEqual(location?["lat"] as? Double, 41)
    }

    func testOnlyWhatChangedGoesOut() {
        var sent: Sender.Sent = [:]
        let a = OSC.Message(address: "/a", values: [1]), b = OSC.Message(address: "/b", values: [2]), b3 = OSC.Message(address: "/b", values: [3])
        XCTAssertEqual(Sender.fresh([a, b], &sent, now: 0).count, 2)                           // the first time, all
        XCTAssertEqual(Sender.fresh([a, b], &sent, now: 0.1).count, 0)                         // nothing changed: nothing
        XCTAssertEqual(Sender.fresh([a, b], &sent, now: 0.25).count, 2)                        // once more, 0.2 s on
        XCTAssertEqual(Sender.fresh([a, b], &sent, now: 5).count, 0)                           // then never while the same
        XCTAssertEqual(Sender.fresh([a, b3], &sent, now: 6).map(\.address), ["/b"])            // what changed
        XCTAssertEqual(Sender.fresh([a, b3], &sent, now: 6.3).map(\.address), ["/b"])          // and its one more
        let t1 = OSC.Message(address: "/t", text: "A"), t2 = OSC.Message(address: "/t", text: "B")
        XCTAssertEqual(Sender.fresh([t1], &sent, now: 7).count, 1)
        XCTAssertEqual(Sender.fresh([t2], &sent, now: 7.1).count, 1)                            // a text that changed goes too
        XCTAssertEqual(Sender.fresh([t2], &sent, now: 7.4).count, 1)                            // its one more
        XCTAssertEqual(Sender.fresh([t2], &sent, now: 9).count, 0)
        XCTAssertEqual(Sender.fresh([t2], &sent, now: 12.2).count, 1)                           // and again every 5 s, for a receiver opened later
        let h = OSC.Message(address: OSC.root + "/time/hour", values: [14])
        XCTAssertEqual(Sender.fresh([h], &sent, now: 20).count, 1)
        XCTAssertEqual(Sender.fresh([h], &sent, now: 20.3).count, 1)                            // its one more
        XCTAssertEqual(Sender.fresh([h], &sent, now: 24).count, 0)
        XCTAssertEqual(Sender.fresh([h], &sent, now: 25.1).count, 1)                            // TIME's (and WEATHER's) slow values too, every 5 s
    }

    func testTimeAndWeather() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 14, minute: 30, second: 15, nanosecond: 500_000_000))!
        let c = Sender.clock(d, cal)
        XCTAssertEqual(c.count, Sender.numbers("time").count)
        XCTAssertEqual(c[0], 14); XCTAssertEqual(c[1], 30); XCTAssertEqual(c[2], 15.5, accuracy: 1e-3)
        XCTAssertEqual(c[3], Float((14 * 3600 + 30 * 60 + 15.5) / 86400), accuracy: 1e-6)
        XCTAssertEqual(Array(c[4...]), [2026, 10, 13, 2, 286])   // a Tuesday, the year's 286th day
        let v = Weather.values(["temperature_2m": 21.5, "apparent_temperature": 20.1, "relative_humidity_2m": 60, "precipitation": 0, "cloud_cover": 75,
                                "wind_speed_10m": 3.2, "wind_direction_10m": 270, "pressure_msl": 1013.2, "is_day": 1, "weather_code": 61])
        XCTAssertEqual(v?.count, Sender.numbers("weather").count)   // the text is not a reading
        XCTAssertEqual(v?.first, 21.5); XCTAssertEqual(v?.last, 61)
        XCTAssertEqual(Weather.sky(61), "LIGHT RAIN")
        XCTAssertNil(Weather.values(["temperature_2m": 21.5]))     // an answer short of a value is none
    }

    func testTuneLikeThePage() {
        var t = Sender.Tune(zero: [1, 0], sm: 0)
        XCTAssertEqual(Sender.tuned([3, 2], &t, now: 0), [2, 2])                               // ZERO comes off, OFF does not smooth
        t = Sender.Tune(sm: 1)
        XCTAssertEqual(Sender.tuned([0], &t, now: 0), [0])                                     // the first reading as it is
        XCTAssertEqual(Sender.tuned([1], &t, now: 1.0 / 12)[0], 0.35, accuracy: 1e-5)          // LO: 0.35 of the way in a twelfth of a second
        XCTAssertEqual(Sender.tuned([1], &t, now: 3.0 / 12)[0], 1 - 0.65 * 0.65 * 0.65, accuracy: 1e-5)   // the same pace at any rate
    }

    func testEverySensorIsListed() {
        let ids = ["attitude", "quat", "gravity", "gyro", "accel", "useraccel", "location", "mag", "pressure", "weather", "touch", "mic", "prox", "battery", "time", "face", "hand"]
        XCTAssertEqual(Set(Sender.space.keys), Set(ids))
        XCTAssertTrue(Sender.space.values.joined().allSatisfy { $0.count == 2 && $0[0].hasPrefix(OSC.root + "/") })   // an address, what its one value is
        XCTAssertTrue(Sender.space.values.joined().allSatisfy { !($0[0].last?.isNumber ?? true) })   // TouchDesigner would run a value's number into a digit
        XCTAssertEqual(Sender.space["face"]?.count, 17 + 52)   // the head's values, then ARKit's 52 by their own names
        XCTAssertEqual(Sender.numbers("location").count, 5)    // the address is a text: no reading of its own, no CSV column
    }

    func testHandGesturesByThePagesRules() {
        func hand(open: Bool) -> [[Float]] {   // a wrist, each finger's base a little above it, its tip far above (open) or back by the base (a fist)
            var lm = [[Float]](repeating: [0.5, 0.8, 1], count: 21)
            for (tip, base) in [(4, 1), (8, 5), (12, 9), (16, 13), (20, 17)] { lm[base] = [0.5, 0.7, 1]; lm[tip] = [0.5, open ? 0.5 : 0.72, 1] }
            return lm
        }
        XCTAssertEqual(Hand.up(hand(open: true)), [true, true, true, true, true])
        XCTAssertEqual(Hand.up(hand(open: false)), [false, false, false, false, false])
        let open = Hand.scores(hand(open: true)), fist = Hand.scores(hand(open: false))
        XCTAssertEqual(open.firstIndex(of: open.max()!), 2)   // OPEN PALM
        XCTAssertEqual(fist.firstIndex(of: fist.max()!), 1)   // FIST
    }

    func testHandsSideAndRealPicture() {
        XCTAssertEqual(Hand.left(.left, mirrored: false), 1)   // the back camera: Vision's left hand is your left
        XCTAssertEqual(Hand.left(.left, mirrored: true), 0)    // the front one's frame is a mirror: its left hand is your right
        XCTAssertEqual(Hand.left(.unknown, mirrored: true), 0.5)
        XCTAssertTrue(Hand.swaps([1, nil]) && Hand.swaps([nil, 0]) && Hand.swaps([1, 0]))   // a right hand in H1 goes to H2 (free, or its hand wants H1)
        XCTAssertFalse(Hand.swaps([0, 1]) || Hand.swaps([1, 1]) || Hand.swaps([0, 0]) || Hand.swaps([nil, 1]) || Hand.swaps([0, nil]))   // in place, or both sure of one side: they stay
        var px: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1280, 720, kCVPixelFormatType_32BGRA, nil, &px)   // a camera frame, on its side as it comes
        let d = px.flatMap { Hand.picture($0, .leftMirrored, CIContext()) }
        XCTAssertEqual(d.flatMap(UIImage.init(data:))?.size, CGSize(width: 108, height: 192))   // upright and small
    }

    func testFaceIsSentMirroredInThePagesOrder() {
        XCTAssertEqual(Face.shapes.count, 52)
        XCTAssertEqual(Set(Face.shapes.map(\.rawValue)).count, 52)
        XCTAssertEqual(Face.shapes.first, .eyeBlinkRight); XCTAssertEqual(Face.shapes[7], .eyeBlinkLeft)   // Sender.space's eyeBlinkLeft is your left eye: ARKit's right one (its face is your mirror image)
        XCTAssertEqual(Face.shapes[15], .jawRight); XCTAssertEqual(Face.shapes[17], .jawOpen); XCTAssertEqual(Face.shapes.last, .tongueOut)   // a way to one side turns round too; one with no side stays
        func near(_ a: [Float], _ b: [Float], _ what: String) { XCTAssertTrue(zip(a, b).allSatisfy { abs($0 - $1) < 1e-5 }, what + ": \(a)") }
        var m = matrix_identity_float4x4   // ARKit's portrait camera space, as read on the phone: already your mirror, you in front at z -0.37, no turn
        m.columns.3 = [0.05, -0.1, -0.37, 1]   // 5 cm to your right, 10 down
        near(Face.head(m), [0.05, -0.1, -0.37, 0, 0, 0, 1], "straight at the phone: as ARKit gives it")
        let s = sin(Float(0.25)), c = cos(Float(0.25))
        near(Array(Face.head(simd_float4x4(simd_quatf(angle: 0.5, axis: [0, 1, 0])))[3...]), [0, s, 0, c], "a turn about y as it is (the page's frog looks right)")
        XCTAssertEqual(Face.orientation(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)), .right)   // x' = 1 - y, y' = x: a quarter turn
        XCTAssertEqual(Face.orientation(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)), .leftMirrored)   // x' = y, y' = x: the camera's mirror
        XCTAssertEqual(Face.orientation(CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 1, ty: 1)), .rightMirrored)
    }

    func testTakeRowsAreTouchDesignerChannels() {
        XCTAssertEqual(Take.header(["/sensorlove/accel/x", "/sensorlove/mic"]), "time,sensorlove/accel/x,sensorlove/mic\n")   // OSC In's channel names
        XCTAssertEqual(Take.line(1.23456, [0.1, nil, .nan, -2]), "1.235,0.1,,,-2.0\n")   // no value, or none to write: an empty cell
        XCTAssertEqual(Sender.touches.count, 1 + 5 * 4)
        XCTAssertTrue(Sender.touches.allSatisfy { !($0.last?.isNumber ?? true) })
    }
}
