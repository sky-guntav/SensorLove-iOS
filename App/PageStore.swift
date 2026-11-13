// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import Foundation

/// What the page keeps (a browser's localStorage), kept by the app from one launch to the next: the cards' order, the presets,
/// the way SensorLove was left.
final class PageStore: ObservableObject {
    @Published private(set) var light = false   // the page's theme: the status bar and the background under the page follow it
    private(set) var items: [String: String]

    init() {
        items = UserDefaults.standard.dictionary(forKey: "page") as? [String: String] ?? [:]
        readTheme()
    }

    func set(_ key: String, _ value: String?) {
        items[key] = value
        UserDefaults.standard.set(items, forKey: "page")
        if key == "sensorlove.last" { readTheme() }
    }

    private func readTheme() {
        let last = items["sensorlove.last"].flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
        light = last?["theme"] as? String == "light"
    }
}
