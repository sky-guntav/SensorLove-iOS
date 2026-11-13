// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import Foundation
import Network
import UIKit

/// Sends the running sensors to the destinations on one clock, at the page's rate (SEND RATE): each tick the values that changed
/// (fresh), as OSC bundles or a JSON object (OSC.swift), over UDP or TCP. What runs, where to and how fast come from the state the
/// page keeps (sensorlove.last); what each sensor sends, from space below.
final class Sender {
    var tell: ([String: Any]) -> Void = { _ in }   // to the page (SL.recv), on the main thread
    private(set) var net = "ask"                    // local network access as far as iOS lets an app tell: ok · no · ask (not known yet). Main thread
    private(set) var ip = ""                        // the phone's address on Wi-Fi, for THIS PHONE; "" off Wi-Fi. Main thread
    private(set) var saved: URL?                    // the last take, for SAVE CSV. Main thread
    private(set) var place = ""                     // the address (LOCATION's, WEATHER's), short, for the page. Main thread

    private let queue: DispatchQueue                 // everything below lives on it
    private var timer: DispatchSourceTimer?
    private var hz = 0
    private var dests: [Dest] = []                  // the ones switched on
    private var links: [String: Link] = [:]         // a connection per host, port and protocol (two destinations may share one)
    private var running: Set<String> = []           // the sensors that are on, by the page's ids
    private var paused = false                      // the page's bypass key
    private var slots = Array(repeating: [Float]([0, 0, 0, 0]), count: 5)   // TOUCH, the page's five: x, y (0 to 1), DOWN, RADIUS (pt); all 0 when up
    private var used = 0                            // the slots touched so far: only those send (no touch, no TOUCH channels)
    private var sent: Sent = [:]
    private var count = 0, countAt = 0.0, mps = 0   // messages out this second, for the page's MSG/S
    private var latest: [String: [Float]] = [:]     // each running sensor's last reading, by the page's ids
    private var tunes: [String: Tune] = [:]         // the page's TUNE: ZERO and SMOOTH, by the page's ids
    private var frameAt = 0.0                       // the page's last frame of readings
    private var take: Take?                         // REC
    private var address = ""                        // LOCATION's address, whole, for OSC (/location/address)
    private var bg = true, away = false             // IN BACKGROUND, and SensorLove off the screen: on, it goes on sending; off, it stops
    private let motion: Motion
    private let weather: Weather                    // WEATHER: Open-Meteo, asked from here
    private var sky = ""                            // WEATHER in words, for OSC (/weather/text)
    private let phone = Phone()                     // LOCATION, MIC, PROX, BATTERY: on the main thread
    private let hand = Hand()                       // HAND: the camera and Vision, on their own queue
    private let face = Face()                       // FACE: ARKit on the front camera, on its own queue (HAND reads its frames then)
    private var hands: [[[Float]]?] = [nil, nil]    // HAND's joints, a slot each, for the page's picture
    private var pic: Data?                          // REAL: the camera's newest frame (JPEG), not yet with the page
    private var mesh: [Int]?                        // REAL: FACE's mesh on it (Face.mesh)
    private var handOn = false, faceOn = false, handFront = true, camHz = 30   // what HAND and FACE want, for camera(). Main thread
    private let ndi = NDI()                         // VIDEO and DEPTH: the cameras' frames as NDI sources
    private var videoOn = false, depthOn = false, ndiWant = NDI.Settings()   // what VIDEO and DEPTH want, for camera(). Main thread
    private var quarters = 0                        // how the phone is held (Frames.quarter), from GRAVITY: VIDEO and DEPTH stand up with it. On the queue
    private var probe: NWConnection?
    private let paths = NWPathMonitor()

