// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import SwiftUI

@main
struct SensorLoveApp: App {
    @StateObject private var page = PageStore()

    var body: some Scene {
        WindowGroup {
            ZStack {
                // the page's --bg (light or dark), until it paints
                page.light ? Color(red: 198 / 255, green: 192 / 255, blue: 176 / 255) : Color(red: 10 / 255, green: 9 / 255, blue: 8 / 255)
                WebView(page: page)
            }
            .ignoresSafeArea()
            .preferredColorScheme(page.light ? .light : .dark)   // the status bar's text follows the page's theme
        }
    }
}
