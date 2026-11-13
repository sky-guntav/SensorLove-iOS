// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import SwiftUI
import WebKit

/// An ad hoc or Xcode install: the App Store (and TestFlight) strip the provisioning profile. Only these write to the phone's log
/// (the page's console, FACE's axes), for debugging over USB: the console holds the address, so a store build keeps quiet.
let testInstall = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil

/// The whole interface: WebUI/home.html from the app bundle, full screen.
struct WebView: UIViewRepresentable {
    let page: PageStore

    func makeCoordinator() -> Coordinator { Coordinator(page: page) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "sl")   // the page posts here: webkit.messageHandlers.sl
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false                      // see-through: the app's background shows until the page paints
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false    // the page scrolls inside itself, never as a whole
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never   // the page keeps clear of the notch itself (env(safe-area-inset-*))
        web.allowsLinkPreview = false
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        context.coordinator.load(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let page: PageStore
        let sender = Sender()
        let finder = Finder()                         // DESTINATIONS' FOUND ON THIS NETWORK
        let tips = Tips()                             // the tip jar (HELLO's jar, ABOUT)
        private var finding = false                   // the page shows DESTINATIONS (find { on })
        weak var web: WKWebView?

        init(page: PageStore) {
            self.page = page
            super.init()
            sender.tell = { [weak self] m in self?.tell(m) }
            finder.found = { [weak self] l in self?.tell(["found": l]) }
            tips.tell = { [weak self] m in self?.tell(m) }
            sender.update(page.items["sensorlove.last"])   // the destinations as they were left: connected before the page is up
            sender.start()
            let center = NotificationCenter.default
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.sender.resend() }   // back from iOS Settings: access may have changed
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.sender.leave(true); self?.finder.run(false); self?.dark(false) }   // another app, or the lock: IN BACKGROUND decides; no looking round off the screen
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in self?.sender.leave(false); self?.finder.run(self?.finding == true) }
        }

        func load(_ web: WKWebView) {
            sender.restart()   // a page that starts again sends, with no finger down and no TUNE
            finding = false; finder.run(false)   // it asks again when it shows DESTINATIONS
            // the boot script carries what was kept, so it is made again for every load
            let scripts = web.configuration.userContentController
            scripts.removeAllUserScripts()
            scripts.addUserScript(WKUserScript(source: boot(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
            guard let dir = Bundle.main.url(forResource: "WebUI", withExtension: nil) else { return }
            web.loadFileURL(dir.appendingPathComponent("home.html"), allowingReadAccessTo: dir)
        }

        /// Runs before the page's own script: it is in the app, which version and build this is, what it kept last time, what goes
        /// out (OSC ADDRESSES), what reads for real, iOS access (LOCAL NETWORK, MOTION, LOCATION, MIC, CAMERA) and the phone's address
        /// (changes come later through SL.recv).
        private func boot() -> String {
            let info = Bundle.main.infoDictionary ?? [:]
            let version = (info["CFBundleShortVersionString"] as? String ?? "?") + " · BUILD " + (info["CFBundleVersion"] as? String ?? "?")
            let json = { (o: Any) in (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
            let cams = ["truedepth": Face.can, "lidar": Face.lidar, "people": Face.people, "ndi": NDI.built, "ai": Detail.built]   // what VIDEO and DEPTH can have on this phone and in this build
            return "window.SL = { version: '\(version)', store: \(json(page.items)), osc: \(json(Sender.space)), live: \(json(Sender.live)), cams: \(json(cams)), perm: \(json(sender.perms())), ip: '\(sender.ip)' }; document.documentElement.classList.add('app');"
        }

        private func tell(_ m: [String: Any]) {   // to the page: SL.recv({ perm, ip, log, mps, v, hands, cam, rec, addr, map, found, tips, tip })
            guard let d = try? JSONSerialization.data(withJSONObject: m), let json = String(data: d, encoding: .utf8) else { return }
            web?.evaluateJavaScript("window.SL && SL.recv && SL.recv(\(json))")
        }

        // the page's messages, { t: what, ... }: store { k: key, v: its value, or null to remove it } · touch { f: each finger's
        // x, y, radius } · bypass { on } · perm { k } (iOS asks for one) · settings (iOS Settings, after the page asked) · tune { id,
        // zero, sm } · rec { on } · csv (SAVE CSV) · map { x0, y0 } (LOCATION's map) · real { on } (HAND's camera picture, for
        // REAL) · find { on } (DESTINATIONS is up: look for receivers) · tips (the jar is open: its tips and prices) · tip { id }
        // (buy one) · log { m } (a console line)
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let m = message.body as? [String: Any] else { return }
            switch m["t"] as? String ?? "" {
            case "store":
                guard let key = m["k"] as? String else { return }
                page.set(key, m["v"] as? String)
                if key == "sensorlove.last" { sender.update(m["v"] as? String) }   // what runs, how fast, where to
            case "touch": sender.touch(m["f"] as? [[Double]] ?? [])
            case "bypass": sender.bypass(m["on"] as? Bool == true)
            case "perm": if let k = m["k"] as? String, sender.perms()[k] != nil { sender.ask(k) }
            case "settings": sender.settings()
            case "tune": if let id = m["id"] as? String { sender.tune(id, zero: m["zero"] as? [Double], sm: m["sm"] as? Int ?? 0) }
            case "rec": sender.rec(m["on"] as? Bool == true)
            case "csv": if let url = sender.saved { share(url) }
            case "map": if let x = m["x0"] as? Double, let y = m["y0"] as? Double { sender.map(x0: x, y0: y) }
            case "real": sender.real(m["on"] as? Bool == true)
            case "find": finding = m["on"] as? Bool == true; finder.run(finding)
            case "dark": dark(m["on"] as? Bool == true)
            case "tips": tips.load()
            case "tip": if let id = m["id"] as? String { tips.buy(id, in: web?.window?.windowScene) }
            case "licences":   // ABOUT: NDI's open-source licences, copied into WebUI by the build that fetched NDI (ci_post_clone.sh)
                let u = Bundle.main.url(forResource: "ndi-licenses", withExtension: "txt", subdirectory: "WebUI")
                tell(["licences": u.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""])
            case "log": if testInstall { NSLog("CONSOLE %@", m["m"] as? String ?? "") }   // test installs: the page's console in the device log
            default: break
            }
        }

        /// DARK: the screen as dim as it goes while the page is black (a source runs on with no one looking at the phone); back as
        /// it was when the page wakes (a touch) or SensorLove leaves the screen
        private var bright: CGFloat?
        private func dark(_ on: Bool) {
            guard let screen = web?.window?.windowScene?.screen else { return }
            if on, bright == nil { bright = screen.brightness; screen.brightness = 0 }
            else if !on, let b = bright { screen.brightness = b; bright = nil }
        }

        private func share(_ url: URL) {   // iOS's share sheet: AirDrop, Save to Files, Mail…
            guard let web, let top = web.window?.rootViewController, top.presentedViewController == nil else { return }
            let s = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            s.popoverPresentationController?.sourceView = web   // an iPad running it as an iPhone app wants an anchor
            s.completionWithItemsHandler = { [weak self] _, done, _, _ in if done { self?.tell(["log": "SAVED " + url.lastPathComponent]) } }
            top.present(s, animated: true)
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) { sender.resend() }   // what changed while the page loaded

        // the page comes from the bundle; anything else it opens (mail, a web page) goes to its own app
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, !url.isFileURL else { return decisionHandler(.allow) }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        // iOS may end the page's process to free memory: bring it back
        func webViewWebContentProcessDidTerminate(_ web: WKWebView) { load(web) }
    }
}
