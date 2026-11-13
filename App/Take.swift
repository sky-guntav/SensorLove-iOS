// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import Foundation

/// REC: one take, a CSV in the app's Documents (the Files app shows them, in SensorLove), named after when it started. A row a
/// tick (at SEND RATE): the seconds since REC, then each value as it went out (ZERO and SMOOTH done); a column a value, named as
/// TouchDesigner's OSC In CHOP names the channel (sensorlove/accel/x), so Table DAT → DAT to CHOP (Channel per Column, First Row
/// is Names) gives the live channels back. The columns are the sensors on at REC; one switched off since leaves its cells empty.
final class Take {
    let url: URL, columns: [String], start: Double
    private(set) var rows = 0
    private let file: FileHandle
    private var buffer = Data(), flushed = 0.0

    init(columns: [String], start: Double) throws {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dir = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let name = "SensorLove_" + f.string(from: Date(timeIntervalSince1970: start))
        var url = dir.appendingPathComponent(name + ".csv"), n = 1
        while FileManager.default.fileExists(atPath: url.path) { n += 1; url = dir.appendingPathComponent(name + "-\(n).csv") }   // two takes in a second: the first stays
        guard FileManager.default.createFile(atPath: url.path, contents: Data(Take.header(columns).utf8)) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.url = url; self.columns = columns; self.start = start; file = handle; flushed = start
    }

    static func header(_ columns: [String]) -> String { (["time"] + columns.map { String($0.dropFirst()) }).joined(separator: ",") + "\n" }   // TouchDesigner drops the leading /

    static func line(_ t: Double, _ values: [Float?]) -> String {   // no value (not read yet, or switched off): an empty cell
        ([String(format: "%.3f", t)] + values.map { v in v.flatMap { $0.isFinite ? "\($0)" : nil } ?? "" }).joined(separator: ",") + "\n"
    }

    func add(_ now: Double, _ values: [Float?]) throws {   // to the file once a second: an app killed mid-take loses that second at most
        buffer.append(contentsOf: Take.line(now - start, values).utf8)
        rows += 1
        if now - flushed >= 1 { try flush(); flushed = now }
    }

    func close() throws { try flush(); try file.close() }

    private func flush() throws { try file.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true) }
}
