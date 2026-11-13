// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import Accelerate
import AVFoundation
import Contacts
import CoreLocation
import MapKit
import UIKit

/// The rest of SENSORS: LOCATION (CoreLocation, its address and map from Apple), MIC (how loud it is), PROX (the sensor by the
/// earpiece) and BATTERY; and CAMERA's access, for FACE and HAND. Each runs only while its sensor is on, and asks iOS the first
/// time it starts; off the screen only with IN BACKGROUND, which also keeps SensorLove awake there. Lives on the main thread
/// (CoreLocation and UIDevice want it).
final class Phone: NSObject, CLLocationManagerDelegate {
    var got: ([String: [Float]]) -> Void = { _ in }       // readings by the page's ids, from any thread
    var asked: (String, String) -> Void = { _, _ in }     // LOCATION, MIC or CAMERA access changed: location · mic · camera, then ok · no · ask
    var placed: (String, String) -> Void = { _, _ in }    // the address (LOCATION's, WEATHER's): the whole line (LOCATION's OSC), a short one (the page)
    var said: (String) -> Void = { _ in }                 // a line for the page's console
    var bg = true, away = false                           // IN BACKGROUND, and SensorLove off the screen (another app, or the lock): set them, then apply()
    var worth = true                                      // something goes out off the screen (a destination, or REC): else staying awake only spends the battery
    var listen = false                                    // VIDEO's AUDIO wants the mic too (NDI): set it, then apply()
    var heard: (AVAudioPCMBuffer) -> Void = { _ in }      // the mic's sound itself, for VIDEO's AUDIO, while listen; on the audio thread
    private let locator = CLLocationManager(), engine = AVAudioEngine(), quiet = AVAudioEngine(), geocoder = CLGeocoder()   // engine hears (MIC), quiet plays silence
    private var on: Set<String> = [], course: Float = 0, hearing = false, awake = false, tapped = false
    private var placedAt: CLLocation?, askedAt = Date.distantPast, placing = false, placeSaid = ""
    private var snapper: MKMapSnapshotter?