    init() {
        let q = DispatchQueue(label: "sender")
        queue = q; motion = Motion(queue: q); weather = Weather(queue: q)
        motion.got = { [weak self] v in self?.latest.merge(v) { $1 } }   // on the queue
        weather.got = { [weak self] v, sky in guard let self, self.running.contains("weather") else { return }; self.latest["weather"] = v; self.sky = sky }   // on the queue
        weather.said = { [weak self] s in DispatchQueue.main.async { self?.tell(["log": s]) } }
        motion.asked = { [weak self] a in DispatchQueue.main.async { self?.tell(["perm": ["motion": a]]) } }
        phone.got = { [weak self] v in self?.queue.async { self?.latest.merge(v) { $1 } } }
        phone.asked = { [weak self] k, a in self?.tell(["perm": [k: a]]); if k == "camera" { self?.camera() } }
        hand.got = { [weak self] v, j in self?.queue.async { guard let self, self.running.contains("hand") else { return }; self.latest["hand"] = v; self.hands = j } }
        hand.saw = { [weak self] d in self?.queue.async { self?.pic = d } }
        face.got = { [weak self] v in self?.queue.async { guard let self, self.running.contains("face") else { return }; self.latest["face"] = v } }
        face.frames = { [weak self] px, t, o in self?.hand.feed(px, t, o) }   // HAND, if it is on, reads them (one front camera for both)
        face.saw = { [weak self] d in self?.queue.async { self?.pic = d } }
        face.mesh = { [weak self] m in self?.queue.async { self?.mesh = m } }
        face.said = { [weak self] s in DispatchQueue.main.async { self?.tell(["log": s]) } }
        face.picture = { [weak self] p in self?.ndi.picture(p) }
        face.depth = { [weak self] d in self?.ndi.depth(d) }
        hand.picture = { [weak self] p in self?.ndi.picture(p) }
        hand.depth = { [weak self] d in self?.ndi.depth(d) }
        phone.heard = { [weak self] b in self?.ndi.audio(b) }
        ndi.told = { [weak self] st in DispatchQueue.main.async { self?.tell(["ndi": st]) } }
        ndi.thumb = { [weak self] id, d in let u = "data:image/jpeg;base64," + d.base64EncodedString(); DispatchQueue.main.async { if self?.phone.away == false { self?.tell(["thumb": [id, u]]) } } }   // the cards' pictures, while the page is on the screen
        ndi.said = { [weak self] s in DispatchQueue.main.async { self?.tell(["log": s]) } }
        phone.said = { [weak self] s in self?.tell(["log": s]) }
        phone.placed = { [weak self] whole, short in
            guard let self else { return }
            self.place = short; self.tell(["addr": short])
            self.queue.async { self.address = whole }
        }
    }

    private struct Dest {
        let name: String, host: String, port: NWEndpoint.Port, prefix: String, tcp: Bool, json: Bool
        var key: String { "\(host):\(port.rawValue)/\(tcp ? "tcp" : "udp")" }
    }

    private final class Link {
        let conn: NWConnection
        var ready = false, retrying = false
        var said = ""                               // the last problem told to the console: each is told once
        init(_ conn: NWConnection) { self.conn = conn }
    }

    func start() {
        paths.pathUpdateHandler = { [weak self] _ in self?.lookAround() }   // also once at the start
        paths.start(queue: queue)
    }

    /// The page's kept state: the running sensors, the rate, the destinations (each checked: the page is not trusted with a port)
    func update(_ last: String?) {
        guard let last, let o = (try? JSONSerialization.jsonObject(with: Data(last.utf8))) as? [String: Any], let s = o["s"] as? [String: Any] else { return }
        let on = Set(s["on"] as? [String] ?? []), rate = min(max(s["hz"] as? Int ?? 60, 1), 240), bg = o["bg"] as? Bool ?? true
        let camhz = (s["camhz"] as? Int).flatMap { [15, 30, 60].contains($0) ? $0 : nil } ?? 30   // the page's CAMERA rate: HAND (and FACE) frames a second
        let ds = (o["dests"] as? [[String: Any]] ?? []).compactMap { d -> Dest? in
            guard d["on"] as? Bool == true, let host = d["host"] as? String, !host.isEmpty,
                  let n = d["port"] as? Int, let p = UInt16(exactly: n), let port = NWEndpoint.Port(rawValue: p), p > 0 else { return nil }
            return Dest(name: d["name"] as? String ?? host, host: host, port: port, prefix: d["prefix"] as? String ?? "", tcp: d["tcp"] as? Bool == true, json: d["json"] as? Bool == true)
        }
        phone.bg = bg; phone.run(on)
        handOn = on.contains("hand"); faceOn = on.contains("face"); handFront = s["cam"] as? String != "BACK"; camHz = min(camhz, rate)   // never more than SEND RATE
        videoOn = on.contains("video"); depthOn = on.contains("depth"); ndiWant = Sender.ndiSettings(s["ndi"] as? [String: Any] ?? [:])
        camera()
        queue.async {   // sent forgotten: a destination just switched on gets what is there
            self.running = on; self.dests = ds; self.bg = bg; self.sent = [:]; self.latest = self.latest.filter { on.contains($0.key) }
            self.motion.run(on, hz: rate, lean: !self.away); self.relink(); self.clock(rate)
        }
    }

