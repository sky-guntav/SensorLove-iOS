// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import StoreKit
import UIKit

/// The tip jar: tips through Apple's in-app purchase, consumables that unlock nothing (SensorLove is free, all of it). Apple takes
/// the payment; the app only lists the tips, buys one and finishes it. Main thread
final class Tips {
    static let ids = ["com.skyfly.SensorLove.tip.tiny", "com.skyfly.SensorLove.tip.small", "com.skyfly.SensorLove.tip.medium", "com.skyfly.SensorLove.tip.large"]
    var tell: ([String: Any]) -> Void = { _ in }   // to the page (SL.recv): { tips: [[id, price]], us } · { tip: done · pending · cancel · fail }
    private var products: [Product] = []
    private var updates: Task<Void, Never>?

    init() {
        // a tip that ends outside a purchase: approved later (Ask to Buy, a bank's check), or cut off before it was finished
        updates = Task { @MainActor [weak self] in
            for await result in Transaction.updates {
                await result.unsafePayloadValue.finish()   // nothing to deliver either way: finished, it never comes back
                if case .verified = result { self?.tell(["tip": "done"]) }
            }
        }
    }

    deinit { updates?.cancel() }

    /// The tips, cheapest first, each with its price in the store's currency; none if the App Store does not answer. us: the
    /// phone's App Store is the United States', the only one where an app may also link to another way to pay (GitHub Sponsors)
    func load() {
        Task { @MainActor in
            products = ((try? await Product.products(for: Tips.ids)) ?? []).sorted { $0.price < $1.price }
            let us = await Storefront.current?.countryCode == "USA"
            tell(["tips": products.map { [$0.id, $0.displayPrice] }, "us": us])
        }
    }

    /// Apple's sheet asks for the confirmation, over the scene
    func buy(_ id: String, in scene: UIScene?) {
        guard let p = products.first(where: { $0.id == id }), let scene else { return tell(["tip": "fail"]) }
        Task { @MainActor in
            var state = "fail"
            switch try? await p.purchase(confirmIn: scene) {
            case .success(let result)?:
                await result.unsafePayloadValue.finish()
                if case .verified = result { state = "done" }
            case .pending?: state = "pending"
            case .userCancelled?: state = "cancel"
            default: break
            }
            tell(["tip": state])
        }
    }
}