    override init() {
        super.init()
        locator.delegate = self
        locator.desiredAccuracy = kCLLocationAccuracyBest
        locator.pausesLocationUpdatesAutomatically = false   // off the screen too, standing still: a location that stops is no sensor
        let center = NotificationCenter.default
        center.addObserver(forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.near() }
        for n in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            center.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.charge() }
        }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in   // a call takes the audio
            guard let self else { return }
            let began = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue
            if self.hearing { self.say("MIC · INTERRUPTED: " + (began ? "BEGAN" : "ENDED")) }
            if !began { self.again() }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in self?.again() }   // headphones in or out: the engine stopped under it
    }

    func access(_ k: String) -> String {   // ok · no · ask (never asked)
        if k == "location" {
            switch locator.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: return "ok"
            case .notDetermined: return "ask"
            default: return "no"
            }
        }
        if k == "camera" {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return "ok"
            case .notDetermined: return "ask"
            default: return "no"
            }
        }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "ok"
        case .undetermined: return "ask"
        default: return "no"
        }
    }

    func ask(_ k: String) {   // never asked: iOS asks now
        if k == "location" { return locator.requestWhenInUseAuthorization() }   // the answer comes to locationManagerDidChangeAuthorization
        if k == "camera" { return AVCaptureDevice.requestAccess(for: .video) { _ in DispatchQueue.main.async { self.asked("camera", self.access("camera")) } } }
        AVAudioApplication.requestRecordPermission { _ in DispatchQueue.main.async { self.asked("mic", self.access("mic")); self.apply() } }
    }

    func run(_ now: Set<String>) { on = now; apply() }   // what is on (the page's ids)

    /// Each sensor as it should be now: on, allowed, and on the screen or with IN BACKGROUND (iOS stops PROX off the screen itself).
    /// Off the screen with IN BACKGROUND and something on, the silence keeps SensorLove awake (sound())
    func apply() {
        let live = !away || bg
        let locate = on.contains("location") || on.contains("weather")   // WEATHER asks Open-Meteo for where the phone is
        if !locate || !live { locator.stopUpdatingLocation() } else if access("location") != "ask" { locator.startUpdatingLocation() } else if !away { ask("location") }
        locator.allowsBackgroundLocationUpdates = bg   // the location background mode (project.yml); iOS shows its blue mark meanwhile
        let mic = on.contains("mic") || listen
        if mic && access("mic") == "ask" && !away { ask("mic") }
        let hear = mic && access("mic") == "ok" && live, keep = away && bg && worth && !on.isEmpty
        if hear != hearing || keep != awake { hearing = hear; awake = keep; sound() }
        UIDevice.current.isProximityMonitoringEnabled = on.contains("prox") && !away   // iOS darkens the screen while something is near
        if on.contains("prox") { near() }
        UIDevice.current.isBatteryMonitoringEnabled = on.contains("battery")
        if on.contains("battery") { charge() }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        guard let p = l.last else { return }
        if p.course >= 0 { course = Float(p.course) }   // standing still has no course: the last one stays
        got(["location": [Float(p.coordinate.latitude), Float(p.coordinate.longitude), Float(p.altitude), Float(max(p.speed, 0)), course, Float(p.horizontalAccuracy)]])   // OSC sends five; the page's map also wants how sure the fix is
        if on.contains("location") || on.contains("weather") { place(p) }   // WEATHER shows it too, to tell where its weather is for (OSC: LOCATION's only)
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        asked("location", access("location"))
        apply()
    }

    /// The address of a fix, from Apple, in the phone's language: again only 50 m on, and 30 s after the last ask (Apple limits how
    /// often an app may ask). shortcut: CLGeocoder is deprecated from iOS 26 (MKReverseGeocodingRequest); move once the app needs 26
    private func place(_ p: CLLocation) {
        guard !placing, Date().timeIntervalSince(askedAt) >= 30, placedAt.map({ p.distance(from: $0) >= 50 }) ?? true else { return }
        placing = true; askedAt = Date()
        geocoder.reverseGeocodeLocation(p) { [weak self] marks, e in
            guard let self else { return }
            self.placing = false
            guard let m = marks?.first else { return self.tellPlace("ADDRESS · " + (e.map(Phone.why) ?? "NONE HERE")) }   // no network, or asked too often: a later fix asks again
            self.placedAt = p
            let whole = m.postalAddress.map { CNPostalAddressFormatter.string(from: $0, style: .mailingAddress).split(separator: "\n").joined(separator: ", ") } ?? m.name ?? ""
            let short = [m.name, m.subLocality ?? m.locality].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }   // the street and number (or the place's name), then the district
            self.placed(whole, short.joined(separator: ", "))
            self.tellPlace("ADDRESS · " + whole.uppercased(with: .current))   // what OSC gets, as it gets it
        }
    }

    private func tellPlace(_ s: String) { if s != placeSaid { placeSaid = s; say(s) } }   // each new address, or a new reason there is none, once

    /// LOCATION's map: Apple's map of a square the page asks for (zoom 16 tile pixels from x0, y0, 1280 a side), as a PNG data URL;
    /// nil when it cannot (no network). The page turns its colours into streets, water and green
    func map(x0: Double, y0: Double, done: @escaping (String?) -> Void) {
        let o = MKMapSnapshotter.Options(), look = MKStandardMapConfiguration()
        o.mapRect = MKMapRect(x: x0 * 16, y: y0 * 16, width: 1280 * 16, height: 1280 * 16)   // MapKit's map points are zoom 20's pixels
        o.size = CGSize(width: 1280, height: 1280)
        o.traitCollection = UITraitCollection { $0.userInterfaceStyle = .light }   // the light map, whose colours the page reads
        o.scale = 1                                                              // asked for, but it still comes at the screen's scale: drawn down below
        look.pointOfInterestFilter = .excludingAll; look.showsTraffic = false
        o.preferredConfiguration = look
        let s = MKMapSnapshotter(options: o)
        snapper = s
        s.start { [weak self] shot, e in
            self?.snapper = nil
            if let e { self?.say("MAP · " + e.localizedDescription.uppercased()) }
            let one = UIGraphicsImageRendererFormat(); one.scale = 1   // 1280 px: the screen's 3840 made 2 MB that froze the page for a second and a half
            let png = shot.map { s in UIGraphicsImageRenderer(size: o.size, format: one).pngData { _ in s.image.draw(in: CGRect(origin: .zero, size: o.size)) } }
            done(png.map { "data:image/png;base64," + $0.base64EncodedString() })
        }
    }

    /// The audio as MIC and IN BACKGROUND want it. MIC: the input's loudness, -60 dBFS (a quiet room) to 0 (as loud as it goes) as
    /// 0 to 1, about 45 times a second; other apps' sound plays on (mixWithOthers), quieter on the speaker: measurement mode drops
    /// iOS's loudness processing, in and out. Off the screen with nothing to hear, quiet plays silence,
    /// mixed (other apps' sound untouched): iOS keeps an app awake while it plays. Neither: the session goes. Errors to the console
    private func sound() {
        let s = AVAudioSession.sharedInstance()
        if tapped && !hearing { engine.inputNode.removeTap(onBus: 0); engine.stop(); tapped = false }
        if quiet.isRunning && (hearing || !awake) { quiet.stop() }
        guard hearing || awake else {
            do { try s.setActive(false, options: .notifyOthersOnDeactivation) } catch { say("AUDIO · STOP FAILED: " + Phone.why(error)) }
            return
        }
        do {
            if hearing { try s.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]) }
            else { try s.setCategory(.playback, mode: .default, options: [.mixWithOthers]) }
            try s.setActive(true)
        } catch { say((hearing ? "MIC" : "IN BACKGROUND") + " · SESSION FAILED: " + Phone.why(error)) }
        if hearing && !tapped {
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else { return say("MIC · NO INPUT") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] b, _ in
                guard let d = b.floatChannelData?[0] else { return }
                var rms: Float = 0
                vDSP_rmsqv(d, 1, &rms, vDSP_Length(b.frameLength))
                self?.got(["mic": [max(0, min(1, (20 * log10(max(rms, 1e-7)) + 60) / 60))]])
                if self?.listen == true { self?.heard(b) }
            }
            tapped = true
            do { try engine.start() } catch { say("MIC · ENGINE FAILED: " + Phone.why(error)) }
        }
        if !hearing && !quiet.isRunning {
            _ = quiet.mainMixerNode   // nothing in: the output plays silence
            do { try quiet.start() } catch { say("IN BACKGROUND · CAN'T STAY AWAKE: " + Phone.why(error)) }
        }
    }

    /// The engines from scratch, as they should be: iOS stops them for a call, or when the hardware changes under them (left
    /// stopped, MIC went quiet, and off the screen SensorLove fell asleep)
    private func again() {
        if tapped { engine.inputNode.removeTap(onBus: 0); engine.stop(); tapped = false }
        quiet.stop()
        if hearing || awake { sound() }
    }

    private static func why(_ e: Error) -> String { let n = e as NSError; return "\(n.localizedDescription) (\(n.code))".uppercased() }

    private func say(_ s: String) { said(s) }

    private func near() { got(["prox": [UIDevice.current.proximityState ? 0 : 1]]) }   // 0 near, 1 clear

    private func charge() {   // OSC sends the level; the page's wizard also wants whether it charges
        let d = UIDevice.current
        got(["battery": [max(d.batteryLevel, 0), d.batteryState == .charging ? 1 : 0]])
    }
}