    /// SensorLove leaves the screen (another app, the lock) or comes back. IN BACKGROUND on: it goes on sending, kept awake (Phone);
    /// off: it stops at once and goes on when back. Either way the page sleeps meanwhile: no frames for it, no cards to lean
    func leave(_ gone: Bool) {
        queue.async {
            self.away = gone; self.motion.run(self.running, hz: self.hz, lean: !gone)
            let worth = !self.paused && (!self.dests.isEmpty || self.take != nil)   // nothing would go out: no use staying awake
            DispatchQueue.main.async { self.phone.away = gone; self.phone.worth = worth; self.phone.apply(); self.camera(); self.ndi.leave(gone) }
        }
    }

    /// The cameras as they should be now: on, allowed (iOS asks the first time), and SensorLove on the screen (iOS gives an app no
    /// camera off it). One camera at a time, its side the page's CAMERA, the front one while FACE is on (the page's camRule). ARKit
    /// (Face) holds it when something needs ARKit: FACE; MATTE on either side (on the back with world tracking: LiDAR's depth and where
    /// the phone is). Then HAND reads ARKit's frames and VIDEO and DEPTH take them; else HAND's capture is the camera, for HAND, VIDEO
    /// and DEPTH from that side's depth camera, filtered by iOS (TrueDepth: 30 a second against ARKit's 15; LiDAR: sharper and
    /// quicker than ARKit's). DEPTH needs that side's depth camera (TrueDepth on the front, LiDAR on the back).
    /// Main thread
    private func camera() {
        if handOn || faceOn || videoOn || depthOn, phone.access("camera") == "ask", !phone.away { phone.ask("camera") }
        let ok = phone.access("camera") == "ok" && !phone.away, front = faceOn || handFront, matte = videoOn && ndiWant.matte
        let mode: Face.Mode = !ok ? .off : (faceOn || front && matte) && (faceOn || Face.can) ? .face
            : !front && matte && Face.people ? .world : .off   // FACE on a phone with no TrueDepth: Face says so once
        let ar = mode == .world || mode == .face && Face.can   // DEPTH without FACE or MATTE: HAND's capture, that side's depth camera filtered (Hand)
        face.run(Face.Want(mode: mode, face: faceOn && ok, video: videoOn && ok && ar, depth: depthOn && ok && ar, matte: matte, fps: camHz, smooth: ndiWant.smooth, big: videoOn && ndiWant.max))
        hand.run(hand: handOn && ok, video: videoOn && ok, depth: depthOn && ok && (front ? Face.can : Face.lidar), front: front, fps: camHz, ar: ar, hd: ndiWant.hd, max: ndiWant.max, smooth: ndiWant.smooth)
        var n = ndiWant
        n.video = videoOn && ok; n.depth = depthOn && ok && (front ? Face.can : Face.lidar); n.hz = camHz
        ndi.configure(n)
        phone.listen = n.video && n.audio; phone.apply()   // AUDIO: the mic, for VIDEO
        UIApplication.shared.isIdleTimerDisabled = n.video || n.depth   // a source on: the screen stays on (the lock would take the camera)
    }

