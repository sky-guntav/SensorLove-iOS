// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import CoreMotion

/// The phone's motion and air: CoreMotion's device motion, one fused reading for ATTITUDE, QUAT, GRAVITY, GYRO, ACCEL, U.ACCEL
/// and MAGNET, and the barometer for BARO. Device motion runs while one of its sensors is on, or while the page is on the screen
/// (its cards lean with GRAVITY, sensor on or off); the barometer only while BARO is on. Units as CoreMotion gives them: rad, g,
/// rad/s, µT, kPa, m.
final class Motion {
    static let fused: Set<String> = ["attitude", "quat", "gravity", "gyro", "accel", "useraccel", "mag"]
    var got: ([String: [Float]]) -> Void = { _ in }   // the latest readings by the page's ids, on the queue given
    var asked: (String) -> Void = { _ in }            // MOTION access changed (the barometer's: iOS asks the first time BARO starts)
    private let manager = CMMotionManager(), altimeter = CMAltimeter(), ops = OperationQueue()
    private var baro = false, said = Motion.access

    init(queue: DispatchQueue) { ops.underlyingQueue = queue; ops.maxConcurrentOperationCount = 1 }

    static var access: String {   // ok · no · ask (never asked)
        switch CMAltimeter.authorizationStatus() {
        case .authorized: return "ok"
        case .notDetermined: return "ask"
        default: return "no"
        }
    }

    /// What runs, at the send rate (CoreMotion gives 100 a second at most; 30 at least, for the page's frames; 30 with none of
    /// them on, for the cards' lean). On the queue given
    func run(_ on: Set<String>, hz: Int, lean: Bool) {
        if on.isDisjoint(with: Motion.fused) && !lean { manager.stopDeviceMotionUpdates() } else if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1 / Double(on.isDisjoint(with: Motion.fused) ? 30 : min(max(hz, 30), 100))
            if !manager.isDeviceMotionActive {   // the magnetometer keeps yaw from drifting, and calibrates MAGNET
                let frame: CMAttitudeReferenceFrame = CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryCorrectedZVertical) ? .xArbitraryCorrectedZVertical : .xArbitraryZVertical
                manager.startDeviceMotionUpdates(using: frame, to: ops) { [weak self] m, _ in if let m { self?.read(m) } }
            }
        }
        let air = on.contains("pressure") && CMAltimeter.isRelativeAltitudeAvailable() && Motion.access != "no"
        if air && !baro {
            altimeter.startRelativeAltitudeUpdates(to: ops) { [weak self] d, _ in   // altitude from where it started
                if let d { self?.got(["pressure": [d.pressure.floatValue, d.relativeAltitude.floatValue]]) }
                self?.check()
            }
        } else if !air && baro { altimeter.stopRelativeAltitudeUpdates() }
        baro = air
    }

    /// SETTINGS' MOTION, never asked: a moment of the barometer, so iOS asks. On the queue given
    func ask() {
        guard !baro, CMAltimeter.isRelativeAltitudeAvailable() else { return check() }
        altimeter.startRelativeAltitudeUpdates(to: ops) { [weak self] _, _ in
            guard let self, !self.baro else { return }
            self.altimeter.stopRelativeAltitudeUpdates(); self.check()
        }
    }

    private func check() { let a = Motion.access; if a != said { said = a; asked(a) } }

    private func read(_ m: CMDeviceMotion) {
        let a = m.attitude, q = a.quaternion, g = m.gravity, r = m.rotationRate, u = m.userAcceleration, f = m.magneticField.field
        let v: [String: [Double]] = ["attitude": [a.pitch, a.roll, a.yaw], "quat": [q.x, q.y, q.z, q.w], "gravity": [g.x, g.y, g.z],
                                     "gyro": [r.x, r.y, r.z], "accel": [g.x + u.x, g.y + u.y, g.z + u.z], "useraccel": [u.x, u.y, u.z], "mag": [f.x, f.y, f.z]]
        got(v.mapValues { $0.map { Float($0) } })
    }
}
