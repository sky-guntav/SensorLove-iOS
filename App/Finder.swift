// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import Foundation
import Network

/// DESTINATIONS' FOUND ON THIS NETWORK: OSC receivers that announce themselves over Bonjour, each with its IPv4 address and port
/// (what a destination is typed with). _osc._udp: Resolume, TouchOSC, Chataigne. _oscjson._tcp, OSCQuery: MadMapper, Max 9, VDMX;
/// its HTTP server says where its OSC goes (/?HOST_INFO). TouchDesigner announces nothing: it is typed in. It looks only while the
/// page shows DESTINATIONS (find { on }), and not while SensorLove is off the screen.
final class Finder {
    var found: ([[String: Any]]) -> Void = { _ in }  // the whole list whenever it changes: { name, host, port, tcp }. Main thread

    private let queue = DispatchQueue(label: "finder")  // everything below lives on it
    private var browsers: [NWBrowser] = []
    private var seen: [String: [String: Any]] = [:]   // by service (its name and type)
    private var asking: [String: NWConnection] = [:]  // the services being resolved

    func run(_ on: Bool) { queue.async { on ? self.start() : self.stop() } }

    private func start() {
        guard browsers.isEmpty else { return }
        for type in ["_osc._udp", "_oscjson._tcp"] {   // both are in Info.plist's NSBonjourServices: iOS refuses the others
            let b = NWBrowser(for: .bonjour(type: type, domain: nil), using: NWParameters())
            b.browseResultsChangedHandler = { [weak self] results, _ in self?.saw(results, type) }
            b.start(queue: queue)
            browsers.append(b)
        }
    }

    private func stop() {
        browsers.forEach { $0.cancel() }; browsers = []
        asking.values.forEach { $0.cancel() }; asking = [:]
        if !seen.isEmpty { seen = [:]; tell() }
    }

    private func saw(_ results: Set<NWBrowser.Result>, _ type: String) {   // what announces itself now: the gone go, the new are resolved
        var now: [String: (NWEndpoint, String)] = [:]
        for r in results { if case let .service(name, _, _, _) = r.endpoint { now[name + "." + type] = (r.endpoint, name) } }
        let gone = seen.keys.filter { $0.hasSuffix("." + type) && now[$0] == nil }
        gone.forEach { seen[$0] = nil; asking.removeValue(forKey: $0)?.cancel() }
        for (k, s) in now where seen[k] == nil && asking[k] == nil { resolve(s.0, k, s.1, query: type == "_oscjson._tcp") }
        if !gone.isEmpty { tell() }
    }

    /// A connection to the service tells its address; OSCQuery's is its HTTP server, asked where its OSC goes
    private func resolve(_ e: NWEndpoint, _ k: String, _ name: String, query: Bool) {
        let p: NWParameters = query ? .tcp : .udp
        (p.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4   // destinations are typed as IPv4
        let c = NWConnection(to: e, using: p)
        asking[k] = c
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, self.asking[k] === c else { return }
            switch state {
            case .ready:
                guard case let .hostPort(host, port)? = c.currentPath?.remoteEndpoint, case let .ipv4(a) = host else { return self.drop(k) }
                let ip = a.rawValue.map { String($0) }.joined(separator: ".")
                if query { self.hostInfo(c, k, name, ip, port.rawValue) } else { self.add(k, name, ip, Int(port.rawValue), tcp: false) }
            case .failed(_): self.drop(k)   // the next change of the list tries it again
            default: break
            }
        }
        c.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak c] in if let self, let c, self.asking[k] === c { self.drop(k) } }   // never resolved: let it go
    }

    private func hostInfo(_ c: NWConnection, _ k: String, _ name: String, _ ip: String, _ http: UInt16) {
        c.send(content: Data("GET /?HOST_INFO HTTP/1.0\r\nHost: \(ip)\r\n\r\n".utf8), completion: .contentProcessed { _ in })
        var got = Data()
        func more() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] d, _, done, err in
                guard let self, self.asking[k] === c else { return }
                if let d { got.append(d) }
                if let o = Finder.hostInfo(got) { return self.add(k, o.name ?? name, o.ip ?? ip, o.port ?? Int(http), tcp: o.tcp) }
                if done || err != nil || got.count > 65536 { self.drop(k) } else { more() }   // not OSCQuery after all
            }
        }
        more()
    }

    /// OSCQuery's answer to /?HOST_INFO (a whole HTTP response): the OSC receiver's name, address, port and transport. A missing
    /// port or address is the HTTP server's own, a missing transport UDP. nil until the JSON body is all there
    static func hostInfo(_ response: Data) -> (name: String?, ip: String?, port: Int?, tcp: Bool)? {
        guard let r = response.range(of: Data("\r\n\r\n".utf8)), let o = (try? JSONSerialization.jsonObject(with: response[r.upperBound...])) as? [String: Any] else { return nil }
        let ip = (o["OSC_IP"] as? String).flatMap { $0.isEmpty || $0 == "0.0.0.0" ? nil : $0 }
        return (o["NAME"] as? String, ip, o["OSC_PORT"] as? Int, (o["OSC_TRANSPORT"] as? String)?.uppercased() == "TCP")
    }

    private func add(_ k: String, _ name: String, _ ip: String, _ port: Int, tcp: Bool) {
        asking.removeValue(forKey: k)?.cancel()
        seen[k] = ["name": name, "host": ip, "port": port, "tcp": tcp]
        tell()
    }

    private func drop(_ k: String) { asking.removeValue(forKey: k)?.cancel() }

    private func tell() {
        let list = seen.keys.sorted().compactMap { seen[$0] }
        DispatchQueue.main.async { self.found(list) }
    }
}