    /// VIDEO's and DEPTH's settings as the page keeps them (s.ndi), checked: the page is not trusted with a name or a range
    static func ndiSettings(_ o: [String: Any]) -> NDI.Settings {
        var n = NDI.Settings()
        let name = (o["name"] as? String ?? "").uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " " || $0 == "-") }
        n.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "SENSORLOVE" : String(name.prefix(32))
        let size = o["size"] as? Double ?? (o["hd"] as? Bool == false ? 720 : nil)   // 1080 or 720; MAX (the page's word, or nothing yet): the camera's own
        n.max = size == nil; n.hd = size != 720; n.matte = o["matte"] as? Bool == true; n.audio = o["audio"] as? Bool == true
        if let far = o["far"] as? Double { n.far = Float(min(max(far, 0.5), 20)); n.auto = false } else { n.auto = true; n.face = o["far"] as? String == "FACE"; n.eq = o["far"] as? String == "EQ" }   // a number, AUTO, FACE or EQ (the page's words)
        n.smooth = o["smooth"] as? Bool ?? true
        n.detail = o["detail"] as? Bool ?? false
        return n
    }

    func touch(_ f: [[Double]]) {   // the page's touch slots: a finger keeps its slot until it lifts; [x, y, radius], or [] when free
        let page: [[Float]?] = f.prefix(5).map { $0.count == 3 ? $0.map { Float($0) } : nil }
        queue.async {
            for (i, p) in page.enumerated() {
                if let p { self.slots[i] = [p[0], p[1], 1, p[2]]; self.used = max(self.used, i + 1) } else { self.slots[i] = [0, 0, 0, 0] }   // lifted: all 0, nothing left standing
            }
        }
    }

    func bypass(_ on: Bool) { queue.async { self.paused = on } }

    func real(_ on: Bool) { hand.show(on); face.show(on); if !on { queue.async { self.pic = nil; self.mesh = nil } } }   // the page's REAL on the screen, or not any more (whoever has the camera sends it)

    func tune(_ id: String, zero: [Double]?, sm: Int) { queue.async { self.tunes[id] = Tune(zero: zero?.map { Float($0) }, sm: sm) } }   // the page's TUNE changed

    func restart() { queue.async { self.paused = false; self.slots = self.slots.map { _ in [0, 0, 0, 0] }; self.tunes = [:] } }   // a page that starts again: sending, no finger down, no TUNE

    /// REC: a take of the sensors on now (Take.swift); STOP closes it for SAVE CSV. The page hears how it goes: rec { on, rows, t }
    func rec(_ on: Bool) {
        queue.async {
            let now = Date().timeIntervalSince1970
            guard on else { return self.stop(now, failed: false) }
            guard self.take == nil else { return }
            let columns = Sender.live.filter(self.running.contains).flatMap { id -> [String] in id == "touch" ? Sender.touches : Sender.numbers(id).map { $0[0] } }   // numbers only: TouchDesigner's DAT to CHOP reads a text as 0
            do { let t = try Take(columns: columns, start: now); self.take = t; self.told(t, on: true, now) }
            catch { DispatchQueue.main.async { self.tell(["log": "REC · CAN'T MAKE THE FILE"]) } }
        }
    }

    private func stop(_ now: Double, failed: Bool) {
        guard let t = take else { return }
        take = nil
        let ok = (try? t.close()) != nil && !failed
        DispatchQueue.main.async { self.saved = t.url }   // what got there stays
        told(t, on: false, now)
        if !ok { DispatchQueue.main.async { self.tell(["log": "REC · CAN'T WRITE THE FILE"]) } }
    }

    private func told(_ t: Take, on: Bool, _ now: Double) {
        let m: [String: Any] = ["on": on, "rows": t.rows, "t": now - t.start]
        DispatchQueue.main.async { self.tell(["rec": m]) }
    }

    /// Access as iOS tells it, for SETTINGS: ok · no · ask (never asked)
    func perms() -> [String: String] { ["network": net, "motion": Motion.access, "location": phone.access("location"), "mic": phone.access("mic"), "camera": phone.access("camera")] }

    /// SETTINGS asks for one never asked: iOS asks now (LOCAL NETWORK: a knock on a neighbour; MOTION: a moment of the barometer).
    /// Allowed or denied, only iOS Settings changes it: the page asks first, then settings()
    func ask(_ k: String) {
        if k == "motion" { return queue.async { self.motion.ask() } }
        if k != "network" { return phone.ask(k) }
        queue.async {
            guard let here = Sender.local() else { return DispatchQueue.main.async { self.tell(["log": "NO WI-FI"]) } }
            self.knock(here.neighbour)
        }
    }

    func settings() { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }   // SensorLove's page in iOS Settings

    /// The page has (re)loaded, or iOS Settings were open: what it may have missed (LOCAL NETWORK has no API: a new knock tells)
    func resend() {
        tell(["perm": perms(), "ip": ip, "addr": place])
        queue.async { self.lookAround() }
    }

    func map(x0: Double, y0: Double) {   // LOCATION's map, for the page (Phone.map)
        phone.map(x0: x0, y0: y0) { [weak self] png in self?.tell(["map": ["png": png ?? "", "x0": x0, "y0": y0]]) }
    }

    private func lookAround() {   // the network changed (or this is the start): the phone's address, and whether iOS lets it in
        let here = Sender.local()
        DispatchQueue.main.async { if self.ip != here?.ip ?? "" { self.ip = here?.ip ?? ""; self.tell(["ip": self.ip]) } }
        if let here { knock(here.neighbour) }
    }

    /// A connection to a neighbour on the Wi-Fi: iOS asks the first time, and how it goes is the answer (there is no API to ask)
    private func knock(_ host: String) {
        probe?.cancel()
        let c = NWConnection(host: NWEndpoint.Host(host), port: 9, using: .udp)   // 9: discard. Nothing is sent
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c else { return }
            switch state {
            case .ready: self.access("ok"); c.cancel(); if self.probe === c { self.probe = nil }   // done: the next knock has nothing to cancel
            case .waiting(_), .failed(_): if c.currentPath?.unsatisfiedReason == .localNetworkDenied { self.access("no") }
            default: break
            }
        }
        c.start(queue: queue)
        probe = c
    }

    private func access(_ s: String) { DispatchQueue.main.async { if self.net != s { self.net = s; self.tell(["perm": ["network": s]]) } } }

    private func relink() {   // a connection for each destination, none for the ones gone
        let keys = Set(dests.map(\.key))
        for (k, l) in links where !keys.contains(k) { l.conn.cancel(); links[k] = nil }
        for d in dests where links[d.key] == nil { links[d.key] = link(d) }
    }

    private func link(_ d: Dest) -> Link {
        let l = Link(NWConnection(host: NWEndpoint.Host(d.host), port: d.port, using: d.tcp ? .tcp : .udp))
        l.conn.stateUpdateHandler = { [weak self, weak l] state in
            guard let self, let l else { return }
            l.ready = false
            switch state {
            case .ready:
                l.ready = true; l.said = ""; self.access("ok")
            case .waiting(let e), .failed(let e):
                if l.conn.currentPath?.unsatisfiedReason == .localNetworkDenied { self.access("no") } else { self.say(l, d, e) }
                guard !l.retrying else { break }
                l.retrying = true
                self.queue.asyncAfter(deadline: .now() + 2) {   // a receiver that is not up yet: try again (a failed connection is done: a new one)
                    l.retrying = false
                    guard self.links[d.key] === l else { return }
                    if case .failed(_) = state { l.conn.cancel(); self.links[d.key] = self.link(d) } else { l.conn.restart() }
                }
            default:
                break
            }
        }
        l.conn.start(queue: queue)
        return l
    }

    private func say(_ l: Link, _ d: Dest, _ e: NWError) {   // a problem, told to the console once
        let why: String
        switch e {
        case .posix(.ECONNREFUSED): why = "NOTHING LISTENS ON PORT \(d.port.rawValue)"
        case .posix(.ENETUNREACH), .posix(.EHOSTUNREACH), .posix(.ENETDOWN): why = "CAN'T REACH " + d.host
        case .dns(_): why = "NO SUCH HOST " + d.host
        default: why = "NO CONNECTION"
        }
        let text = d.name + ": " + why
        if l.said != text { l.said = text; DispatchQueue.main.async { self.tell(["log": text]) } }
    }

    private func clock(_ rate: Int) {   // the send clock, at the page's rate
        guard rate != hz else { return }
        hz = rate
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1 / Double(rate), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let now = Date().timeIntervalSince1970
        if now - countAt >= 1 {
            let n = count; count = 0; countAt = now
            if n != mps && !away { mps = n; DispatchQueue.main.async { self.tell(["mps": n]) } }
            if let t = take, !away { told(t, on: true, now) }   // the page's REC timer and rows
        }
        if running.contains("time") { latest["time"] = Sender.clock(Date()) }
        if let g = latest["gravity"], g.count == 3 {   // how the phone is held (the page's lean keeps GRAVITY coming while it is on the screen)
            let q = Frames.quarter(gravity: [g[0], g[1], g[2]], was: quarters)
            if q != quarters { quarters = q; face.turned(q); hand.turned(q) }
        }
        if running.contains("weather"), let l = latest["location"] { weather.near(Double(l[0]), Double(l[1]), now) }   // asks only when it is time
        if !away, now - frameAt >= 1.0 / 32, !latest.isEmpty {   // the page's monitors, 30 times a second: the readings as they are (the page tunes them too)
            frameAt = now
            let v = latest.mapValues { $0.map { $0.isFinite ? Double($0) : 0 } }
            var frame: [String: Any] = ["v": v]
            if running.contains("hand") { frame["hands"] = hands.map { j -> Any in if let j { return j.map { $0.map(Double.init) } }; return NSNull() } }   // the joints for the page's picture (OSC never gets them)
            if let p = pic { frame["cam"] = "data:image/jpeg;base64," + p.base64EncodedString(); pic = nil }   // REAL: the camera's picture behind them
            if let m = mesh { frame["mesh"] = m; mesh = nil }   // and the face's mesh on it
            DispatchQueue.main.async { self.tell(frame) }
        }
        guard !paused, bg || !away, !dests.isEmpty || take != nil else { return }   // the page's bypass holds REC too, and so does leaving with IN BACKGROUND off
        let all = messages(now)
        if let t = take { record(t, all, now) }
        let m = Sender.fresh(all, &sent, now: now)
        guard !m.isEmpty else { return }
        for d in dests {
            guard let l = links[d.key], l.ready else { continue }   // not connected (yet): by then these values are old, so they go
            for p in OSC.packets(d.json ? all : m, prefix: d.prefix, json: d.json, tcp: d.tcp, time: now) { l.conn.send(content: p, completion: .idempotent) }   // a JSON line is the whole picture
            count += d.json ? 1 : m.count
        }
    }

    private func record(_ t: Take, _ all: [OSC.Message], _ now: Double) {   // a row: each column's value this tick; a TOUCH slot not sent is up (0)
        var v: [String: Float] = [:]
        for m in all { v[m.address] = m.values.first }   // a text (the address) has no column
        let up: Float? = running.contains("touch") ? 0 : nil, touch = OSC.root + "/touch/"
        do { try t.add(now, t.columns.map { v[$0] ?? ($0.hasPrefix(touch) ? up : nil) }) } catch { stop(now, failed: true) }
    }

    typealias Sent = [String: (m: OSC.Message, at: Double, again: Bool)]   // each address's last message out, when it changed, one more to go

    /// What goes out this tick: only the messages that changed, each once more 0.2 s later (a lost packet catches up), then
    /// nothing while it stays the same; a text (the address) and TIME's and WEATHER's slow values also every 5 s, for a receiver
    /// opened later (the hour would otherwise reach it in an hour). An untouched TOUCH sends nothing
    static let slow = [OSC.root + "/time/", OSC.root + "/weather/"]
    static func fresh(_ all: [OSC.Message], _ sent: inout Sent, now: Double) -> [OSC.Message] {
        all.filter { m in
            guard let s = sent[m.address], s.m == m else { sent[m.address] = (m, now, true); return true }
            if m.text != nil || slow.contains(where: m.address.hasPrefix), now - s.at >= 5 { sent[m.address]?.at = now; return true }
            guard s.again, now - s.at >= 0.2 else { return false }
            sent[m.address]?.again = false
            return true
        }
    }

    /// Each running sensor's latest values, tuned, at the addresses space gives
    private func messages(_ now: Double) -> [OSC.Message] {
        var m: [OSC.Message] = []
        for id in Sender.live where running.contains(id) {
            guard let raw = latest[id] else { continue }
            for (i, (e, v)) in zip(Sender.numbers(id), Sender.tuned(raw, &tunes[id, default: Tune()], now: now)).enumerated()
                where (id != "hand" || i >= 28 || i % 14 == 0 || raw[i - i % 14] > 0) && (id != "face" || i == 0 || raw[0] > 0) { m.append(.init(address: e[0], values: [v])) }   // a hand out of view sends only its ACTIVE, a face lost only DETECTED (as the page shows it)
            if id == "location", !address.isEmpty { m.append(.init(address: OSC.root + "/location/address", text: address)) }   // only once found
            if id == "weather", !sky.isEmpty { m.append(.init(address: OSC.root + "/weather/text", text: sky)) }
        }
        if running.contains("touch"), used > 0 {   // how many are down, then each slot touched so far
            m.append(.init(address: OSC.root + "/touch/count", values: [Float(slots.filter { $0[2] > 0 }.count)]))
            for i in 0..<used { for (k, v) in zip(["x", "y", "down", "radius"], slots[i]) { m.append(.init(address: OSC.root + "/touch/\(i + 1)/" + k, values: [v])) } }
        }
        return m
    }

    static let touches: [String] = [OSC.root + "/touch/count"] + (1...5).flatMap { i in ["x", "y", "down", "radius"].map { OSC.root + "/touch/\(i)/" + $0 } }   // TOUCH in a take: every slot, touched or not

    static func numbers(_ id: String) -> [[String]] { (space[id] ?? []).filter { $0[1] != "TEXT" } }   // a sensor's values, in its readings' order

    static let live = ["touch", "attitude", "quat", "gravity", "gyro", "accel", "useraccel", "mag", "pressure", "location", "weather", "mic", "prox", "battery", "time", "hand", "face", "video", "depth"]   // the sensors this build reads; the page shows the others COMING SOON. VIDEO and DEPTH go out as NDI, not OSC

    /// TIME: the phone's clock and calendar, in its time zone: HOUR, MINUTE, SECOND (with its fraction), DAYPROGRESS (0 to 1), YEAR,
    /// MONTH, DAY, WEEKDAY (1 Monday … 7 Sunday), YEARDAY. No Unix time: TouchDesigner's float32 would hold it in 2-minute steps
    static func clock(_ d: Date, _ cal: Calendar = .current) -> [Float] {
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday], from: d)
        let h = c.hour ?? 0, mi = c.minute ?? 0, s = Double(c.second ?? 0) + Double(c.nanosecond ?? 0) / 1e9
        let wd = ((c.weekday ?? 1) + 5) % 7 + 1, yd = cal.ordinality(of: .day, in: .year, for: d) ?? 1   // Calendar's 1 is Sunday
        return [Float(h), Float(mi), Float(s), Float((Double(h * 3600 + mi * 60) + s) / 86400), Float(c.year ?? 0), Float(c.month ?? 0), Float(c.day ?? 0), Float(wd), Float(yd)]
    }

    struct Tune { var zero: [Float]? = nil, sm = 0, ema: [Float]? = nil, at = 0.0 }
    static let smooth: [Float] = [1, 0.35, 0.12]   // the page's SMOOTH (OFF, LO, HI): how far a value moves in a twelfth of a second

    /// A reading less its ZERO, then smoothed the way the page smooths it, at whatever rate it comes
    static func tuned(_ raw: [Float], _ t: inout Tune, now: Double) -> [Float] {
        var out = raw
        if let z = t.zero, z.count == raw.count { out = zip(raw, z).map { $0 - $1 } }
        let a = 1 - pow(1 - smooth[min(max(t.sm, 0), 2)], Float(max(now - t.at, 0) * 12))
        if a < 1, let e = t.ema, e.count == out.count { out = zip(e, out).map { $0 + ($1 - $0) * a } }
        t.ema = out; t.at = now
        return out
    }

    /// What goes out, sensor by sensor (the page's ids): each address and what its one value is. SETTINGS lists it as OSC ADDRESSES
    /// (the boot script hands it over), so the list is what is sent. One value per address: TouchDesigner's OSC In CHOP names a
    /// channel after its address (sensorlove/accel/x) but numbers a message's several values (accel1, accel2), and Resolume, Notch
    /// or Ableton map one value each. No address ends in a digit: TouchDesigner would run a value's number into it (touch/11).
    /// FACE by ARKit's own 52 names (Live Link Face, MetaHuman); HAND as the MediaPipe TouchDesigner plugin names them.
    static let space: [String: [[String]]] = {
        let xyz = ["x", "y", "z"], xyzw = ["x", "y", "z", "w"]
        func each(_ a: String, _ keys: [String], _ what: String) -> [[String]] { keys.map { [a + "/" + $0, what] } }
        var s: [String: [[String]]] = [:]
        s["attitude"] = each("/attitude", ["pitch", "roll", "yaw"], "RAD")
        s["quat"] = each("/quaternion", xyzw, "-1 TO 1")
        s["gravity"] = each("/gravity", xyz, "G")
        s["gyro"] = each("/gyro", xyz, "RAD/S")
        s["accel"] = each("/accel", xyz, "G")
        s["useraccel"] = each("/useraccel", xyz, "G")
        s["location"] = each("/location", ["lat", "lon"], "DEG") + [["/location/alt", "M"], ["/location/speed", "M/S"], ["/location/heading", "DEG"], ["/location/address", "TEXT"]]   // the address: one line in the phone's language, when it changes
        s["mag"] = each("/magnet", xyz, "µT")
        s["pressure"] = [["/pressure/kpa", "KPA"], ["/pressure/altitude", "M"]]
        s["touch"] = [["/touch/count", "0-5"]] + each("/touch/1-5", ["x", "y"], "0-1") + [["/touch/1-5/down", "0 / 1"], ["/touch/1-5/radius", "PT"]]
        s["mic"] = [["/mic", "0-1"]]
        s["prox"] = [["/proximity", "0 / 1"]]
        s["battery"] = [["/battery", "0-1"]]
        s["time"] = [["/time/hour", "0-23"], ["/time/minute", "0-59"], ["/time/second", "0-60"], ["/time/dayprogress", "0-1"], ["/time/year", "YEAR"],
                     ["/time/month", "1-12"], ["/time/day", "1-31"], ["/time/weekday", "1 MON-7 SUN"], ["/time/yearday", "1-366"]]
        s["weather"] = [["/weather/temp", "°C"], ["/weather/feels", "°C"], ["/weather/humidity", "%"], ["/weather/rain", "MM"], ["/weather/clouds", "%"],
                        ["/weather/wind", "M/S"], ["/weather/winddir", "DEG FROM"], ["/weather/pressure", "HPA"], ["/weather/isday", "0 / 1"],
                        ["/weather/code", "WMO"], ["/weather/text", "TEXT"]]   // Weather.fields' order; the sky in words when it comes
        let arkit = ["eyeBlinkLeft", "eyeLookDownLeft", "eyeLookInLeft", "eyeLookOutLeft", "eyeLookUpLeft", "eyeSquintLeft", "eyeWideLeft",
                     "eyeBlinkRight", "eyeLookDownRight", "eyeLookInRight", "eyeLookOutRight", "eyeLookUpRight", "eyeSquintRight", "eyeWideRight",
                     "jawForward", "jawLeft", "jawRight", "jawOpen", "mouthClose", "mouthFunnel", "mouthPucker", "mouthLeft", "mouthRight",
                     "mouthSmileLeft", "mouthSmileRight", "mouthFrownLeft", "mouthFrownRight", "mouthDimpleLeft", "mouthDimpleRight",
                     "mouthStretchLeft", "mouthStretchRight", "mouthRollLower", "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper",
                     "mouthPressLeft", "mouthPressRight", "mouthLowerDownLeft", "mouthLowerDownRight", "mouthUpperUpLeft", "mouthUpperUpRight",
                     "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight", "cheekPuff", "cheekSquintLeft",
                     "cheekSquintRight", "noseSneerLeft", "noseSneerRight", "tongueOut"]   // the page's order (FACE's values)
        var face = [["/face/detected", "0 / 1"]] + each("/face/position", xyz, "M") + each("/face/rotation", xyzw, "-1 TO 1")   // the page's order (FACE_HEAD)
        for k in ["lookat", "lefteye", "righteye"] { face += each("/face/" + k, xyz, "M") }
        s["face"] = face + arkit.map { ["/face/" + $0, "0-1"] }
        let hand = ["active", "gesture", "velocity", "leftness", "rightness", "pinch_x", "pinch_y", "pinch_rot", "pinch_dist", "thumb", "index", "middle", "ring", "pinky"]
        var hands: [[String]] = []
        for h in ["1", "2"] {
            for (i, k) in hand.enumerated() { hands.append(["/hand/\(h)/" + k, k == "gesture" ? "0-7" : i == 0 || i > 8 ? "0 / 1" : "VALUE"]) }
        }
        s["hand"] = hands + [["/hand/distance", "VALUE"]]
        s["video"] = []   // VIDEO and DEPTH are NDI sources (NDI.swift): nothing over OSC
        s["depth"] = []
        return s.mapValues { $0.map { [OSC.root + $0[0], $0[1]] } }
    }()

    /// The phone's IPv4 address on Wi-Fi (or on the hotspot it shares), and a neighbour's on the same network; nil off Wi-Fi
    static func local() -> (ip: String, neighbour: String)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var found: (ip: String, neighbour: String)?
        var p = list
        while let i = p?.pointee {
            p = i.ifa_next
            let name = String(cString: i.ifa_name)
            guard name == "en0" || name.hasPrefix("bridge"), let a = i.ifa_addr, a.pointee.sa_family == UInt8(AF_INET), let m = i.ifa_netmask else { continue }
            let ip = a.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let net = ip & m.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let here = (ip: dotted(ip), neighbour: dotted(net &+ 1 == ip ? net &+ 2 : net &+ 1))   // the first host but itself (often the router)
            if name == "en0" { return here }
            found = found ?? here
        }
        return found
    }

    private static func dotted(_ a: UInt32) -> String { "\(a >> 24).\(a >> 16 & 255).\(a >> 8 & 255).\(a & 255)" }
}
