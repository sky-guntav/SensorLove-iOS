// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import Foundation

/// OSC as SensorLove sends it: every running sensor under /sensorlove, one value per address (Sender.space), a tick's messages in
/// one bundle (in several when they do not fit one UDP datagram), TCP framed with SLIP (OSC 1.1). Or the tick as one JSON object
/// instead. Only bytes here: Sender does the network.
enum OSC {
    static let root = "/sensorlove"
    static let maxPacket = 1400   // under Wi-Fi's 1500 with room for the IP and UDP headers: a bundle never fragments

    struct Message: Equatable { let address: String; var values: [Float] = []; var text: String? = nil }   // numbers, or one text (LOCATION's address)

    /// What one destination gets for a tick: its prefix after the root (/sensorlove/phone1/gyro/x), OSC bundles (SLIP framed on
    /// TCP, which has no packets) or one JSON object
    static func packets(_ messages: [Message], prefix: String, json: Bool, tcp: Bool, time: Double) -> [Data] {
        if json { return [object(messages, prefix: prefix, time: time)] }
        let b = bundles(messages.map { message(address($0.address, prefix: prefix), $0.values, text: $0.text) })
        return tcp ? b.map(slip) : b
    }

    /// The address and its type tags, each ended and padded to 4 bytes with zeros, then each value as a big-endian float (or the
    /// text, UTF-8, ended and padded the same way)
    static func message(_ address: String, _ values: [Float], text: String? = nil) -> Data {
        if let text { return padded(address) + padded(",s") + padded(text) }
        var d = padded(address) + padded("," + String(repeating: "f", count: values.count))
        for v in values { withUnsafeBytes(of: v.bitPattern.bigEndian) { d.append(contentsOf: $0) } }
        return d
    }

    /// The messages in as few bundles as fit maxPacket (a message too big for one goes alone in its own)
    static func bundles(_ messages: [Data]) -> [Data] {
        let head = padded("#bundle") + Data([0, 0, 0, 0, 0, 0, 0, 1])   // time tag 1: at once (a receiver's clock never holds it back)
        var out: [Data] = [], b = head
        for m in messages {
            if b.count > head.count && b.count + 4 + m.count > maxPacket { out.append(b); b = head }
            b += withUnsafeBytes(of: UInt32(m.count).bigEndian) { Data($0) } + m
        }
        if b.count > head.count { out.append(b) }
        return out
    }

    static func address(_ address: String, prefix: String) -> String {   // every phone's messages keep /sensorlove first, so /sensorlove/* catches them all
        let p = name(prefix)
        return p.isEmpty || !address.hasPrefix(root) ? address : root + "/" + p + String(address.dropFirst(root.count))
    }

    static func name(_ prefix: String) -> String { prefix.split(separator: "/").joined(separator: "/") }   // "/phone1/" → "phone1"

    /// SLIP, OSC 1.1's frame on a stream: END, the packet with its ENDs and ESCs escaped, END
    static func slip(_ packet: Data) -> Data {
        var d = Data([0xC0])
        for b in packet {
            switch b {
            case 0xC0: d += [0xDB, 0xDC]
            case 0xDB: d += [0xDB, 0xDD]
            default: d.append(b)
            }
        }
        d.append(0xC0)
        return d
    }

    /// The tick as one JSON line: { timestamp, prefix (if set), accel: { x, y, z }, touch: { count, 1: { x, y, down, radius } } }.
    /// Each address under the root is a path to its value (TIME's /time/hour is time.hour, so the tick's own clock is not "time")
    static func object(_ messages: [Message], prefix: String, time: Double) -> Data {
        var o: [String: Any] = ["timestamp": time]
        if !name(prefix).isEmpty { o["prefix"] = name(prefix) }
        for m in messages {
            let path = (m.address.hasPrefix(root + "/") ? String(m.address.dropFirst(root.count + 1)) : m.address).split(separator: "/").map(String.init)
            if let text = m.text { put(&o, path[...], text); continue }   // a text (the address) as it is
            let v = m.values.map { $0.isFinite ? Double($0.description) ?? 0 : 0 }   // 0.1, not 0.10000000149; NaN is no JSON (and JSONSerialization would throw)
            put(&o, path[...], v.count == 1 ? v[0] : v)
        }
        return ((try? JSONSerialization.data(withJSONObject: o)) ?? Data()) + Data([10])
    }

    private static func put(_ o: inout [String: Any], _ path: ArraySlice<String>, _ leaf: Any) {
        guard let k = path.first else { return }
        if path.count == 1 { o[k] = leaf; return }
        var child = o[k] as? [String: Any] ?? [:]   // touch's count beside its fingers
        put(&child, path.dropFirst(), leaf)
        o[k] = child
    }

    private static func padded(_ s: String) -> Data {
        var d = Data(s.utf8)
        d.append(0)
        while d.count % 4 != 0 { d.append(0) }
        return d
    }
}
