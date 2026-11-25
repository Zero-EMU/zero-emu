import SwiftUI
import Combine
#if os(iOS)
import StoreKit
import UIKit
import AVFoundation
#elseif os(macOS)
import AppKit
#endif

// Zero EMU Pro's store. Three products: two subscriptions that renew (月付
// and 年付, one subscription group) and 永久, bought once. Whoever owns any
// of them has Pro. The App Store is asked through StoreKit; a debug build
// also has a pretend store that takes no money and talks to nobody, so the
// page and the locks can be gone through before the products exist, and so
// the UI tests have a store that answers the same way every time.
// What Pro opens is in Domain.swift (ProAccess); the page is ProPage in
// SystemSettingsApp.swift.

/// One of the three as the store offers it: its price in the storefront's
/// own words ("$0.99", "¥8.00").
struct ProOffer: Identifiable, Equatable, Sendable {
    var plan: ProPlan
    var price: String
    var id: String { plan.rawValue }
}

/// What is owned now.
struct ProHoldings: Equatable, Sendable {
    var plans: Set<ProPlan> = []
    /// When the subscription owned renews or runs out (nil: none, or 永久 only).
    var expires: Date?
    /// When each was first bought, as the store says it (the 卡带证's date).
    var since: [ProPlan: Date] = [:]
    var isPro: Bool { !plans.isEmpty }
}

/// What a purchase came to.
enum ProPurchaseOutcome: Equatable, Sendable {
    case bought, cancelled
    /// Waiting for an approval (Ask to Buy) or for the payment to go through.
    case pending
    case failed(String)
}

/// Something the store could not do, in words for the page.
struct ProStoreFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// A store: the App Store, or a debug build's pretend one.
@MainActor protocol ProBackend: AnyObject {
    /// For the log and the developer's page.
    var name: String { get }
    func offers() async throws -> [ProOffer]
    func holdings() async -> ProHoldings
    /// What is owned, when the store can say it at once (the pretend one
    /// can; the App Store has to be asked: nil).
    var known: ProHoldings? { get }
    func buy(_ plan: ProPlan) async -> ProPurchaseOutcome
    /// 恢复购买: the store is asked again what this Apple account owns.
    func restore() async throws
    /// 管理订阅: the system's own page for it.
    func manage() async throws
    /// Told when something changed outside a purchase made here (a renewal,
    /// a refund, a purchase on another device).
    func listen(_ changed: @escaping @MainActor () -> Void)
    /// "Nothing owned" where something was is asked once more before it is
    /// believed (the App Store, which may answer too early after a launch
    /// or a restore; the pretend store's answer is its own and final).
    var asksAgainBeforeLoss: Bool { get }
}

/// 恢复购买 put away by the user at the Apple Account's question: nothing to say.
struct ProRestoreCancelled: Error {}

@MainActor final class ProStore: ObservableObject {
    static let shared = ProStore()

    enum Catalog: Equatable {
        case loading
        case ready([ProOffer])
        /// The store did not answer or has none of the three: why, in words.
        case unavailable(String)
    }

    @Published private(set) var isPro: Bool
    @Published private(set) var holdings = ProHoldings()
    @Published private(set) var catalog = Catalog.loading
    /// A purchase, or 恢复购买, under way: the page's rows wait for it.
    @Published private(set) var buying: ProPlan?
    @Published private(set) var restoring = false
    private var backend: ProBackend
    private var started = false
    private var loadingOffers = false
    /// When the prices on the page were read (they are read again after a
    /// while: a price can change in the store while the app stays open).
    private var offersAt: Date?
    /// Which asking of the store is the latest (an older answer that comes
    /// in after a newer one is dropped).
    private var asked = 0
    /// Asks again when the subscription owned runs out with the app open
    /// (nothing is sent then: a subscription not renewed just ends).
    private var expiryCheck: Task<Void, Never>?

    /// The body colour and the camera body put aside when Pro ended.
    static let asideFinishKey = "FoldArc.pro.aside.finish"
    static let asideBodyKey = "FoldArc.pro.aside.body"

    private init() {
        isPro = ProAccess.isPro
        // The purchases as the store last said them: the cards on the shelf
        // (and the one in the console) stay through a launch until it answers.
        holdings = ProHoldings(plans: ProAccess.plans)
        backend = Self.makeBackend()
    }

    private static func makeBackend() -> ProBackend {
        #if DEBUG
        if let pretend = DebugProBackend.make() { return pretend }
        #endif
        #if os(iOS)
        return AppStoreBackend()
        #else
        return NoStoreBackend()
        #endif
    }
    var backendName: String { backend.name }
    var busy: Bool { buying != nil || restoring }

    /// At launch, before any view reads a choice only Pro has: what is
    /// owned if the store can say it at once, else the last answer; a choice
    /// only Pro has is put aside if that is "not Pro". Then the store is
    /// asked, and listened to from then on.
    func start() {
        guard !started else { return }
        started = true
        NSLog("[pro] store: %@; last known: %@", backend.name, isPro ? "Pro" : "free")
        if let now = backend.known { take(now) } else { settleChoices() }
        backend.listen { [weak self] in Task { await self?.refresh() } }
        Task { await refresh() }
    }

    /// What is owned, from the store.
    func refresh() async {
        asked += 1
        let mine = asked
        var now = await backend.holdings()
        if backend.asksAgainBeforeLoss, isPro, !now.isPro {
            try? await Task.sleep(for: .seconds(2))
            now = await backend.holdings()
        }
        guard mine == asked else { return }
        take(now)
    }
    /// The store's answer taken at once, whatever else is being asked: after
    /// a purchase or 恢复购买, what is said next goes by it.
    private func refreshNow() async {
        asked += 1
        take(await backend.holdings())
    }
    /// The rest of the app goes by ProAccess.isPro, written here; choices
    /// only Pro has are put aside, or come back.
    private func take(_ now: ProHoldings) {
        if holdings != now { holdings = now }
        expiryCheck?.cancel()
        expiryCheck = nil
        if let end = now.expires, end > Date(), !now.plans.contains(.lifetime) {
            expiryCheck = Task { [weak self] in
                try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow + 5))
                if !Task.isCancelled { await self?.refresh() }
            }
        }
        ProAccess.keep(now.plans)
        CartridgeRecord.note(now)
        if now.isPro != isPro {
            isPro = now.isPro
            NSLog("[pro] now %@ (%@)", now.isPro ? "Pro" : "free", now.plans.map(\.rawValue).sorted().joined(separator: ","))
        }
        settleChoices()
    }

    /// The three prices: asked when the page opens, again after an answer
    /// that had none, and again once the ones shown are ten minutes old
    /// (those stay on the page meanwhile, and if the store does not answer).
    func loadOffers() async {
        var had = false
        if case .ready = catalog { had = true }
        if had, let at = offersAt, Date().timeIntervalSince(at) < 600 { return }
        guard !loadingOffers else { return }
        loadingOffers = true
        defer { loadingOffers = false }
        if !had { catalog = .loading }
        do {
            let found = try await backend.offers()
            let offers = ProPlan.allCases.compactMap { plan in found.first { $0.plan == plan } }
            if !offers.isEmpty {
                catalog = .ready(offers)
                offersAt = Date()
            } else if !had {
                catalog = .unavailable(String(localized: "App Store 里现在没有这些项目"))
            }
            NSLog("[pro] offers: %@", offers.map { "\($0.plan.rawValue) \($0.price)" }.joined(separator: ", "))
        } catch is CancellationError {
            // The page was left before the store answered: asked again next time.
            NSLog("[pro] offers: the asking was given up")
        } catch {
            if !had { catalog = .unavailable(error.localizedDescription) }
            NSLog("[pro] no offers: %@", error.localizedDescription)
        }
    }

    func buy(_ plan: ProPlan) async -> ProPurchaseOutcome {
        guard !busy else { return .cancelled }
        buying = plan
        defer { buying = nil }
        NSLog("[pro] buying %@", plan.rawValue)
        let outcome = await backend.buy(plan)
        NSLog("[pro] %@: %@", plan.rawValue, String(describing: outcome))
        if outcome == .bought { await refreshNow() }
        return outcome
    }

    /// 恢复购买. nil when the store was asked (whether Pro is open then is
    /// `isPro`), or why it could not be (empty: the user put the question
    /// away, and there is nothing to say).
    func restore() async -> String? {
        guard !busy else { return "" }
        restoring = true
        defer { restoring = false }
        do { try await backend.restore() } catch is ProRestoreCancelled {
            NSLog("[pro] restore: put away by the user")
            return ""
        } catch {
            NSLog("[pro] restore failed: %@", error.localizedDescription)
            return error.localizedDescription
        }
        await refreshNow()
        NSLog("[pro] restored: %@", isPro ? "Pro" : "nothing owned")
        return nil
    }

    /// 管理订阅. nil when the system's page came up, or why it did not.
    func manageSubscriptions() async -> String? {
        do { try await backend.manage(); return nil } catch { return error.localizedDescription }
    }

    /// The day 永久's launch price is announced until, while it runs.
    var offerEnd: Date? {
        var end = ProAccess.launchOfferEnd
        #if DEBUG
        // `--foldarc-pro-offer=2026-12-31`: as if that were the day.
        if let value = DebugProBackend.argument("--foldarc-pro-offer") {
            let format = DateFormatter()
            format.calendar = Calendar(identifier: .gregorian)
            format.locale = Locale(identifier: "en_US_POSIX")
            format.dateFormat = "yyyy-MM-dd"
            end = format.date(from: value)
        }
        #endif
        return ProAccess.offerRuns(until: end, now: Date()) ? end : nil
    }

    // MARK: Choices only Pro has

    private func settleChoices() {
        // TV模式 is Pro's: without Pro the TV goes back to mirroring (the
        // kept mode stays kept: `ScreenLayout.stored` gives it with Pro only).
        // With the console on, its picture is not taken off the TV in the
        // middle: the mode goes when the console is put away (PlayView).
        if !isPro, TVOutput.shared.tvMode, !TVOutput.shared.attached {
            TVOutput.shared.setTVMode(false)
        } else if isPro, !TVOutput.shared.tvMode, !TVOutput.shared.attached, ScreenLayout.stored == .tv {
            // Back with Pro (no game on the screens: a game says its own mode).
            TVOutput.shared.setTVMode(true)
        }
        let finishes = ShellFinish.allCases.map(\.rawValue), bodies = CameraBody.allCases.map(\.rawValue)
        settle(StoredFinishName.key, aside: Self.asideFinishKey, fallback: ShellFinish.aqua.rawValue) {
            ProAccess.isFree(position: finishes.firstIndex(of: $0), of: ProAccess.freeFinishes)
        }
        settle(CameraBody.defaultsKey, aside: Self.asideBodyKey, fallback: CameraBody.native.rawValue) {
            ProAccess.isFree(position: bodies.firstIndex(of: $0), of: ProAccess.freeBodies)
        }
    }
    private func settle(_ key: String, aside: String, fallback: String, isFree: (String) -> Bool) {
        let defaults = UserDefaults.standard
        let before = ProAccess.Choice(current: defaults.string(forKey: key) ?? fallback, aside: defaults.string(forKey: aside))
        let after = ProAccess.settle(before, pro: isPro, fallback: fallback, isFree: isFree)
        guard after != before else { return }
        defaults.set(after.current, forKey: key)
        if let kept = after.aside { defaults.set(kept, forKey: aside) } else { defaults.removeObject(forKey: aside) }
        NSLog("[pro] %@: %@ -> %@%@", key, before.current, after.current, after.aside.map { " (\($0) put aside)" } ?? "")
    }

    #if DEBUG
    // MARK: The developer's page (a debug build)

    /// The pretend store is the one in use.
    var pretend: Bool { backend is DebugProBackend }
    /// The pretend store or the App Store, from now on and at the next launches.
    func usePretendStore(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: DebugProBackend.storeKey)
        backend = Self.makeBackend()
        catalog = .loading
        offersAt = nil
        NSLog("[pro] store: %@", backend.name)
        backend.listen { [weak self] in Task { await self?.refresh() } }
        if let now = backend.known { take(now) }
        Task { await refresh() }
    }
    /// What was "bought" in the pretend store is forgotten.
    func clearPretendPurchases() {
        (backend as? DebugProBackend)?.clear()
        if let now = backend.known { take(now) }
    }
    #endif
}

extension ShellFinish {
    /// One of the colours everybody has.
    var isFree: Bool { ProAccess.isFree(position: Self.allCases.firstIndex(of: self), of: ProAccess.freeFinishes) }
    /// It can be used now: free, or Pro is open.
    var isOpen: Bool { isFree || ProAccess.isPro }
}

extension CameraBody {
    /// One of the bodies everybody has.
    var isFree: Bool { ProAccess.isFree(position: Self.allCases.firstIndex(of: self), of: ProAccess.freeBodies) }
    var isOpen: Bool { isFree || ProAccess.isPro }
}

/// A small lock on a choice only Pro has.
struct ProLockBadge: View {
    var size: Double
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.56, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.black.opacity(0.62), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: max(0.6, size * 0.07)))
            .accessibilityHidden(true)
    }
}

#if os(iOS)
// MARK: - The App Store

@MainActor final class AppStoreBackend: ProBackend {
    let name = "App Store"
    private var products: [ProPlan: Product] = [:]
    private var updates: Task<Void, Never>?
    deinit { updates?.cancel() }

    let asksAgainBeforeLoss = true
    /// What each of the three has to be in the store: a subscription that
    /// renews, or bought once and kept. One set up as something else there
    /// (a consumable would be paid for and open nothing; a subscription that
    /// does not renew would stay open for good) is not offered and not counted.
    private static func kind(_ plan: ProPlan) -> Product.ProductType { plan.renews ? .autoRenewable : .nonConsumable }

    func offers() async throws -> [ProOffer] {
        let found = try await Product.products(for: ProPlan.allCases.map(\.productID))
        var offers: [ProOffer] = []
        for product in found {
            guard let plan = ProPlan(productID: product.id) else { continue }
            guard product.type == Self.kind(plan) else {
                NSLog("[pro] %@ is set up in the store as %@: not offered", product.id, product.type.rawValue)
                continue
            }
            products[plan] = product
            offers.append(ProOffer(plan: plan, price: product.displayPrice))
        }
        return offers
    }

    var known: ProHoldings? { nil }
    func holdings() async -> ProHoldings {
        var now = ProHoldings()
        for await result in Transaction.currentEntitlements {
            // Only what the App Store signed, not taken back, and not the
            // subscription a higher one replaced.
            guard case .verified(let transaction) = result, transaction.revocationDate == nil, !transaction.isUpgraded,
                  let plan = ProPlan(productID: transaction.productID), transaction.productType == Self.kind(plan) else { continue }
            now.plans.insert(plan)
            if plan.renews, let end = transaction.expirationDate { now.expires = max(now.expires ?? end, end) }
            now.since[plan] = min(now.since[plan] ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
        }
        return now
    }

    func buy(_ plan: ProPlan) async -> ProPurchaseOutcome {
        guard AppStore.canMakePayments else { return .failed(String(localized: "这台 iPhone 现在不允许 App 内购买（屏幕使用时间里的限制）")) }
        do {
            if products[plan] == nil { _ = try await offers() }
            guard let product = products[plan] else { return .failed(String(localized: "App Store 里现在没有这一项")) }
            let result: Product.PurchaseResult
            if let scene = Self.scene {
                result = try await product.purchase(confirmIn: scene)
            } else {
                result = try await product.purchase()
            }
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed(String(localized: "这笔购买没有通过 App Store 的校验"))
                }
                await transaction.finish()
                return .bought
            case .userCancelled: return .cancelled
            case .pending: return .pending
            @unknown default: return .failed(String(localized: "App Store 给了一个不认识的结果"))
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async throws {
        do { try await AppStore.sync() } catch StoreKitError.userCancelled {
            throw ProRestoreCancelled()
        }
    }

    func manage() async throws {
        guard let scene = Self.scene else { throw ProStoreFailure(message: String(localized: "现在打不开订阅管理")) }
        try await AppStore.showManageSubscriptions(in: scene)
    }

    func listen(_ changed: @escaping @MainActor () -> Void) {
        updates?.cancel()
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                changed()
            }
        }
    }

    /// The window the app is shown in (the purchase sheet goes over it).
    private static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.session.role == .windowApplication }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
#else
/// The Mac preview has no store.
@MainActor final class NoStoreBackend: ProBackend {
    let name = "none"
    let asksAgainBeforeLoss = false
    func offers() async throws -> [ProOffer] { [] }
    func holdings() async -> ProHoldings { ProHoldings(plans: ProAccess.isPro ? [.lifetime] : []) }
    var known: ProHoldings? { nil }
    func buy(_ plan: ProPlan) async -> ProPurchaseOutcome { .cancelled }
    func restore() async throws {}
    func manage() async throws {}
    func listen(_ changed: @escaping @MainActor () -> Void) {}
}
#endif

#if DEBUG
// MARK: - A debug build's pretend store

/// The three products at fixed prices; a purchase takes a moment and no
/// money, and nothing leaves the iPhone. What was "bought" is remembered
/// (其他设置 › 开发者 forgets it, or changes to the App Store).
/// For the tests, `--foldarc-pro=<free|monthly|yearly|lifetime|owned|none|store>`:
/// what is owned as the run begins (owned: 永久; none: the store has no
/// prices; store: the App Store itself) — nothing of such a run is
/// remembered. `--foldarc-pro-buy=<cancel|pending|fail>`: what a purchase
/// comes to. `--foldarc-pro-restore=<plan|fail>`: what 恢复购买 finds.
@MainActor final class DebugProBackend: ProBackend {
    static let storeKey = "FoldArc.pro.debug.pretend"
    static let ownedKey = "FoldArc.pro.debug.owned"
    static let boughtAtKey = "FoldArc.pro.debug.boughtAt"

    let name: String
    let asksAgainBeforeLoss = false
    private var owned: Set<ProPlan>
    private var boughtAt: Date
    private let remembers: Bool
    private let hasOffers: Bool
    private let buyResult: String?
    private let restoreResult: String?
    private var changed: (@MainActor () -> Void)?

    /// (The last one given counts: a test's own after the ones every test has.)
    static func argument(_ name: String) -> String? {
        ProcessInfo.processInfo.arguments.last { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
    }

    /// nil: the App Store is the one to use.
    static func make() -> DebugProBackend? {
        let defaults = UserDefaults.standard
        if let mode = argument("--foldarc-pro") {
            guard mode != "store" else { return nil }
            let plan: ProPlan? = mode == "owned" ? .lifetime : ProPlan(rawValue: mode)
            let owned: Set<ProPlan> = plan.map { Set([$0]) } ?? []
            CartridgeRecord.keepsNothing = true
            return DebugProBackend(name: "pretend (\(mode), this run only)", owned: owned, boughtAt: Date(), remembers: false, hasOffers: mode != "none")
        }
        if defaults.object(forKey: storeKey) != nil, !defaults.bool(forKey: storeKey) { return nil }
        let owned = Set((defaults.stringArray(forKey: ownedKey) ?? []).compactMap(ProPlan.init(rawValue:)))
        return DebugProBackend(name: "pretend", owned: owned, boughtAt: defaults.object(forKey: boughtAtKey) as? Date ?? Date(), remembers: true, hasOffers: true)
    }

    private init(name: String, owned: Set<ProPlan>, boughtAt: Date, remembers: Bool, hasOffers: Bool) {
        self.name = name
        self.owned = owned
        self.boughtAt = boughtAt
        self.remembers = remembers
        self.hasOffers = hasOffers
        buyResult = Self.argument("--foldarc-pro-buy")
        restoreResult = Self.argument("--foldarc-pro-restore")
    }

    func offers() async throws -> [ProOffer] {
        try? await Task.sleep(for: .milliseconds(300))
        guard hasOffers else { throw ProStoreFailure(message: String(localized: "连不上 App Store")) }
        return [ProOffer(plan: .monthly, price: "$0.99"), ProOffer(plan: .yearly, price: "$3.99"), ProOffer(plan: .lifetime, price: "$6.99")]
    }

    func holdings() async -> ProHoldings { current }
    var known: ProHoldings? { current }
    private var current: ProHoldings {
        var now = ProHoldings(plans: owned)
        for plan in owned { now.since[plan] = boughtAt }
        // A subscription: a month or a year from when it was "bought".
        if owned.contains(.yearly) {
            now.expires = Calendar.current.date(byAdding: .year, value: 1, to: boughtAt)
        } else if owned.contains(.monthly) {
            now.expires = Calendar.current.date(byAdding: .month, value: 1, to: boughtAt)
        }
        return now
    }

    func buy(_ plan: ProPlan) async -> ProPurchaseOutcome {
        try? await Task.sleep(for: .milliseconds(700))
        switch buyResult {
        case "cancel": return .cancelled
        case "pending": return .pending
        case "fail": return .failed(String(localized: "连不上 App Store"))
        default: break
        }
        // One subscription at a time, as in a subscription group.
        if plan.renews { owned.subtract([.monthly, .yearly]) }
        owned.insert(plan)
        boughtAt = Date()
        remember()
        return .bought
    }

    func restore() async throws {
        try? await Task.sleep(for: .milliseconds(500))
        guard let found = restoreResult else { return }
        guard let plan = ProPlan(rawValue: found) else { throw ProStoreFailure(message: String(localized: "连不上 App Store")) }
        owned.insert(plan)
        remember()
    }

    func manage() async throws {
        throw ProStoreFailure(message: String(localized: "调试商店没有订阅管理：真的商店会在这里打开系统的那一页"))
    }

    func listen(_ changed: @escaping @MainActor () -> Void) { self.changed = changed }

    func clear() {
        owned = []
        remember()
    }

    private func remember() {
        guard remembers else { return }
        UserDefaults.standard.set(owned.map(\.rawValue).sorted(), forKey: Self.ownedKey)
        UserDefaults.standard.set(boughtAt, forKey: Self.boughtAtKey)
    }
}
#endif

// MARK: - 典藏卡带 and their films

extension ProStore {
    /// The 典藏卡带 standing on the shelf: one for each purchase owned (铜
    /// with 月付, 银 with 年付, 金 with 永久), gone again when its purchase
    /// is. (A debug build's `--foldarc-gold-card=off` keeps them away, for
    /// the UI tests written before there were any; the last such argument
    /// counts.)
    var cartridges: [Cartridge] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.last(where: { $0.hasPrefix("--foldarc-gold-card=") }) == "--foldarc-gold-card=off" { return [] }
        #endif
        return Cartridge.owned(holdings.plans)
    }
}

/// When each 典藏卡带 became the player's — the store's first purchase of it
/// when it says so, else the first time this device saw it owned — kept on
/// this device (nothing of it is sent anywhere); and whether its opening
/// has said 「这盘卡带是你的了」 yet (once, the first time it plays).
@MainActor enum CartridgeRecord {
    /// A debug build's run that remembers nothing of the store
    /// (`--foldarc-pro=…`): kept for the run only.
    static var keepsNothing = false
    private static var run: [String: Any] = [:]
    private static func sinceKey(_ cartridge: Cartridge) -> String { "FoldArc.cartridge.\(cartridge.rawValue).since" }
    private static func welcomedKey(_ cartridge: Cartridge) -> String { "FoldArc.cartridge.\(cartridge.rawValue).welcomed" }
    private static func read(_ key: String) -> Any? { keepsNothing ? run[key] : UserDefaults.standard.object(forKey: key) }
    private static func write(_ value: Any, _ key: String) { if keepsNothing { run[key] = value } else { UserDefaults.standard.set(value, forKey: key) } }
    static func since(_ cartridge: Cartridge) -> Date? { read(sinceKey(cartridge)) as? Date }
    /// What is owned now: a card not seen before is dated (the store's date if
    /// it has one; an earlier date the store gives later takes its place).
    static func note(_ holdings: ProHoldings) {
        for cartridge in Cartridge.owned(holdings.plans) {
            let kept = since(cartridge)
            if let bought = holdings.since[cartridge.plan] {
                if kept.map({ bought < $0 }) ?? true { write(bought, sinceKey(cartridge)) }
            } else if kept == nil {
                write(Date(), sinceKey(cartridge))
            }
        }
    }
    /// Whether this is the card's first opening (and from now on it is not).
    static func firstOpening(_ cartridge: Cartridge) -> Bool {
        guard read(welcomedKey(cartridge)) as? Bool != true else { return false }
        write(true, welcomedKey(cartridge))
        return true
    }
    /// 入手: the date as the 卡带证 and the opening print it.
    static func sinceText(_ cartridge: Cartridge) -> String {
        (since(cartridge) ?? Date()).formatted(.dateTime.locale(UILanguage.locale).year().month().day())
    }
}

/// The metals the three cards are made of: the label's band, the name on
/// it, the shell, the small square on the menus, the wash over the picture.
struct CartridgeTint {
    var bandTop: Color, bandLow: Color, bandInk: Color, rule: Color
    var titleTop: Color, titleLow: Color
    var shellLight: Color, shellDark: Color
    var iconLight: Color, iconMid: Color, iconDark: Color, mark: Color
    var wash: Color
    /// The moulded shell's own colour (red, green, blue).
    var metal: (Double, Double, Double)
}

extension Cartridge {
    /// The card's name.
    var title: String {
        switch self {
        case .bronze: return String(localized: "铜卡带")
        case .silver: return String(localized: "银卡带")
        case .gold: return String(localized: "金卡带")
        }
    }
    /// What its films are, under the name on the card.
    var subtitle: String {
        switch self {
        case .bronze: return String(localized: "课间十分钟")
        case .silver, .gold: return String(localized: "小时候")
        }
    }
    /// The words along the label's band.
    var bandWord: String { rawValue.uppercased() + " CARTRIDGE" }
    var tint: CartridgeTint {
        switch self {
        case .gold:
            return CartridgeTint(bandTop: Color(red: 1.0, green: 0.93, blue: 0.66), bandLow: Color(red: 0.95, green: 0.78, blue: 0.36),
                                 bandInk: Color(red: 0.45, green: 0.30, blue: 0.08), rule: Color(red: 0.62, green: 0.42, blue: 0.10),
                                 titleTop: Color(red: 1.0, green: 0.96, blue: 0.72), titleLow: Color(red: 0.98, green: 0.76, blue: 0.28),
                                 shellLight: Color(red: 0.98, green: 0.84, blue: 0.44), shellDark: Color(red: 0.80, green: 0.58, blue: 0.18),
                                 iconLight: Color(red: 1.0, green: 0.90, blue: 0.56), iconMid: Color(red: 0.90, green: 0.66, blue: 0.20), iconDark: Color(red: 0.70, green: 0.46, blue: 0.12),
                                 mark: Color(red: 0.36, green: 0.22, blue: 0.05), wash: Color(red: 1.0, green: 0.80, blue: 0.30),
                                 metal: (0.95, 0.74, 0.28))
        case .silver:
            return CartridgeTint(bandTop: Color(red: 0.95, green: 0.96, blue: 0.98), bandLow: Color(red: 0.78, green: 0.81, blue: 0.86),
                                 bandInk: Color(red: 0.24, green: 0.28, blue: 0.35), rule: Color(red: 0.42, green: 0.47, blue: 0.55),
                                 titleTop: Color(red: 0.98, green: 0.99, blue: 1.0), titleLow: Color(red: 0.74, green: 0.79, blue: 0.87),
                                 shellLight: Color(red: 0.88, green: 0.90, blue: 0.93), shellDark: Color(red: 0.60, green: 0.63, blue: 0.69),
                                 iconLight: Color(red: 0.96, green: 0.97, blue: 0.99), iconMid: Color(red: 0.74, green: 0.77, blue: 0.82), iconDark: Color(red: 0.48, green: 0.51, blue: 0.58),
                                 mark: Color(red: 0.20, green: 0.23, blue: 0.30), wash: Color(red: 0.82, green: 0.88, blue: 1.0),
                                 metal: (0.82, 0.84, 0.88))
        case .bronze:
            return CartridgeTint(bandTop: Color(red: 0.93, green: 0.74, blue: 0.56), bandLow: Color(red: 0.76, green: 0.50, blue: 0.30),
                                 bandInk: Color(red: 0.31, green: 0.15, blue: 0.06), rule: Color(red: 0.48, green: 0.26, blue: 0.12),
                                 titleTop: Color(red: 0.99, green: 0.86, blue: 0.70), titleLow: Color(red: 0.88, green: 0.58, blue: 0.34),
                                 shellLight: Color(red: 0.84, green: 0.58, blue: 0.38), shellDark: Color(red: 0.58, green: 0.34, blue: 0.18),
                                 iconLight: Color(red: 0.94, green: 0.72, blue: 0.52), iconMid: Color(red: 0.74, green: 0.46, blue: 0.26), iconDark: Color(red: 0.50, green: 0.28, blue: 0.14),
                                 mark: Color(red: 0.27, green: 0.13, blue: 0.05), wash: Color(red: 1.0, green: 0.64, blue: 0.38),
                                 metal: (0.72, 0.45, 0.25))
        }
    }
}

/// What the 典藏卡带 in the console is playing: which card, which film of
/// its order, and since when.
@MainActor final class GoldReel: ObservableObject {
    static let shared = GoldReel()
    @Published private(set) var cartridge = Cartridge.gold
    @Published private(set) var index = 0
    @Published private(set) var began = Date()
    /// The opening (the card's name, its number and date) since when; nil: over.
    @Published private(set) var opening: Date?
    /// The opening says 「这盘卡带是你的了」 (the card's first).
    @Published private(set) var welcome = false
    /// The last film has played: its last picture stays (it does not go dark).
    @Published private(set) var ended = false
    /// The wind over the film (ReelWind): a finger's gusts across the lower screen, and a breath's on the
    /// microphone while it lasts.
    @Published private(set) var wind = ReelWind()
    /// The newest gust: when, and which way.
    var gustAt: Date? { wind.gusts.last?.at }
    var gustRight: Bool { wind.gusts.last?.right ?? true }
    /// 金卡带's film: the dust blown off what was left in the attic (GoldDustPlace.thing: when, which
    /// way). It stays off until a shot is chosen or the film begins again.
    @Published private(set) var dusted: [String: GoldDustBlow] = [:]
    /// 金卡带's film (GoldFilm): how far in it was at `began` (seconds), and
    /// since when it has stood still (its screen gone, the app away); nil:
    /// it plays on.
    @Published private(set) var offset = 0.0
    @Published private(set) var pausedAt: Date?
    /// One more each time the film is put somewhere, stopped or let go on:
    /// the player goes where the reel says then.
    @Published private(set) var cue = 0
    /// 银卡带's seasons in the order the card plays them: spring, summer,
    /// autumn, winter (11-23: always so; it used to begin with the season it was).
    @Published private(set) var seasons = SilverSeason.allCases
    static let openingSeconds = 3.6
    let plan = GoldReelPlan.stored()
    /// How many films the card playing has (金卡带: its film's shots).
    var count: Int { plan.count(cartridge) }
    /// 金卡带 plays its one film, a video; 银卡带 its four seasons, a video
    /// each; 铜卡带, films drawn as they play.
    var isFilm: Bool { cartridge == .gold }
    var isSeasons: Bool { cartridge == .silver }
    /// The card plays videos: they stand still while their screen is gone and go on after.
    var playsVideo: Bool { cartridge != .bronze }
    /// 银卡带's season now.
    var season: SilverSeason { seasons[index % seasons.count] }
    /// How long the video playing is (seconds).
    var filmLength: Double { isSeasons ? SilverSeason.length : GoldFilm.length }
    /// 铜卡带's game now.
    var game: FlipGame { plan.games[index % plan.games.count] }
    /// The name of the film (金卡带: the shot) playing, and its name for the log and the tests.
    var title: String { isFilm ? GoldFilm.title(index) : (isSeasons ? season.title : game.title) }
    var key: String { isFilm ? GoldFilm.shots[index % GoldFilm.shots.count].key : (isSeasons ? season.rawValue : game.rawValue) }
    /// Seconds into the video playing at `now` (0 ... its length).
    func filmTime(_ now: Date = Date()) -> Double {
        min(filmLength, max(0, offset + (pausedAt ?? now).timeIntervalSince(began)))
    }
    /// The line under the picture: this cartridge's one of the film's lines
    /// (the videos have none).
    var caption: String {
        if playsVideo { return "" }
        let lines = game.captions
        var numbers = plan.random(for: game)
        return lines[numbers.int(lines.count)]
    }
    /// The next film (or the one before), from its beginning.
    func step(_ delta: Int) {
        let count = self.count
        jump(((index + delta) % count + count) % count)
    }
    /// A film of the strip, from its beginning (金卡带: its film from that shot).
    func jump(_ to: Int) {
        index = max(0, min(count - 1, to))
        began = Date()
        opening = nil
        ended = false
        if playsVideo {
            offset = isFilm ? GoldFilm.shots[index].start : 0
            pausedAt = nil
            cue += 1
            dusted = [:]
        }
        NSLog("[gold] %@ film %d of %d: %@", cartridge.rawValue, index + 1, count, key)
    }
    /// From the first film (the cartridge has just gone in): the opening
    /// first, then the films.
    func rewind(_ cartridge: Cartridge) {
        self.cartridge = cartridge
        index = 0
        let now = Date()
        opening = now
        welcome = CartridgeRecord.firstOpening(cartridge)
        began = now.addingTimeInterval(Self.openingSeconds)
        ended = false
        offset = 0
        pausedAt = nil
        cue += 1
        dusted = [:]
        NSLog("[gold] %@ cartridge %@ plays: %@%@", cartridge.rawValue, plan.code,
              cartridge == .bronze ? plan.games.map(\.rawValue).joined(separator: ", ")
                : (cartridge == .gold ? "its film, \(GoldFilm.shots.count) shots" : seasons.map(\.rawValue).joined(separator: ", ")),
              welcome ? " (its first opening)" : "")
    }
    /// The opening cut short (A, or a film chosen).
    func skipOpening() {
        guard opening != nil else { return }
        opening = nil
        began = Date()
        if playsVideo { cue += 1 }
        NSLog("[gold] the opening skipped")
    }
    /// A film has played its length: on to the next; after the last, its
    /// last picture stays. (金卡带: the shot playing follows the film; at
    /// its end the last picture stays. 银卡带: the next season comes once a
    /// film has gone dark; the fourth's last picture is held before it does.)
    func tick(_ now: Date) {
        // (a breath sends a gust every little while: new lines of wind and stirred dust as it goes on; its wind
        // holds while it lasts — ReelWind; once nothing blows the gusts are let go, and the wind's layers with them)
        if breath, gustAt.map({ now.timeIntervalSince($0) > 1.2 }) ?? true { gust(right: breathRight, breath: true) }
        if !breath, wind.isStill(at: now) {
            wind = ReelWind()
            NSLog("[gold] the wind has died down")
        }
        if let opening, now.timeIntervalSince(opening) >= Self.openingSeconds { self.opening = nil }
        guard opening == nil, !ended else { return }
        if isFilm {
            guard pausedAt == nil else { return }
            let t = filmTime(now)
            let shot = GoldFilm.shot(at: t)
            if shot != index {
                index = shot
                NSLog("[gold] gold film: shot %d of %d (%@) at %.1f s", index + 1, count, key, t)
            }
            if t >= GoldFilm.length - 0.05 {
                ended = true
                NSLog("[gold] gold: the film has played; its last picture stays, the dust drifting")
            }
            return
        }
        if isSeasons {
            guard pausedAt == nil else { return }
            // (the reel's own time, not held at the film's length: the film has a moment to go dark
            // and its last sound to end before the next comes)
            let t = offset + now.timeIntervalSince(began)
            if index + 1 < count {
                guard t >= SilverSeason.length + 0.3 else { return }
                NSLog("[gold] silver: %@ has played; the next season", key)
                step(1)
            } else if t >= SilverSeason.holdAt {
                ended = true
                NSLog("[gold] silver: the last season has played (%@); its last picture stays", key)
            }
            return
        }
        guard now.timeIntervalSince(began) >= GoldReelPlan.seconds(cartridge) else { return }
        if index + 1 < count {
            step(1)
        } else {
            ended = true
            NSLog("[gold] %@: the last film has played; its picture stays", cartridge.rawValue)
        }
    }
    /// The video stands still where it is (its screen gone, the app away).
    /// An opening still showing is over: the film will begin from its start
    /// when it goes on.
    func pause(_ now: Date = Date()) {
        guard playsVideo, pausedAt == nil, !ended else { return }
        if opening != nil {
            opening = nil
            offset = 0
            began = now
        }
        pausedAt = now
        cue += 1
        NSLog("[gold] %@ film: stands still at %.1f s", cartridge.rawValue, filmTime(now))
    }
    /// …and goes on from there.
    func resume(_ now: Date = Date()) {
        guard playsVideo, let pausedAt else { return }
        began = began.addingTimeInterval(now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        cue += 1
        NSLog("[gold] %@ film: goes on from %.1f s", cartridge.rawValue, filmTime(now))
    }
    /// A finger across the lower screen: a gust over the picture.
    func gust(right: Bool, breath: Bool = false) {
        let now = Date()
        wind.blow(at: now, right: right, breath: breath)
        NSLog("[gold] a gust to the %@%@", right ? "right" : "left", breath ? " (a breath on the microphone)" : "")
        // 金卡带's film: the dust lying on what is in the picture now goes with it
        guard isFilm, opening == nil else { return }
        for (thing, picture) in GoldFilmDustPainter.things(t: ended ? GoldFilm.length : GoldFilmClock.shared.time(), ended: ended) where dusted[thing] == nil {
            dusted[thing] = GoldDustBlow(at: now, right: right)
            NSLog("[gold] the dust blown off the %@ (%@)", thing, picture)
        }
    }
    /// Someone blowing on the microphone (MicListener): a gust at once, another every little while
    /// as long as the breath lasts (tick); each new breath blows the other way. When the breath ends its wind
    /// dies down at once (ReelWind.calmSeconds): wind while someone blows, none after.
    @Published private(set) var breath = false
    private var breathRight = false
    func breathing(_ on: Bool) {
        guard on != breath else { return }
        breath = on
        guard on else {
            wind.calm(at: Date())
            NSLog("[gold] the breath has ended: its wind dies down")
            return
        }
        breathRight.toggle()
        gust(right: breathRight, breath: true)
    }
}

extension GoldScene {
    var title: String {
        switch self {
        case .wayHome: return String(localized: "放学路上")
        case .classroom: return String(localized: "教室午后")
        case .summerNight: return String(localized: "夏夜")
        case .rainyWindow: return String(localized: "雨天窗台")
        case .playground: return String(localized: "操场")
        }
    }
    /// The lines under the picture; a cartridge shows one of them.
    var captions: [String] {
        switch self {
        case .wayHome: return [String(localized: "放学路上，书包一颠一颠的。"), String(localized: "太阳还没落山，不着急回家。")]
        case .classroom: return [String(localized: "下午第二节课，粉笔灰在光里飘。"), String(localized: "窗外的树一直在晃，谁也没发现你在看。")]
        case .summerNight: return [String(localized: "夏天的晚上，电风扇摇着头，电视还开着。"), String(localized: "凉席、西瓜，和一个不想睡的晚上。")]
        case .rainyWindow: return [String(localized: "下雨天出不去，就趴在窗台上数雨点。"), String(localized: "等雨停了，就出去踩水。")]
        case .playground: return [String(localized: "操场上最后一个回家的人。"), String(localized: "风筝飞得比教学楼还高。")]
        }
    }
}

extension SilverSeason {
    /// The film's name (the strip, the lower screen, the picture's corner as it begins).
    var title: String {
        switch self {
        case .spring: return String(localized: "春 · 风筝")
        case .summer: return String(localized: "夏 · 夏夜")
        case .autumn: return String(localized: "秋 · 回家路上")
        case .winter: return String(localized: "冬 · 下雪了")
        }
    }
}

extension GoldFilm {
    /// The film's name.
    static var name: String { String(localized: "一台掌机的回忆") }
    /// A shot's name (the strip, the lower screen).
    static func title(_ index: Int) -> String {
        switch shots[min(max(index, 0), shots.count - 1)].key {
        case "birthday": return String(localized: "生日礼物")
        case "quilt": return String(localized: "被窝里")
        case "classroom": return String(localized: "课间")
        case "summer": return String(localized: "暑假")
        case "desk": return String(localized: "书堆")
        case "packing": return String(localized: "收进盒子")
        case "attic": return String(localized: "落灰")
        case "found": return String(localized: "翻出来")
        default: return String(localized: "屏幕亮了")
        }
    }
}

extension FlipGame {
    var title: String {
        switch self {
        case .jumpRope: return String(localized: "跳绳")
        case .shuttlecock: return String(localized: "踢毽子")
        }
    }
    /// The lines under the picture; a cartridge shows one of them.
    var captions: [String] {
        switch self {
        case .jumpRope: return [String(localized: "课间十分钟，跳绳要排队。"), String(localized: "一个、两个、三个……谁也别想打断。")]
        case .shuttlecock: return [String(localized: "毽子踢到第十个，上课铃就响了。"), String(localized: "踢了几个？课本角上用「正」字记着。")]
        }
    }
}

/// A colour as three numbers, to mix.
struct ReelRGB {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    var color: Color { Color(red: min(1, max(0, r)), green: min(1, max(0, g)), blue: min(1, max(0, b))) }
    func mixed(_ other: ReelRGB, _ t: Double) -> ReelRGB {
        let k = min(1, max(0, t))
        return ReelRGB(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }
    func scaled(_ k: Double) -> ReelRGB { ReelRGB(r * k, g * k, b * k) }
}

/// The picture is drawn on a sheet 160 across and 96 down, whatever the
/// screen's size: smooth shapes and soft light, in a few flat colours.
struct ReelSheet {
    static let width = 160.0, height = 96.0
    var context: GraphicsContext
    /// Points for one of the sheet's units.
    var unit: Double
    var origin: CGPoint

    private func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: origin.x + x * unit, y: origin.y + y * unit) }
    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: w * unit, height: h * unit)
    }
    /// The same sheet, drawing only inside a box of it.
    func clipped(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> ReelSheet {
        var inner = context
        inner.clip(to: Path(rect(x, y, w, h)))
        return ReelSheet(context: inner, unit: unit, origin: origin)
    }
    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color, _ round: Double = 0) {
        guard w > 0, h > 0 else { return }
        let r = rect(x, y, w, h)
        let corner = min(round * unit, Double(min(r.width, r.height)) / 2)
        context.fill(corner > 0.2 ? Path(roundedRect: r, cornerRadius: corner) : Path(r), with: .color(color))
    }
    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ rgb: ReelRGB, _ round: Double = 0) { box(x, y, w, h, rgb.color, round) }
    func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ color: Color) {
        guard rx > 0, ry > 0 else { return }
        context.fill(Path(ellipseIn: rect(cx - rx, cy - ry, rx * 2, ry * 2)), with: .color(color))
    }
    func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rgb: ReelRGB) { oval(cx, cy, rx, ry, rgb.color) }
    func disc(_ cx: Double, _ cy: Double, _ radius: Double, _ color: Color) { oval(cx, cy, radius, radius, color) }
    func disc(_ cx: Double, _ cy: Double, _ radius: Double, _ rgb: ReelRGB) { oval(cx, cy, radius, radius, rgb.color) }
    /// A round line, not filled.
    func circle(_ cx: Double, _ cy: Double, _ radius: Double, _ color: Color, _ width: Double = 0.3) {
        guard radius > 0 else { return }
        context.stroke(Path(ellipseIn: rect(cx - radius, cy - radius, radius * 2, radius * 2)), with: .color(color), lineWidth: width * unit)
    }
    /// A filled shape with straight sides.
    func shape(_ points: [(Double, Double)], _ color: Color) {
        guard points.count > 2 else { return }
        context.fill(outline(points), with: .color(color))
    }
    private func outline(_ points: [(Double, Double)]) -> Path {
        var outline = Path()
        guard let first = points.first else { return outline }
        outline.move(to: point(first.0, first.1))
        for p in points.dropFirst() { outline.addLine(to: point(p.0, p.1)) }
        outline.closeSubpath()
        return outline
    }
    /// A filled shape going from one colour at `a` to another at `b`.
    func shape(_ points: [(Double, Double)], from a: (Double, Double), _ first: Color, to b: (Double, Double), _ second: Color) {
        guard points.count > 2 else { return }
        context.fill(outline(points), with: .linearGradient(Gradient(colors: [first, second]), startPoint: point(a.0, a.1), endPoint: point(b.0, b.1)))
    }
    /// The same sheet, drawing only inside a shape of it.
    func clipped(to points: [(Double, Double)]) -> ReelSheet {
        var inner = context
        inner.clip(to: outline(points))
        return ReelSheet(context: inner, unit: unit, origin: origin)
    }
    func shape(_ points: [(Double, Double)], _ rgb: ReelRGB) { shape(points, rgb.color) }
    /// A line through the points, its ends and corners round.
    func path(_ points: [(Double, Double)], _ color: Color, _ width: Double = 0.6) {
        guard points.count > 1 else { return }
        var route = Path()
        route.move(to: point(points[0].0, points[0].1))
        for p in points.dropFirst() { route.addLine(to: point(p.0, p.1)) }
        context.stroke(route, with: .color(color), style: StrokeStyle(lineWidth: width * unit, lineCap: .round, lineJoin: .round))
    }
    func path(_ points: [(Double, Double)], _ rgb: ReelRGB, _ width: Double = 0.6) { path(points, rgb.color, width) }
    func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ color: Color, _ width: Double = 0.6) { path([(x0, y0), (x1, y1)], color, width) }
    func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ rgb: ReelRGB, _ width: Double = 0.6) { path([(x0, y0), (x1, y1)], rgb.color, width) }
    /// A line through the points, bent smoothly from one to the next.
    func curve(_ points: [(Double, Double)], _ color: Color, _ width: Double = 0.6) {
        guard points.count > 2 else { path(points, color, width); return }
        var route = Path()
        route.move(to: point(points[0].0, points[0].1))
        for i in 0..<(points.count - 1) {
            let before = points[max(0, i - 1)], from = points[i], to = points[i + 1], after = points[min(points.count - 1, i + 2)]
            let first = point(from.0 + (to.0 - before.0) / 6, from.1 + (to.1 - before.1) / 6)
            let second = point(to.0 - (after.0 - from.0) / 6, to.1 - (after.1 - from.1) / 6)
            route.addCurve(to: point(to.0, to.1), control1: first, control2: second)
        }
        context.stroke(route, with: .color(color), style: StrokeStyle(lineWidth: width * unit, lineCap: .round, lineJoin: .round))
    }
    /// Small print, its top left corner at (x, y), `size` of the sheet's units high.
    func smallPrint(_ text: String, _ x: Double, _ y: Double, _ size: Double, _ color: Color) {
        context.draw(Text(verbatim: text).font(.system(size: size * unit, weight: .regular, design: .serif)).foregroundColor(color), at: point(x, y), anchor: .topLeading)
    }
    /// A box going from one colour at its top to another at its foot.
    func fade(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ top: ReelRGB, _ low: ReelRGB) {
        guard w > 0, h > 0 else { return }
        let r = rect(x, y, w, h)
        context.fill(Path(r), with: .linearGradient(Gradient(colors: [top.color, low.color]), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
    }
    /// The sky: one colour at the top to another at `bottom`.
    func sky(_ top: ReelRGB, _ low: ReelRGB, bottom: Double) { fade(0, 0, Self.width, bottom, top, low) }
    /// Light round a point: the colour at the middle, nothing at `radius`.
    func glow(_ cx: Double, _ cy: Double, _ radius: Double, _ color: Color) {
        guard radius > 0 else { return }
        context.fill(Path(ellipseIn: rect(cx - radius, cy - radius, radius * 2, radius * 2)),
                     with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: point(cx, cy), startRadius: 0, endRadius: radius * unit))
    }
    /// The corners a little darker, as an old lens leaves them.
    func vignette(_ strength: Double) {
        let reach = (Self.width * Self.width + Self.height * Self.height).squareRoot() / 2 * unit
        context.fill(Path(rect(0, 0, Self.width, Self.height)),
                     with: .radialGradient(Gradient(colors: [Color.black.opacity(0), Color.black.opacity(strength)]), center: point(Self.width / 2, Self.height / 2), startRadius: reach * 0.62, endRadius: reach))
    }
    /// A number 0 ..< 1 that is the same for the same two whole numbers.
    static func noise(_ a: Int, _ b: Int) -> Double {
        var z = UInt64(truncatingIfNeeded: a &* 73_856_093) ^ UInt64(truncatingIfNeeded: b &* 19_349_663)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / 9_007_199_254_740_992.0
    }
}

/// One film, at one moment.
struct GoldScenePainter {
    var scene: GoldScene
    var random: ReelRandom
    /// Seconds since the film began.
    var t: Double

    func draw(_ context: GraphicsContext, size: CGSize) {
        let unit = min(size.width / ReelSheet.width, size.height / ReelSheet.height)
        guard unit > 0 else { return }
        let origin = CGPoint(x: (size.width - unit * ReelSheet.width) / 2, y: (size.height - unit * ReelSheet.height) / 2)
        var clipped = context
        clipped.clip(to: Path(CGRect(x: origin.x, y: origin.y, width: unit * ReelSheet.width, height: unit * ReelSheet.height)))
        let sheet = ReelSheet(context: clipped, unit: unit, origin: origin)
        var numbers = random
        switch scene {
        case .wayHome: wayHome(sheet, &numbers)
        case .classroom: classroom(sheet, &numbers)
        case .summerNight: summerNight(sheet, &numbers)
        case .rainyWindow: rainyWindow(sheet, &numbers)
        case .playground: playground(sheet, &numbers)
        }
        sheet.vignette(0.30)
        // The film comes up out of black and goes back into it.
        let fade = max(0, 1 - t / 1.2) + max(0, (t - (GoldReelPlan.sceneSeconds - 1.0)) / 1.0)
        if fade > 0.01 { sheet.box(0, 0, ReelSheet.width, ReelSheet.height, Color.black.opacity(min(1, fade))) }
    }

    /// A shape pointed at both ends (a leaf, a fan's blade), from (x, y) along `angle`.
    private func leaf(_ d: ReelSheet, _ x: Double, _ y: Double, _ angle: Double, _ length: Double, _ width: Double, _ color: Color) {
        let ca = cos(angle), sa = sin(angle)
        var flat: [(Double, Double)] = []
        for i in 0...8 {
            let u = Double(i) / 8
            flat.append((u * length, sin(u * Double.pi) * width / 2))
        }
        for i in 1...7 {
            let u = Double(8 - i) / 8
            flat.append((u * length, -sin(u * Double.pi) * width / 2))
        }
        var turned: [(Double, Double)] = []
        for p in flat { turned.append((x + p.0 * ca - p.1 * sa, y + p.0 * sa + p.1 * ca)) }
        d.shape(turned, color)
    }

    /// A cloud with a flat underside from (x, y), `w` long.
    private func cloud(_ d: ReelSheet, _ x: Double, _ y: Double, _ w: Double, _ body: ReelRGB, _ light: ReelRGB) {
        d.oval(x + w * 0.30, y + 0.3, w * 0.20, 2.7, body)
        d.oval(x + w * 0.56, y - 0.7, w * 0.24, 3.6, body)
        d.oval(x + w * 0.80, y + 0.5, w * 0.15, 2.0, body)
        d.box(x, y, w, 2.6, body, 1.3)
        d.oval(x + w * 0.52, y - 1.6, w * 0.15, 1.6, light)
    }

    /// A straight piece with flat ends, `w0` wide at one and `w1` at the other.
    private func limb(_ d: ReelSheet, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ w0: Double, _ w1: Double, _ color: Color) {
        let dx = x1 - x0, dy = y1 - y0
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.001 else { return }
        let nx = -dy / length / 2, ny = dx / length / 2
        d.shape([(x0 + nx * w0, y0 + ny * w0), (x1 + nx * w1, y1 + ny * w1), (x1 - nx * w1, y1 - ny * w1), (x0 - nx * w0, y0 - ny * w0)], color)
    }

    /// A child's head from the side, facing right, round (cx, cy). `sway`
    /// moves the tied-back hair; `wink` sets when the eye shuts.
    private func head(_ d: ReelSheet, _ cx: Double, _ cy: Double, _ k: Double, girl: Bool, sway: Double, wink: Double) {
        let skin = Color(red: 0.97, green: 0.82, blue: 0.69), shade = Color(red: 0.90, green: 0.71, blue: 0.58), hair = Color(red: 0.15, green: 0.11, blue: 0.10)
        func P(_ dx: Double, _ dy: Double) -> (Double, Double) { (cx + dx * k, cy + dy * k) }
        if girl {
            // The hair tied back, swinging behind.
            leaf(d, cx - 2.3 * k, cy - 0.9 * k, 1.95 + sway * 0.4, 5.0 * k, 2.3 * k, hair)
            d.disc(cx - 2.35 * k, cy - 0.85 * k, 0.6 * k, Color(red: 0.92, green: 0.30, blue: 0.34))
        }
        d.oval(cx - 0.5 * k, cy - 0.55 * k, 2.9 * k, 2.75 * k, hair)
        // The face, its nose, the ear.
        d.oval(cx + 0.35 * k, cy + 0.35 * k, 2.35 * k, 2.4 * k, skin)
        d.disc(cx + 2.62 * k, cy + 0.45 * k, 0.42 * k, skin)
        d.oval(cx - 0.75 * k, cy + 0.6 * k, 0.55 * k, 0.72 * k, shade)
        // The fringe, and the light on the hair.
        let fringe: [(Double, Double)] = [P(-1.6, -2.1), P(0.4, -2.95), P(2.1, -2.4), P(2.8, -1.25), P(2.15, -1.45), P(1.75, -0.8), P(1.2, -1.5),
                                          P(0.55, -0.75), P(0.0, -1.5), P(-0.7, -0.85), P(-1.3, -1.4)]
        d.shape(fringe, hair)
        let shine: [(Double, Double)] = [P(-1.9, -2.2), P(-0.7, -2.85), P(0.8, -2.8)]
        d.path(shine, Color(red: 0.42, green: 0.32, blue: 0.27).opacity(0.9), 0.32 * k)
        // The eye (it shuts for a moment now and then), the brow, the mouth, the cheek.
        if (t + wink).truncatingRemainder(dividingBy: 3.7) < 0.13 {
            d.line(cx + 1.15 * k, cy + 0.08 * k, cx + 2.0 * k, cy + 0.08 * k, hair, 0.24 * k)
        } else {
            d.oval(cx + 1.55 * k, cy, 0.5 * k, 0.64 * k, Color.white)
            d.oval(cx + 1.68 * k, cy + 0.03 * k, 0.33 * k, 0.5 * k, Color(red: 0.16, green: 0.10, blue: 0.08))
            d.disc(cx + 1.78 * k, cy - 0.17 * k, 0.13 * k, Color.white)
        }
        d.line(cx + 1.05 * k, cy - 0.98 * k, cx + 2.0 * k, cy - 1.08 * k, hair.opacity(0.85), 0.24 * k)
        let smile: [(Double, Double)] = [P(1.6, 1.38), P(1.95, 1.52), P(2.32, 1.32)]
        d.path(smile, Color(red: 0.55, green: 0.22, blue: 0.20).opacity(0.85), 0.2 * k)
        d.disc(cx + 0.95 * k, cy + 1.0 * k, 0.62 * k, Color(red: 1.0, green: 0.50, blue: 0.48).opacity(0.36))
    }

    /// A child seen from the side, facing right, `x` under the hips and
    /// `feet` on the ground: walking (the knees and elbows bend), or standing
    /// (with `hand`, the near arm reaches to that point). `k`: how big.
    private func child(_ d: ReelSheet, x: Double, feet: Double, bag: ReelRGB, walking: Bool, hand: (Double, Double)? = nil, k: Double = 1, girl: Bool = false) {
        let skin = ReelRGB(0.97, 0.82, 0.69), navy = ReelRGB(0.17, 0.22, 0.40), shirt = ReelRGB(0.97, 0.97, 0.95)
        let red = Color(red: 0.88, green: 0.20, blue: 0.18), sneaker = Color(red: 0.96, green: 0.96, blue: 0.98)
        let l1 = 3.6 * k, l2 = 3.6 * k
        let p = t * 5.2
        /// A leg's two angles from straight down: the thigh's, the shin's.
        func bones(_ phase: Double, _ front: Bool) -> (Double, Double) {
            guard walking else { return front ? (0.09, 0.09) : (-0.09, -0.09) }
            let thigh = 0.52 * sin(phase)
            return (thigh, thigh - 0.10 - 0.90 * max(0, cos(phase)))
        }
        let near = bones(p, true), far = bones(p + Double.pi, false)
        let dropNear = l1 * cos(near.0) + l2 * cos(near.1), dropFar = l1 * cos(far.0) + l2 * cos(far.1)
        // (The hips ride on whichever leg reaches the ground.)
        let hipY = feet - 1.25 * k - max(dropNear, dropFar)
        let cx = x
        let sway = walking ? sin(p) : 0.0
        d.oval(cx + 0.3 * k, feet + 0.25 * k, 4.4 * k, 0.65 * k, Color.black.opacity(0.22))
        func leg(_ angles: (Double, Double), _ tone: Double) {
            let kx = cx + l1 * sin(angles.0), ky = hipY + l1 * cos(angles.0)
            let ax = kx + l2 * sin(angles.1), ay = ky + l2 * cos(angles.1)
            d.line(cx, hipY, kx, ky, skin.scaled(tone), 1.45 * k)
            d.line(kx, ky, ax, ay, skin.scaled(tone), 1.3 * k)
            if !girl { limb(d, cx, hipY - 0.5 * k, cx + (kx - cx) * 0.62, hipY + (ky - hipY) * 0.62, 2.4 * k, 2.1 * k, navy.scaled(tone).color) }
            // The sock, the shoe with its sole and its stripe.
            d.line(ax + (kx - ax) * 0.20, ay + (ky - ay) * 0.20, ax, ay, Color(white: 0.97 * tone), 1.4 * k)
            d.box(ax - 0.85 * k, ay - 0.15 * k, 3.0 * k, 1.4 * k, tone < 1 ? Color(white: 0.80) : sneaker, 0.65 * k)
            d.box(ax - 0.85 * k, ay + 0.85 * k, 3.0 * k, 0.4 * k, Color(white: 0.32), 0.2 * k)
            d.box(ax + 0.2 * k, ay + 0.2 * k, 1.0 * k, 0.32 * k, red, 0.15 * k)
        }
        func arm(_ swing: Double, _ tone: Double, _ to: (Double, Double)?) {
            let sx = cx + 0.2 * k, sy = hipY - 5.5 * k
            var ex = sx + 2.5 * k * sin(swing), ey = sy + 2.5 * k * cos(swing)
            var hx = ex + 2.4 * k * sin(swing + 0.45), hy = ey + 2.4 * k * cos(swing + 0.45)
            if let to {
                hx = to.0; hy = to.1
                ex = (sx + hx) / 2 + 0.5 * k; ey = (sy + hy) / 2 + 0.6 * k
            }
            d.line(sx, sy, ex, ey, skin.scaled(tone), 1.2 * k)
            d.line(ex, ey, hx, hy, skin.scaled(tone), 1.1 * k)
            d.disc(hx, hy, 0.72 * k, skin.scaled(tone))
            // The short sleeve.
            d.line(sx, sy, sx + (ex - sx) * 0.62, sy + (ey - sy) * 0.62, shirt.scaled(tone < 1 ? 0.92 : 1.0), 1.75 * k)
        }
        // The far arm and leg.
        arm(0.55 * sway, 0.86, nil)
        leg(far, 0.86)
        // The bag on the back: its flap, its pocket, its buckle.
        let deep = bag.scaled(0.78)
        d.box(cx - 5.7 * k, hipY - 6.4 * k, 4.0 * k, 6.4 * k, bag, 1.4 * k)
        d.box(cx - 5.7 * k, hipY - 6.4 * k, 4.0 * k, 2.4 * k, deep, 1.2 * k)
        d.box(cx - 5.3 * k, hipY - 3.1 * k, 2.5 * k, 2.3 * k, Color.white.opacity(0.22), 0.7 * k)
        d.box(cx - 4.3 * k, hipY - 4.4 * k, 0.9 * k, 0.9 * k, Color.white.opacity(0.7), 0.25 * k)
        // The body, the bag's strap across it.
        d.box(cx - 2.05 * k, hipY - 1.6 * k, 4.1 * k, 2.7 * k, navy, 1.1 * k)
        d.box(cx - 2.15 * k, hipY - 6.5 * k, 4.3 * k, 5.6 * k, shirt, 1.6 * k)
        d.box(cx - 2.15 * k, hipY - 5.4 * k, 1.0 * k, 3.9 * k, Color.black.opacity(0.06), 0.5 * k)
        let strap: [(Double, Double)] = [(cx - 1.7 * k, hipY - 6.2 * k), (cx + 0.2 * k, hipY - 6.45 * k), (cx + 0.75 * k, hipY - 4.6 * k), (cx - 1.5 * k, hipY - 2.0 * k)]
        d.path(strap, deep, 0.7 * k)
        // The near leg; a skirt over both, if she wears one.
        leg(near, 1.0)
        if girl {
            let flare = sway * 0.5 * k
            let skirt: [(Double, Double)] = [(cx - 2.1 * k, hipY - 1.5 * k), (cx + 2.1 * k, hipY - 1.5 * k), (cx + 3.1 * k + flare, hipY + 2.6 * k), (cx - 3.1 * k + flare, hipY + 2.6 * k)]
            d.shape(skirt, navy)
            for pleat in [-1.0, 0.0, 1.0] {
                d.line(cx + pleat * 1.0 * k, hipY - 0.9 * k, cx + pleat * 1.7 * k + flare, hipY + 2.4 * k, navy.scaled(0.72), 0.22 * k)
            }
        }
        // The neck, the scarf and its two ends, the near arm, the head.
        d.box(cx - 0.3 * k, hipY - 7.4 * k, 1.5 * k, 1.6 * k, skin.scaled(0.95))
        leaf(d, cx + 1.15 * k, hipY - 5.5 * k, 1.75 + sway * 0.22, 2.5 * k, 0.9 * k, Color(red: 0.74, green: 0.14, blue: 0.14))
        leaf(d, cx + 1.15 * k, hipY - 5.5 * k, 1.30 + sway * 0.18, 2.2 * k, 0.9 * k, red)
        let knot: [(Double, Double)] = [(cx - 0.9 * k, hipY - 6.75 * k), (cx + 2.0 * k, hipY - 6.6 * k), (cx + 1.2 * k, hipY - 5.1 * k)]
        d.shape(knot, red)
        arm(-0.55 * sway, 1.0, hand)
        head(d, cx + 0.55 * k, hipY - 9.7 * k, k, girl: girl, sway: sway, wink: 0)
    }

    /// A child sitting on the swing's seat at (sx, sy), facing right, a hand
    /// on the rope at `grip`, the shins swinging by `kick`.
    private func rider(_ d: ReelSheet, _ sx: Double, _ sy: Double, kick: Double, grip: (Double, Double), k: Double, girl: Bool) {
        let skin = ReelRGB(0.97, 0.82, 0.69), navy = ReelRGB(0.17, 0.22, 0.40), shirt = ReelRGB(0.97, 0.97, 0.95)
        let hx = sx - 0.4 * k, hy = sy - 0.9 * k
        let kx = hx + 3.3 * k, ky = hy + 0.4 * k
        let ax = kx + 3.4 * k * sin(0.30 + kick), ay = ky + 3.4 * k * cos(0.30 + kick)
        d.line(hx, hy, kx, ky, skin, 1.45 * k); d.line(kx, ky, ax, ay, skin, 1.3 * k)
        if girl {
            let skirt: [(Double, Double)] = [(hx - 1.9 * k, hy - 1.2 * k), (kx - 0.2 * k, hy - 1.0 * k), (kx + 0.2 * k, ky + 1.9 * k), (hx - 1.7 * k, hy + 1.3 * k)]
            d.shape(skirt, navy)
        } else {
            limb(d, hx - 0.4 * k, hy, hx + (kx - hx) * 0.72, hy + (ky - hy) * 0.72, 2.4 * k, 2.1 * k, navy.color)
        }
        d.line(ax + (kx - ax) * 0.20, ay + (ky - ay) * 0.20, ax, ay, Color(white: 0.97), 1.4 * k)
        d.box(ax - 0.85 * k, ay - 0.15 * k, 3.0 * k, 1.4 * k, Color(red: 0.96, green: 0.96, blue: 0.98), 0.65 * k)
        d.box(ax - 0.85 * k, ay + 0.85 * k, 3.0 * k, 0.4 * k, Color(white: 0.32), 0.2 * k)
        d.box(hx - 2.0 * k, hy - 1.5 * k, 3.8 * k, 2.5 * k, navy, 1.0 * k)
        d.box(hx - 2.1 * k, hy - 6.4 * k, 4.2 * k, 5.6 * k, shirt, 1.6 * k)
        d.box(hx - 0.3 * k, hy - 7.3 * k, 1.5 * k, 1.6 * k, skin.scaled(0.95))
        let knot: [(Double, Double)] = [(hx - 0.9 * k, hy - 6.65 * k), (hx + 2.0 * k, hy - 6.5 * k), (hx + 1.2 * k, hy - 5.0 * k)]
        d.shape(knot, Color(red: 0.88, green: 0.20, blue: 0.18))
        // The arm up to the rope.
        let s0x = hx + 0.3 * k, s0y = hy - 5.4 * k
        let ex = (s0x + grip.0) / 2 + 0.9 * k, ey = (s0y + grip.1) / 2 + 0.9 * k
        d.line(s0x, s0y, ex, ey, skin, 1.2 * k); d.line(ex, ey, grip.0, grip.1, skin, 1.1 * k)
        d.disc(grip.0, grip.1, 0.72 * k, skin)
        d.line(s0x, s0y, s0x + (ex - s0x) * 0.62, s0y + (ey - s0y) * 0.62, shirt, 1.75 * k)
        head(d, hx + 0.55 * k, hy - 9.6 * k, k, girl: girl, sway: kick * 2, wink: 1.3)
    }

    // 回家路上: a street at sundown going by, the child walking home.
    private func wayHome(_ d: ReelSheet, _ n: inout ReelRandom) {
        let mood = n.int(3)
        let top = [ReelRGB(0.22, 0.18, 0.44), ReelRGB(0.30, 0.20, 0.42), ReelRGB(0.16, 0.24, 0.48)][mood]
        let low = [ReelRGB(1.0, 0.62, 0.30), ReelRGB(1.0, 0.56, 0.52), ReelRGB(1.0, 0.78, 0.36)][mood]
        d.sky(top, low, bottom: 70)
        let sunX = n.range(28, 132)
        let warm = low.mixed(ReelRGB(1, 1, 0.85), 0.75).color
        d.glow(sunX, 42, 30, warm.opacity(0.55))
        d.disc(sunX, 42, 9.6, warm.opacity(0.55))
        d.disc(sunX, 42, 7, Color(red: 1, green: 0.97, blue: 0.82))
        // Clouds drifting.
        let clouds = 2 + n.int(3)
        for _ in 0..<clouds {
            let base = n.range(0, 200), y = n.range(8, 34), speed = n.range(1.2, 3.0), w = n.range(14, 26)
            let x = (base + t * speed).truncatingRemainder(dividingBy: 200) - 30
            let body = top.mixed(low, 0.2 + y / 60).mixed(ReelRGB(1, 0.86, 0.86), 0.42)
            cloud(d, x, y, w, body, body.mixed(ReelRGB(1, 0.96, 0.9), 0.35))
        }
        // Birds going home too.
        let birds = 1 + n.int(3)
        for _ in 0..<birds {
            let bx = (n.range(0, 160) + t * n.range(5, 9)).truncatingRemainder(dividingBy: 180) - 10, by = n.range(10, 30)
            let flap = sin(t * 7 + bx / 9) * 1.1
            d.path([(bx - 1.9, by - flap), (bx, by), (bx + 1.9, by - flap)], Color(red: 0.12, green: 0.08, blue: 0.16), 0.45)
        }
        // Roofs far off, going by more slowly than the street's.
        let street = n.int(1000)
        let scroll = t * 5
        let haze = top.mixed(low, 0.5).mixed(ReelRGB(0.24, 0.14, 0.34), 0.5)
        var fx = -((scroll * 0.35).truncatingRemainder(dividingBy: 200))
        var k = 0
        while fx < 360 {
            let slot = k % 11
            let w = 9 + Double(Int(ReelSheet.noise(street + 41, slot) * 12)), h = 6 + Double(Int(ReelSheet.noise(street + 43, slot) * 18))
            if fx + w > 0 && fx < 160 {
                d.box(fx, 70 - h - 8, w, h + 8, haze)
                if ReelSheet.noise(street + 47, slot) > 0.6 { d.shape([(fx, 70 - h - 8), (fx + w / 2, 70 - h - 11), (fx + w, 70 - h - 8)], haze) }
            }
            fx += w + 0.5
            k += 1
        }
        // The houses along the street; some windows lit.
        let wall = top.mixed(ReelRGB(0.05, 0.03, 0.10), 0.72)
        let lit = Color(red: 1.0, green: 0.86, blue: 0.48)
        let dark = wall.mixed(ReelRGB(0.50, 0.46, 0.62), 0.16)
        var hx = -(scroll.truncatingRemainder(dividingBy: 240))
        k = 0
        while hx < 400 {
            let slot = k % 12
            let w = 14 + Double(Int(ReelSheet.noise(street, slot) * 14)), h = 14 + Double(Int(ReelSheet.noise(street + 7, slot) * 26))
            if hx + w > 0 && hx < 160 {
                d.box(hx, 70 - h, w, h + 0.3, wall)
                let roof = ReelSheet.noise(street + 3, slot)
                if roof > 0.66 {
                    d.box(hx + 2, 70 - h - 2, w - 4, 2.4, wall)
                } else if roof > 0.33 {
                    // A tank and an aerial.
                    d.box(hx + w - 6, 70 - h - 3, 3.4, 3.2, wall, 0.7)
                    d.line(hx + 3, 70 - h, hx + 3, 70 - h - 5, wall, 0.35)
                    d.line(hx + 1.6, 70 - h - 4.2, hx + 4.4, 70 - h - 4.2, wall, 0.3)
                } else {
                    d.shape([(hx - 0.8, 70 - h), (hx + w / 2, 70 - h - 4), (hx + w + 0.8, 70 - h)], wall)
                }
                var wy = 70 - h + 3.0
                var row = 0
                while wy < 66 {
                    var wx = hx + 2
                    var col = 0
                    while wx < hx + w - 3 {
                        let v = ReelSheet.noise(street + slot * 31 + row * 7, col)
                        if v > 0.55 {
                            d.box(wx - 0.5, wy - 0.5, 2.9, 3.4, lit.opacity(0.16), 0.9)
                            d.box(wx, wy, 1.9, 2.4, lit, 0.3)
                        } else if v > 0.2 {
                            d.box(wx, wy, 1.9, 2.4, dark, 0.3)
                        }
                        wx += 4; col += 1
                    }
                    wy += 5; row += 1
                }
            }
            hx += w + 2
            k += 1
        }
        // Poles and their wires.
        let pole = Color(red: 0.10, green: 0.07, blue: 0.12)
        let first = -((t * 9).truncatingRemainder(dividingBy: 64))
        for i in 0..<5 {
            let x0 = first + Double(i) * 64
            d.box(x0, 34, 1.3, 44, pole)
            d.box(x0 - 4.2, 36.6, 9.7, 0.8, pole, 0.3)
            d.box(x0 - 3.0, 39.4, 7.3, 0.7, pole, 0.3)
            d.box(x0 - 4.1, 35.6, 0.8, 1.1, pole); d.box(x0 + 4.6, 35.6, 0.8, 1.1, pole)
            let wires: [(Double, Double)] = [(-3.7, 7.0), (5.0, 6.0)]
            for (dx, sag) in wires {
                var hung: [(Double, Double)] = []
                for j in 0...16 {
                    let u = Double(j) / 16
                    hung.append((x0 + dx + 64 * u, 36.4 + sag * (1 - (2 * u - 1) * (2 * u - 1))))
                }
                d.path(hung, pole.opacity(0.85), 0.32)
            }
        }
        // The pavement and the road.
        d.box(0, 69.8, 160, 8.2, top.mixed(ReelRGB(0.30, 0.22, 0.26), 0.7))
        let joint = -((t * 14).truncatingRemainder(dividingBy: 16))
        for i in 0..<12 { d.box(joint + Double(i) * 16, 70, 0.3, 7.4, Color.black.opacity(0.10)) }
        d.box(0, 77.4, 160, 0.9, top.mixed(ReelRGB(0.44, 0.36, 0.38), 0.7))
        d.box(0, 78.2, 160, 17.8, top.mixed(ReelRGB(0.14, 0.12, 0.18), 0.8))
        let dash = -((t * 14).truncatingRemainder(dividingBy: 24))
        for i in 0..<9 { d.box(dash + Double(i) * 24, 86.8, 10, 0.9, Color(red: 0.86, green: 0.80, blue: 0.62).opacity(0.7), 0.45) }
        let bags = [ReelRGB(0.86, 0.22, 0.20), ReelRGB(0.20, 0.44, 0.80), ReelRGB(0.95, 0.74, 0.20), ReelRGB(0.22, 0.62, 0.42)]
        let bag = bags[n.int(bags.count)]
        // The long shadow sundown gives, away from the sun.
        let away = sunX < 76 ? 1.0 : -1.0
        d.shape([(72.4, 80.9), (76.0, 80.9), (74 + away * 30 + 3.5, 83.0), (74 + away * 30 - 4.5, 83.0)], Color.black.opacity(0.24))
        child(d, x: 74, feet: 80.6, bag: bag, walking: true, k: 1.5, girl: n.int(2) == 1)
    }

    // 教室午后: the blackboard, the desks, the light from the window.
    private func classroom(_ d: ReelSheet, _ n: inout ReelRandom) {
        let warm = n.unit()
        let wall = ReelRGB(0.93, 0.89, 0.78).mixed(ReelRGB(0.96, 0.86, 0.70), warm)
        d.box(0, 0, 160, 66.2, wall)
        let dado = wall.mixed(ReelRGB(0.42, 0.62, 0.52), 0.55)
        d.box(0, 44, 160, 22.2, dado)
        d.box(0, 43.6, 160, 0.7, dado.scaled(0.86))
        let floor = ReelRGB(0.58, 0.42, 0.28)
        d.box(0, 66, 160, 30, floor)
        d.box(0, 66, 160, 0.8, floor.scaled(0.72))
        for i in 0..<8 { d.box(0, 69.3 + Double(i) * 3.8, 160, 0.35, floor.scaled(0.86)) }
        // The blackboard, with what the chalk left.
        d.box(9.4, 11.4, 77.2, 33.4, ReelRGB(0.42, 0.30, 0.18), 0.8)
        d.box(12, 14, 72, 28, ReelRGB(0.10, 0.28, 0.22), 0.4)
        d.box(14, 15, 40, 9, Color.white.opacity(0.035), 4); d.box(40, 28, 40, 10, Color.white.opacity(0.03), 5)
        let chalk = Color(red: 0.92, green: 0.94, blue: 0.90).opacity(0.85)
        let lines = 3 + n.int(3)
        for i in 0..<lines {
            let y = 18 + Double(i) * 5, start = 16 + n.range(0, 8), length = n.range(18, 56)
            var x = start
            while x < start + length {
                let piece = 1 + Double(Int(ReelSheet.noise(Int(x), i + 11) * 4))
                if ReelSheet.noise(Int(x), i) > 0.25 {
                    d.path([(x, y + 0.6), (x + piece * 0.33, y - 0.5), (x + piece * 0.66, y + 0.5), (x + piece, y - 0.3)], chalk, 0.42)
                }
                x += piece + 1
            }
        }
        d.box(12, 42, 72, 1.3, ReelRGB(0.34, 0.24, 0.14))
        d.box(14, 41.3, 6, 0.8, Color.white.opacity(0.9), 0.3); d.box(70, 41.3, 4, 0.8, Color(red: 1.0, green: 0.86, blue: 0.5).opacity(0.9), 0.3)
        d.box(58, 40.6, 5.4, 1.5, ReelRGB(0.30, 0.34, 0.52), 0.4)
        // The clock over it; its long hand moves.
        d.disc(48, 6, 5, ReelRGB(0.34, 0.24, 0.16))
        d.disc(48, 6, 4.2, Color(red: 0.98, green: 0.98, blue: 0.96))
        for mark in 0..<12 {
            let a = Double(mark) * Double.pi / 6
            d.line(48 + cos(a) * 3.4, 6 + sin(a) * 3.4, 48 + cos(a) * 3.8, 6 + sin(a) * 3.8, Color(white: 0.35), 0.22)
        }
        let hand = t / 60 * 2 * Double.pi * 6 - Double.pi / 2
        d.line(48, 6, 49.0, 4.2, Color.black, 0.5)
        d.line(48, 6, 48 + cos(hand) * 3.2, 6 + sin(hand) * 3.2, Color(red: 0.8, green: 0.2, blue: 0.2), 0.32)
        d.disc(48, 6, 0.45, Color.black)
        // The window, the tree outside moving in the wind.
        let late = n.unit()
        let frame = ReelRGB(0.42, 0.30, 0.18)
        let skyTop = ReelRGB(0.50, 0.76, 0.96).mixed(ReelRGB(0.98, 0.78, 0.50), late), skyLow = ReelRGB(0.82, 0.93, 1.0).mixed(ReelRGB(1.0, 0.90, 0.70), late)
        let g = d.clipped(102, 10, 48, 36)
        g.fade(102, 10, 48, 36, skyTop, skyLow)
        let bark = ReelRGB(0.36, 0.26, 0.18)
        g.line(105, 47, 111, 31, bark, 1.6); g.line(111, 31, 121, 21, bark, 1.0); g.line(111, 31, 108, 17, bark, 0.9); g.line(116, 26, 128, 26, bark, 0.7)
        let leaves = 14 + n.int(10)
        for i in 0..<leaves {
            let lx = 104 + n.range(0, 30), ly = 12 + n.range(0, 22), sway = sin(t * 1.6 + Double(i)) * 1.3
            let green = ReelRGB(0.20, 0.52, 0.26).mixed(ReelRGB(0.42, 0.68, 0.24), n.unit())
            g.oval(lx + 2.5 + sway, ly + 1.5 + cos(t * 1.3 + Double(i)) * 0.4, 3.7, 2.7, green)
            g.oval(lx + 1.7 + sway, ly + 0.8, 1.7, 1.0, green.mixed(ReelRGB(1, 1, 0.7), 0.4).color.opacity(0.8))
        }
        d.box(99.4, 7.4, 53.2, 2.6, frame, 0.5); d.box(99.4, 46, 53.2, 2.6, frame, 0.5)
        d.box(99.4, 7.4, 2.6, 41.2, frame, 0.5); d.box(150, 7.4, 2.6, 41.2, frame, 0.5)
        d.box(125, 10, 1.6, 36, frame); d.box(102, 27, 48, 1.4, frame)
        d.box(97.6, 48.2, 56.8, 1.7, frame.scaled(1.2), 0.6)
        // The curtain at its side, breathing.
        let cloth = ReelRGB(0.92, 0.80, 0.52)
        var drape: [(Double, Double)] = [(160, 7)]
        for step in 0...20 {
            let y = Double(step) * 2
            drape.append((146 + sin(t * 1.2 + y / 6) * 2 - y / 40, 8 + y))
        }
        drape.append((160, 49.5))
        d.shape(drape, cloth)
        for fold in 0..<3 {
            var crease: [(Double, Double)] = []
            for step in 0...10 {
                let y = Double(step) * 4
                crease.append((151 + Double(fold) * 3 + sin(t * 1.2 + y / 6 + Double(fold)) * 1.1, 8 + y))
            }
            d.path(crease, cloth.scaled(0.74).color.opacity(0.55), 0.4)
        }
        d.box(143, 5.6, 17, 1.5, ReelRGB(0.36, 0.26, 0.18), 0.5)
        // The light the window throws across the room.
        d.shape([(96, 48), (140, 48), (96.8, 96), (52.8, 96)], Color(red: 1, green: 0.95, blue: 0.72).opacity(0.20))
        d.shape([(117, 48), (119, 48), (75.8, 96), (73.8, 96)], floor.scaled(0.6).color.opacity(0.10))
        // The desks, two rows of them.
        let wood = ReelRGB(0.72, 0.52, 0.30), leg = ReelRGB(0.30, 0.30, 0.34)
        for row in 0..<2 {
            let y = 62 + Double(row) * 16, size = 1 + Double(row) * 0.35
            for col in 0..<4 {
                let x = 8 + Double(col) * 38 * (1 + Double(row) * 0.06) - Double(row) * 6
                let w = 24 * size
                d.box(x + 1.2 * size, y + 3 * size, 0.9 * size, 9 * size, leg); d.box(x + w - 2.1 * size, y + 3 * size, 0.9 * size, 9 * size, leg)
                d.box(x + 1.2 * size, y + 9.4 * size, w - 2.4 * size, 0.7 * size, leg)
                d.box(x + 0.7 * size, y + 2.2 * size, w - 1.4 * size, 2.2 * size, wood.scaled(0.72), 0.5 * size)
                d.box(x, y, w, 3 * size, wood, 0.8 * size)
                d.box(x + 1.0 * size, y + 0.5 * size, w - 2.0 * size, 0.4 * size, Color.white.opacity(0.14), 0.2 * size)
                if ReelSheet.noise(col + row * 5, Int(warm * 100)) > 0.45 {
                    d.box(x + 5 * size, y - 1.5 * size, 6 * size, 1.9 * size, Color(red: 0.95, green: 0.95, blue: 0.98), 0.3)
                    d.line(x + 8 * size, y - 1.3 * size, x + 8 * size, y + 0.1 * size, Color(white: 0.72), 0.2)
                }
                if ReelSheet.noise(col + row * 9, Int(late * 100)) > 0.6 {
                    d.box(x + 15 * size, y - 1.0 * size, 5.4 * size, 1.3 * size, Color(red: 0.90, green: 0.30, blue: 0.28), 0.6 * size)
                }
            }
        }
        // Chalk dust in the light.
        let motes = 10 + n.int(10)
        for i in 0..<motes {
            let mx = 56 + n.range(0, 70), my = 50 + n.range(0, 40), phase = n.range(0, 6.28)
            let x = mx + sin(t * 0.4 + phase) * 3, y = my + cos(t * 0.3 + phase) * 2 - t * 0.2
            let a = 0.45 + 0.4 * sin(t * 2 + phase + Double(i))
            if a > 0.08 { d.disc(x, y, 0.36, Color.white.opacity(a)) }
        }
        // Now and then a paper plane.
        if n.unit() > 0.4 {
            let u = (t - 5) / 5
            if u > 0 && u < 1 {
                let x = 165 - u * 190, y = 40 - sin(u * Double.pi) * 16 + u * 10
                d.shape([(x, y), (x + 7.4, y - 1.4), (x + 5.4, y + 0.5), (x + 6.6, y + 2.2)], Color.white)
                d.shape([(x, y), (x + 5.4, y + 0.5), (x + 4.7, y + 1.8)], Color(white: 0.80))
            }
        }
    }

    // 夏夜: the fan turning its head, the television on, the window open.
    private func summerNight(_ d: ReelSheet, _ n: inout ReelRandom) {
        let room = ReelRGB(0.08, 0.10, 0.20)
        d.box(0, 0, 160, 70.2, room)
        d.box(0, 70, 160, 26, ReelRGB(0.16, 0.13, 0.12))
        d.box(0, 70, 160, 0.7, ReelRGB(0.25, 0.21, 0.19))
        // The mat on the floor.
        d.box(29, 75.4, 102, 19.4, ReelRGB(0.36, 0.31, 0.18), 1.0)
        for i in 0..<20 { d.box(30 + Double(i) * 5, 76.2, 4.5, 17.8, i % 2 == 0 ? ReelRGB(0.50, 0.46, 0.28) : ReelRGB(0.45, 0.41, 0.25), 0.4) }
        // The window: the moon, the stars, the fireflies.
        let frame = ReelRGB(0.22, 0.20, 0.22)
        let night = ReelRGB(0.05, 0.08, 0.22)
        let g = d.clipped(10, 10, 46, 34)
        g.fade(10, 10, 46, 34, ReelRGB(0.04, 0.06, 0.18), ReelRGB(0.10, 0.16, 0.34))
        // (In one pane or the other, never behind the bar between them.)
        let m = n.range(0, 12), moonX = m < 7 ? 19 + m : 36 + m, phase = n.int(3)
        let moon = Color(red: 1.0, green: 0.96, blue: 0.80)
        g.glow(moonX, 20, 14, moon.opacity(0.30))
        g.disc(moonX, 20, 5, moon)
        if phase == 0 {
            g.disc(moonX - 1.6, 18.6, 1.1, Color(red: 0.86, green: 0.80, blue: 0.62).opacity(0.5)); g.disc(moonX + 1.5, 21.4, 0.8, Color(red: 0.86, green: 0.80, blue: 0.62).opacity(0.5))
        }
        if phase == 1 { g.disc(moonX + 3, 19, 4.6, night) }
        if phase == 2 { g.disc(moonX - 4, 20, 5, night) }
        let stars = 8 + n.int(10)
        for i in 0..<stars {
            let sx = 11 + n.range(0, 44), sy = 11 + n.range(0, 26)
            g.disc(sx, sy, 0.3, Color.white.opacity(0.55 + 0.4 * sin(t * 1.7 + Double(i) * 2.1)))
        }
        let flies = 3 + n.int(5)
        let firefly = Color(red: 0.80, green: 1.0, blue: 0.40)
        for i in 0..<flies {
            let fx = 14 + n.range(0, 38), fy = 28 + n.range(0, 12), p = n.range(0, 6.28)
            let light = 0.5 + 0.5 * sin(t * 2.2 + p)
            let x = fx + sin(t * 0.7 + p) * 4, y = fy + cos(t * 0.9 + p + Double(i)) * 3
            g.glow(x, y, 2.4, firefly.opacity(0.5 * light))
            g.disc(x, y, 0.38, firefly.opacity(0.25 + 0.75 * light))
        }
        d.box(8, 8, 50, 2, frame); d.box(8, 44, 50, 2, frame); d.box(8, 8, 2, 38, frame); d.box(56, 8, 2, 38, frame)
        d.box(32, 10, 2, 34, frame); d.box(10, 26, 46, 2, frame)
        d.box(6.6, 46, 52.8, 1.7, frame.scaled(1.3), 0.6)
        // The television on its cabinet.
        let show = n.int(3)
        let cabinet = ReelRGB(0.34, 0.22, 0.14)
        d.box(96, 60, 52, 12, cabinet, 0.8)
        d.box(98, 62, 23.2, 8, cabinet.scaled(0.82), 0.5); d.box(122.8, 62, 23.2, 8, cabinet.scaled(0.82), 0.5)
        d.disc(119.4, 66, 0.5, cabinet.scaled(1.6)); d.disc(124.6, 66, 0.5, cabinet.scaled(1.6))
        d.box(100, 72, 3, 4, ReelRGB(0.24, 0.16, 0.10)); d.box(141, 72, 3, 4, ReelRGB(0.24, 0.16, 0.10))
        d.line(112, 28.6, 106, 18, Color(white: 0.6), 0.35); d.line(124, 28.6, 132, 17, Color(white: 0.6), 0.35)
        d.disc(106, 18, 0.5, Color(white: 0.7)); d.disc(132, 17, 0.5, Color(white: 0.7))
        d.box(102, 28, 40, 32, ReelRGB(0.42, 0.36, 0.30), 2.2)
        d.box(103.2, 29.2, 29.6, 25.6, ReelRGB(0.02, 0.03, 0.05), 2.0)
        d.box(134.4, 32, 5.6, 2, ReelRGB(0.20, 0.18, 0.16), 0.5)
        for knob in [40.0, 47.0] {
            d.disc(137.2, knob, 2, ReelRGB(0.16, 0.14, 0.12)); d.line(137.2, knob, 138.4, knob - 1.2, Color(white: 0.5), 0.3)
        }
        for i in 0..<4 { d.box(134.6, 51.4 + Double(i) * 1.3, 5.2, 0.4, ReelRGB(0.26, 0.22, 0.18)) }
        let frame12 = Int(t * 12)
        let tube = d.clipped(104, 30, 28, 24)
        let trace = Color(red: 0.70, green: 1.0, blue: 0.75)
        if show == 0 {
            // Snow between channels.
            for y in 0..<16 { for x in 0..<19 {
                let v = ReelSheet.noise(x + frame12 * 17, y + frame12 * 5)
                tube.box(104 + Double(x) * 1.5, 30 + Double(y) * 1.5, 1.6, 1.6, Color(white: 0.25 + v * 0.7))
            } }
        } else if show == 1 {
            // A ball and two bats.
            tube.box(104, 30, 28, 24, ReelRGB(0.03, 0.10, 0.08))
            for i in 0..<6 { tube.box(117.7, 31 + Double(i) * 4, 0.5, 2, trace.opacity(0.4)) }
            let u = (t * 0.45).truncatingRemainder(dividingBy: 2), bx = u < 1 ? u : 2 - u
            let v = (t * 0.62).truncatingRemainder(dividingBy: 2), by = v < 1 ? v : 2 - v
            tube.disc(107 + bx * 22, 33 + by * 18, 0.9, trace)
            tube.box(105.2, 31 + by * 16, 1.0, 5, trace, 0.4); tube.box(129.8, 47 - by * 14, 1.0, 5, trace, 0.4)
        } else {
            // The bars the station shows late at night.
            let bars = [ReelRGB(0.9, 0.9, 0.9), ReelRGB(0.9, 0.9, 0.2), ReelRGB(0.2, 0.9, 0.9), ReelRGB(0.2, 0.85, 0.3), ReelRGB(0.9, 0.3, 0.85), ReelRGB(0.9, 0.25, 0.2), ReelRGB(0.2, 0.3, 0.9)]
            for (i, bar) in bars.enumerated() { tube.box(104 + Double(i) * 4, 30, 4.2, 24, bar.scaled(0.92 + 0.08 * sin(t * 9 + Double(i)))) }
        }
        let roll = (t * 14).truncatingRemainder(dividingBy: 30)
        tube.box(104, 30 + min(23, roll), 28, 1, Color.white.opacity(0.14))
        tube.shape([(104, 30), (113, 30), (106, 41), (104, 41)], Color.white.opacity(0.05))
        // Its light on the floor, never quite still.
        let flicker = 0.10 + 0.05 * ReelSheet.noise(frame12 / 2, 3)
        let screenLight = Color(red: 0.60, green: 0.78, blue: 1.0)
        for band in 0..<12 {
            let y = 72 + Double(band) * 2
            let near = y - 72, far = y - 70
            d.shape([(84 - near, y), (144 + near * 0.4, y), (144 + far * 0.4, y + 2), (84 - far, y + 2)], screenLight.opacity(flicker * (1 - Double(band) / 13)))
        }
        // The fan, turning its head from side to side.
        let turn = sin(t * 0.5) * 5
        let steel = ReelRGB(0.50, 0.56, 0.62)
        d.oval(71, 79.2, 7.6, 1.6, steel); d.box(70.2, 52, 1.6, 27, steel); d.box(69.2, 61, 3.6, 2.2, steel.scaled(0.84), 0.6)
        let cx = 71 + turn, cy = 46.0
        d.disc(cx, cy, 10.4, ReelRGB(0.30, 0.36, 0.44).color.opacity(0.95))
        d.disc(cx, cy, 9.4, ReelRGB(0.12, 0.16, 0.26))
        let bladeTint = Color(red: 0.62, green: 0.84, blue: 0.92)
        for blade in 0..<3 {
            let a = t * 9 + Double(blade) * 2 * Double.pi / 3
            leaf(d, cx, cy, a, 8.6, 4.4, bladeTint.opacity(0.60))
            leaf(d, cx, cy, a - 0.45, 8.2, 3.8, bladeTint.opacity(0.22))
        }
        for wire in 0..<12 {
            let a = Double(wire) * Double.pi / 6
            d.line(cx + cos(a) * 1.8, cy + sin(a) * 1.8, cx + cos(a) * 9.6, cy + sin(a) * 9.6, Color(white: 0.85).opacity(0.20), 0.2)
        }
        d.circle(cx, cy, 5.6, Color(white: 0.85).opacity(0.20), 0.2)
        d.disc(cx, cy, 1.7, Color(white: 0.85)); d.disc(cx, cy, 0.6, Color(white: 0.6))
        // (Two ribbons tied to its cage, out on the wind it makes.)
        let tints = [Color(red: 0.95, green: 0.36, blue: 0.32), Color(red: 0.98, green: 0.80, blue: 0.30)]
        for ribbon in 0..<2 {
            let ry = cy - 2 + Double(ribbon) * 4
            var streamer: [(Double, Double)] = []
            for i in 0..<7 {
                let along = Double(i)
                streamer.append((cx + 9.8 + along * 1.3, ry + sin(t * 9 + along * 0.9 + Double(ribbon)) * 0.25 * along))
            }
            d.path(streamer, tints[ribbon].opacity(0.9), 0.4)
        }
        // A slice of watermelon, or the coil that keeps the mosquitoes off.
        if n.unit() > 0.5 {
            d.oval(47, 86.0, 8.6, 1.6, Color(white: 0.92))
            var rind: [(Double, Double)] = [], pith: [(Double, Double)] = [], flesh: [(Double, Double)] = []
            for i in 0...12 {
                let a = Double(i) * Double.pi / 12
                let x = cos(a) * 6.0, y = sin(a) * 5.4
                rind.append((47 + x, 80.2 + y)); pith.append((47 + x * 0.86, 80.2 + y * 0.84)); flesh.append((47 + x * 0.76, 80.2 + y * 0.72))
            }
            d.shape(rind, ReelRGB(0.20, 0.56, 0.28))
            d.shape(pith, Color(red: 0.96, green: 0.95, blue: 0.86))
            d.shape(flesh, ReelRGB(0.92, 0.26, 0.30))
            let pips: [(Double, Double)] = [(44.4, 81.6), (47.2, 82.6), (49.8, 81.5)]
            for (sx, sy) in pips { d.oval(sx, sy, 0.3, 0.45, Color.black) }
        } else {
            d.oval(44.5, 85.6, 6.6, 1.5, Color(white: 0.86))
            var turns: [(Double, Double)] = []
            for i in 0..<34 {
                let a = Double(i) * 0.4, out = 0.5 + Double(i) * 0.13
                turns.append((44.5 + cos(a) * out, 85.4 + sin(a) * out * 0.24))
            }
            d.path(turns, ReelRGB(0.16, 0.36, 0.20), 0.45)
            let ex = turns[33].0, ey = turns[33].1
            d.glow(ex, ey, 1.6, Color(red: 1, green: 0.5, blue: 0.2).opacity(0.7)); d.disc(ex, ey, 0.4, Color(red: 1, green: 0.6, blue: 0.25))
            for i in 0..<16 {
                let u = Double(i) / 16, rise = (t * 0.25 + u).truncatingRemainder(dividingBy: 1)
                d.disc(ex + sin(rise * 9 + t) * 2.5 * rise, ey - 1 - rise * 26, 0.4 + rise * 0.8, Color.white.opacity(0.26 * (1 - rise)))
            }
        }
    }

    // 雨天窗台: rain on the glass, the town behind it, something on the sill.
    private func rainyWindow(_ d: ReelSheet, _ n: inout ReelRandom) {
        let dusk = n.unit()
        let top = ReelRGB(0.30, 0.36, 0.46).mixed(ReelRGB(0.16, 0.18, 0.30), dusk), low = ReelRGB(0.56, 0.62, 0.68).mixed(ReelRGB(0.34, 0.34, 0.46), dusk)
        d.sky(top, low, bottom: 96)
        // Roofs across the way, their lights soft in the rain; fainter ones behind.
        let town = n.int(1000)
        var x = -3.0
        var i = 0
        let far = top.mixed(low, 0.5).scaled(0.82)
        while x < 160 {
            let w = 9 + Double(Int(ReelSheet.noise(town + 21, i) * 13)), h = 34 + Double(Int(ReelSheet.noise(town + 23, i) * 24))
            d.box(x, 82 - h, w, h, far)
            x += w + 0.6; i += 1
        }
        x = 0
        i = 0
        let roof = top.scaled(0.55)
        let lamp = Color(red: 1.0, green: 0.86, blue: 0.52)
        while x < 160 {
            let w = 12 + Double(Int(ReelSheet.noise(town, i) * 16)), h = 16 + Double(Int(ReelSheet.noise(town + 5, i) * 30))
            d.box(x, 78 - h, w, h + 4, roof)
            if ReelSheet.noise(town + 13, i) > 0.5 { d.box(x + 1.5, 78 - h - 1.6, w - 3, 1.8, roof) }
            if ReelSheet.noise(town + 9, i) > 0.35 {
                let wx = x + 2 + Double(Int(ReelSheet.noise(town + 2, i) * (w - 6))), wy = 78 - h + 4 + Double(Int(ReelSheet.noise(town + 4, i) * (h - 10)))
                d.glow(wx + 1.5, wy + 1.5, 6, Color(red: 1.0, green: 0.82, blue: 0.46).opacity(0.30))
                d.box(wx, wy, 3, 3, lamp.opacity(0.92), 0.5)
                d.line(wx + 1.5, wy + 0.2, wx + 1.5, wy + 2.8, roof.color.opacity(0.7), 0.22)
            }
            x += w + 1; i += 1
        }
        // The rain.
        let heavy = 50 + n.int(50), slant = n.range(0.15, 0.5)
        let wet = Color(red: 0.82, green: 0.90, blue: 1.0)
        for k in 0..<heavy {
            let rx = n.range(0, 190), speed = n.range(70, 120), start = n.range(0, 96)
            let y = (start + t * speed).truncatingRemainder(dividingBy: 104) - 6
            d.line(rx - y * slant, y, rx - (y + 4.5) * slant, y + 4.5, wet.opacity(k % 3 == 0 ? 0.6 : 0.32), 0.28)
        }
        // Drops finding their way down the glass.
        let drops = 6 + n.int(6)
        for _ in 0..<drops {
            let dx = n.range(6, 154), speed = n.range(3, 9), start = n.range(0, 80)
            let y = (start + t * speed).truncatingRemainder(dividingBy: 84)
            let x = dx + sin(y / 5) * 1.5
            d.path([(dx + sin((y - 7) / 5) * 1.5, y - 7), (dx + sin((y - 3.5) / 5) * 1.5, y - 3.5), (x, y)], Color.white.opacity(0.16), 0.5)
            d.oval(x, y + 0.5, 0.75, 1.1, Color.white.opacity(0.55)); d.disc(x - 0.2, y + 0.2, 0.25, Color.white.opacity(0.9))
        }
        // Lightning, far off, now and then.
        let strike = (t + n.range(0, 6)).truncatingRemainder(dividingBy: 9)
        if strike < 0.12 || (strike > 0.25 && strike < 0.32) { d.box(0, 0, 160, 96, Color.white.opacity(0.35)) }
        // The window's frame and its sill.
        let frame = ReelRGB(0.36, 0.26, 0.18)
        d.box(0, 0, 160, 4, frame); d.box(0, 0, 4, 96, frame); d.box(156, 0, 4, 96, frame); d.box(78, 0, 4, 84, frame); d.box(0, 40, 160, 2, frame)
        d.box(4, 4, 74, 0.5, frame.scaled(0.7)); d.box(82, 4, 74, 0.5, frame.scaled(0.7)); d.box(4, 42, 74, 0.4, frame.scaled(0.7)); d.box(82, 42, 74, 0.4, frame.scaled(0.7))
        d.box(0, 82, 160, 14, ReelRGB(0.50, 0.38, 0.26)); d.box(0, 82, 160, 1.6, ReelRGB(0.64, 0.50, 0.36))
        for grain in 0..<3 { d.box(0, 86.4 + Double(grain) * 3.2, 160, 0.3, ReelRGB(0.45, 0.34, 0.23)) }
        // A plant in its pot.
        d.oval(28, 82.4, 9, 1.0, Color.black.opacity(0.18))
        d.shape([(21.6, 72.6), (34.4, 72.6), (33, 82), (23, 82)], ReelRGB(0.72, 0.38, 0.24))
        d.box(20, 70, 16, 3, ReelRGB(0.80, 0.44, 0.28), 0.8)
        for stem in 0..<5 {
            let a = -2.6 + Double(stem) * 0.5 + sin(t * 0.8 + Double(stem)) * 0.05
            let ca = cos(a), sa = sin(a)
            d.path([(28, 70.6), (28 + ca * 5, 70 + sa * 8.6), (28 + ca * 12, 70 + sa * 14)], ReelRGB(0.22, 0.56, 0.30), 0.6)
            let along = atan2(sa * 5.8, ca * 6.5)
            leaf(d, 28 + ca * 5.5, 70 + sa * 8.2, along, 8.2, 3.4, ReelRGB(0.30, 0.66, 0.34).color)
            leaf(d, 28 + ca * 5.5, 70 + sa * 8.2, along, 8.2, 1.2, ReelRGB(0.52, 0.80, 0.46).color.opacity(0.7))
        }
        // What waits on the sill with you.
        let friend = n.int(3)
        if friend == 0 {
            // A cat, its back to the room, its tail keeping time.
            let ink = ReelRGB(0.62, 0.63, 0.68)
            let flick = sin(t * 1.4) * 4
            d.oval(120, 82.2, 10, 0.9, Color.black.opacity(0.18))
            d.path([(113.5, 80.6), (108.5, 81.0), (104.6, 79.4 - flick * 0.4), (102.6, 75.4 - flick)], ink, 1.5)
            d.oval(120, 75.6, 7.4, 6.6, ink)
            d.oval(120, 80.6, 8.6, 1.7, ink)
            d.disc(125.4, 66.4, 4.6, ink)
            d.shape([(121.4, 65.0), (122.2, 59.8), (125.2, 62.6)], ink); d.shape([(126.0, 62.4), (129.2, 59.8), (129.9, 65.0)], ink)
            for stripe in 0..<3 {
                let over = Double(stripe)
                d.line(116.2 + over * 2.4, 71.0 - over * 0.5, 115.4 + over * 2.4, 74.0 - over * 0.5, ink.scaled(0.78).color.opacity(0.8), 0.5)
            }
        } else if friend == 1 {
            // A paper boat, ready for the puddles.
            let paper = Color(red: 0.96, green: 0.96, blue: 0.92), shade = Color(white: 0.82)
            d.oval(119.5, 82.2, 13, 0.9, Color.black.opacity(0.16))
            d.shape([(119.5, 68.4), (125.5, 77.6), (113.5, 77.6)], paper)
            d.shape([(119.5, 68.4), (119.5, 77.6), (113.5, 77.6)], shade)
            d.shape([(104.6, 75.6), (113.5, 77.6), (125.5, 77.6), (134.4, 75.6), (129.2, 81.9), (109.8, 81.9)], paper)
            d.shape([(108.4, 80.2), (130.6, 80.2), (129.2, 81.9), (109.8, 81.9)], shade)
        } else {
            // Rain boots, and a small radio.
            let yellow = ReelRGB(0.95, 0.78, 0.16)
            for boot in 0..<2 {
                let bx = 108 + Double(boot) * 12, by = 70 + Double(boot) * 2
                d.box(bx, by, 6, 82 - by, yellow, 1.2)
                d.box(bx, 78.6, 9.4, 3.4, yellow, 1.6)
                d.box(bx, by, 6, 1.3, yellow.scaled(0.8), 0.5)
                d.box(bx + 0.5, 81.2, 8.9, 0.8, yellow.scaled(0.62), 0.3)
                d.box(bx + 1.0, by + 2.4, 0.7, 5.0, Color.white.opacity(0.35), 0.35)
            }
            d.box(134, 72, 16, 10, ReelRGB(0.62, 0.20, 0.18), 1.4)
            d.disc(139, 77, 2.7, Color(white: 0.2))
            d.circle(139, 77, 1.6, Color(white: 0.36), 0.25); d.disc(139, 77, 0.5, Color(white: 0.36))
            let needle = 145.2 + sin(t * 0.3) * 1.2
            d.box(143.6, 73.8, 5.0, 2.0, Color(white: 0.86), 0.4); d.line(needle, 74.0, needle, 75.6, Color(red: 0.8, green: 0.2, blue: 0.2), 0.25)
            d.line(148, 72, 152, 62, Color(white: 0.75), 0.35); d.disc(152, 62, 0.5, Color(white: 0.8))
            if Int(t * 2) % 2 == 0 { d.disc(146.2, 79.2, 0.6, Color(red: 1, green: 0.8, blue: 0.3)) }
        }
    }

    // 操场: the swing, the kite, the school behind.
    private func playground(_ d: ReelSheet, _ n: inout ReelRandom) {
        let mood = n.int(3)
        let top = [ReelRGB(0.26, 0.40, 0.72), ReelRGB(0.36, 0.30, 0.60), ReelRGB(0.20, 0.46, 0.66)][mood]
        let low = [ReelRGB(1.0, 0.80, 0.62), ReelRGB(1.0, 0.66, 0.60), ReelRGB(0.98, 0.90, 0.66)][mood]
        d.sky(top, low, bottom: 70)
        let clouds = 1 + n.int(3)
        for _ in 0..<clouds {
            let x = (n.range(0, 200) + t * n.range(0.8, 2)).truncatingRemainder(dividingBy: 200) - 30, y = n.range(8, 30), w = n.range(16, 30)
            let body = top.mixed(low, 0.25 + y / 70).mixed(ReelRGB(1, 1, 1), 0.72)
            cloud(d, x, y, w, body, ReelRGB(1, 1, 1))
        }
        // Trees beyond the fence.
        let leafy = ReelRGB(0.16, 0.36, 0.26).mixed(top, 0.30)
        let trees: [(Double, Double, Double)] = [(78, 60, 6), (152, 54, 9), (93, 63, 4.6)]
        for (index, tree) in trees.enumerated() {
            let tx = tree.0, ty = tree.1, r = tree.2
            let sway = sin(t * 0.9 + Double(index)) * 0.4
            d.box(tx - 0.6, ty, 1.2, 70 - ty, leafy.scaled(0.7))
            d.disc(tx + sway, ty, r, leafy); d.disc(tx - r * 0.5 + sway, ty + r * 0.35, r * 0.7, leafy); d.disc(tx + r * 0.55 + sway, ty + r * 0.3, r * 0.66, leafy)
            d.disc(tx - r * 0.25 + sway, ty - r * 0.3, r * 0.45, leafy.mixed(low, 0.16))
        }
        // The school, and its flag.
        let school = top.mixed(ReelRGB(0.10, 0.08, 0.16), 0.62)
        d.box(6, 36, 64, 34.3, school); d.box(30, 28, 16, 8.2, school)
        d.shape([(28.6, 28.2), (38, 23.6), (47.4, 28.2)], school)
        d.box(4.8, 35.2, 66.4, 1.5, school.mixed(low, 0.14))
        d.disc(38, 31.6, 2.1, Color(red: 1.0, green: 0.95, blue: 0.80).opacity(0.92)); d.line(38, 31.6, 38, 30.2, school, 0.3); d.line(38, 31.6, 39.0, 32.0, school, 0.3)
        let glass = school.mixed(ReelRGB(0.60, 0.66, 0.86), 0.2)
        let lit = Color(red: 1.0, green: 0.86, blue: 0.5)
        for row in 0..<4 { for col in 0..<9 {
            let wx = 10 + Double(col) * 7, wy = 40 + Double(row) * 7
            if ReelSheet.noise(row + mood * 3, col) > 0.72 {
                d.box(wx - 0.5, wy - 0.5, 4, 4.6, lit.opacity(0.16), 1.0)
                d.box(wx, wy, 3, 3.6, lit, 0.4)
            } else {
                d.box(wx, wy, 3, 3.6, glass, 0.4)
            }
        } }
        d.box(35, 61, 6, 9.2, school.scaled(0.7), 0.6)
        d.box(84, 22, 0.8, 48, Color(white: 0.85)); d.disc(84.4, 21.6, 0.8, Color(white: 0.92))
        var flag: [(Double, Double)] = []
        for i in 0...6 {
            let along = Double(i)
            flag.append((84.8 + along * 1.55, 22.6 + sin(t * 3 + along * 0.7) * 0.7 * along / 6))
        }
        for i in 0...6 {
            let along = Double(6 - i)
            flag.append((84.8 + along * 1.55, 28.4 + sin(t * 3 + along * 0.7 + 0.4) * 0.7 * along / 6))
        }
        d.shape(flag, ReelRGB(0.90, 0.24, 0.22))
        // The ground and its track.
        let grass = ReelRGB(0.30, 0.56, 0.34).mixed(top, 0.25)
        d.box(0, 69.8, 160, 26.2, grass)
        d.fade(0, 69.8, 160, 5.2, grass.scaled(0.84), grass)
        d.box(0, 82, 160, 8, ReelRGB(0.76, 0.40, 0.30).mixed(top, 0.2))
        d.box(0, 84.6, 160, 0.5, Color.white.opacity(0.6)); d.box(0, 87.3, 160, 0.5, Color.white.opacity(0.6))
        // The swing, still going.
        let ink = ReelRGB(0.20, 0.22, 0.30)
        let legs: [(Double, Double)] = [(100, 108), (116, 108), (130, 138), (146, 138)]
        for (foot, head) in legs { d.line(foot, 80, head, 50, ink, 1.0) }
        d.line(107.4, 50, 138.6, 50, ink, 1.2)
        let swing = sin(t * 1.9) * 0.25
        let sx = 123 + sin(swing) * 20, sy = 50 + cos(swing) * 20
        d.oval(123 + sin(swing) * 8, 80.4, 4.5, 0.6, Color.black.opacity(0.16))
        d.line(121, 50, sx - 2, sy, Color(white: 0.8), 0.3); d.line(125, 50, sx + 2, sy, Color(white: 0.8), 0.3)
        d.box(sx - 3.2, sy, 6.4, 1.1, ReelRGB(0.62, 0.40, 0.22), 0.4)
        let someone = n.unit() > 0.35, riderGirl = n.int(2) == 1
        if someone {
            // Someone is on it, a hand on the near rope.
            rider(d, sx, sy, kick: cos(t * 1.9) * 0.35, grip: (125 + (sx + 2 - 125) * 0.60, 50 + (sy - 50) * 0.60), k: 1.05, girl: riderGirl)
        }
        // The kite, and whoever holds its string.
        let kites = [ReelRGB(0.95, 0.30, 0.28), ReelRGB(1.0, 0.80, 0.20), ReelRGB(0.30, 0.70, 0.95), ReelRGB(0.60, 0.40, 0.90)]
        let kiteInk = kites[n.int(kites.count)]
        let kite = kiteInk.color
        // (High over the swing, ahead of whoever holds it: the string runs slanting.)
        let kx = 104 + n.range(0, 30) + sin(t * 0.6) * 5, ky = 10 + n.range(0, 8) + cos(t * 0.9) * 3
        d.shape([(kx, ky - 5.2), (kx + 3.7, ky - 0.6), (kx, ky + 3.8), (kx - 3.7, ky - 0.6)], kite)
        d.shape([(kx, ky - 5.2), (kx + 3.7, ky - 0.6), (kx, ky + 3.8)], Color.white.opacity(0.20))
        d.line(kx, ky - 5.0, kx, ky + 3.6, Color.white.opacity(0.5), 0.22); d.line(kx - 3.5, ky - 0.6, kx + 3.5, ky - 0.6, Color.white.opacity(0.4), 0.22)
        var tail: [(Double, Double)] = []
        for i in 0..<8 {
            let down = Double(i)
            tail.append((kx + sin(t * 3 + down * 0.8) * (0.3 + down * 0.28), ky + 3.8 + down * 1.6))
        }
        d.path(tail, kite.opacity(0.9), 0.3)
        for i in [2, 4, 6] { d.disc(tail[i].0, tail[i].1, 0.65, i == 4 ? Color.white : kite) }
        let hx = 63.6, hy = 61.0
        var string: [(Double, Double)] = []
        for i in 0...24 {
            let u = Double(i) / 24
            string.append((kx + (hx - kx) * u, ky + 3.8 + (hy - ky - 3.8) * u + sin(u * Double.pi) * 6))
        }
        d.path(string, Color.white.opacity(0.6), 0.2)
        child(d, x: 58, feet: 82.6, bag: kiteInk, walking: false, hand: (hx, hy), k: 1.3, girl: n.int(2) == 1)
        // Dandelion seeds on the wind.
        let seeds = 5 + n.int(8)
        for _ in 0..<seeds {
            let x = (n.range(0, 170) + t * n.range(3, 7)).truncatingRemainder(dividingBy: 170) - 5, y = n.range(40, 78), p = n.range(0, 6.28)
            let yy = y + sin(t + p) * 3
            d.line(x, yy, x - 0.5, yy + 1.2, Color.white.opacity(0.5), 0.15)
            d.disc(x, yy, 0.42, Color.white.opacity(0.8))
        }
    }
}

/// The pencil's own small numbers: the same for the same page, so a line
/// drawn on a page stays as it was drawn there.
private struct FlipRandom {
    private var state: UInt32
    init(_ seed: Int) { state = UInt32(truncatingIfNeeded: seed &* 2_654_435_761 &+ 12_345) }
    mutating func unit() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296.0
    }
    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
    /// -a ... a.
    mutating func either(_ a: Double) -> Double { (unit() * 2 - 1) * a }
}

/// Lines as a hand draws them: not quite straight, and not quite the same
/// on the next page.
private struct FlipPencil {
    var sheet: ReelSheet
    var page: Int
    /// Every page lies a hair differently under the thumb.
    var dx: Double, dy: Double
    private var drawn = 0
    static let lead = ReelRGB(0.23, 0.23, 0.27)

    init(sheet: ReelSheet, page: Int, dx: Double, dy: Double) {
        self.sheet = sheet
        self.page = page
        self.dx = dx
        self.dy = dy
    }
    mutating func line(_ points: [(Double, Double)], _ width: Double = 0.55, wobble: Double = 0.16, alpha: Double = 0.86) {
        drawn += 1
        var hand = FlipRandom(page &* 977 &+ drawn &* 131)
        var route: [(Double, Double)] = []
        for p in points {
            let x = p.0 + dx + hand.either(wobble), y = p.1 + dy + hand.either(wobble)
            route.append((x, y))
        }
        let weight = width * hand.range(0.85, 1.12)
        if route.count >= 3 {
            sheet.curve(route, Self.lead.color.opacity(alpha), weight)
            // Gone over once more, lighter: pencil is never one clean stroke.
            var again: [(Double, Double)] = []
            for p in route {
                let x = p.0 + hand.either(0.10), y = p.1 + hand.either(0.10)
                again.append((x, y))
            }
            sheet.curve(again, Self.lead.color.opacity(alpha * 0.35), width * 0.6)
        } else {
            sheet.path(route, Self.lead.color.opacity(alpha), weight)
        }
    }
    /// A circle as a hand closes one: a little more than once round.
    mutating func ring(_ cx: Double, _ cy: Double, _ radius: Double, _ width: Double = 0.55) {
        drawn += 1
        var hand = FlipRandom(page &* 977 &+ drawn &* 131)
        let start = hand.range(0, 2 * Double.pi)
        var route: [(Double, Double)] = []
        for i in 0..<15 {
            let angle = start + 2 * Double.pi * Double(i) / 13.0
            let reach = radius * (1 + hand.either(0.035))
            route.append((cx + dx + reach * cos(angle), cy + dy + reach * sin(angle)))
        }
        sheet.curve(route, Self.lead.color.opacity(0.86), width)
    }
    func dot(_ x: Double, _ y: Double, _ radius: Double = 0.42) {
        sheet.disc(x + dx, y + dy, radius, Self.lead.color.opacity(0.9))
    }
}

/// 铜卡带's films: the corner of a schoolbook's page, where someone has
/// drawn pencil people that move as the pages are flipped. Every page is
/// another page — its lines of type differ, its number goes up — and only
/// the drawing carries on, moving once a page.
struct FlipBookPainter {
    var game: FlipGame
    /// This cartridge's numbers for the game.
    var random: ReelRandom
    /// Seconds since the film began.
    var t: Double
    /// A gust under the page's lower outer corner: 0 lying flat … 1 lifted most (GoldFilm.windLevel's
    /// flutter); the pages riffle there.
    var wind = 0.0

    /// Pages flipped a second.
    static let pagesASecond = 12.0
    private static let paper = ReelRGB(0.965, 0.935, 0.850)
    private static let printed = ReelRGB(0.42, 0.40, 0.38)
    private typealias Point = (Double, Double)
    private typealias Limb = ((Double, Double), (Double, Double))

    private static func smooth(_ u: Double) -> Double {
        let k = min(1, max(0, u))
        return k * k * (3 - 2 * k)
    }
    private static func mix(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }

    func draw(_ context: GraphicsContext, size: CGSize) {
        let unit = min(size.width / ReelSheet.width, size.height / ReelSheet.height)
        guard unit > 0 else { return }
        let origin = CGPoint(x: (size.width - unit * ReelSheet.width) / 2, y: (size.height - unit * ReelSheet.height) / 2)
        var clipped = context
        clipped.clip(to: Path(CGRect(x: origin.x, y: origin.y, width: unit * ReelSheet.width, height: unit * ReelSheet.height)))
        // The film looks at the page's lower outer corner, twice as near:
        // (78, 48) to (158, 96) of the page fills the sheet.
        let near = ReelSheet(context: clipped, unit: unit * 2, origin: CGPoint(x: origin.x - 78 * unit * 2, y: origin.y - 48 * unit * 2))
        var numbers = random
        let book = numbers.int(9000)
        let girl = numbers.int(2) == 0
        let turned = Int(t * Self.pagesASecond)
        let within = t * Self.pagesASecond - Double(turned)
        // The drawing moves once a page.
        let shown = Double(turned) / Self.pagesASecond
        var lie = FlipRandom(turned &* 613 &+ book)
        let dx = lie.either(0.22), dy = lie.either(0.22)
        page(near, number: 37 + 2 * turned, book: book, shade: 1 - Self.smooth(within / 0.45))
        var pencil = FlipPencil(sheet: near, page: turned, dx: dx, dy: dy)
        let ground = 90.5
        switch game {
        case .jumpRope:
            jumpRope(&pencil, cx: 114, ground: ground, t: shown, girl: girl)
            // A sun someone drew, and a flower beside the jumper.
            pencil.ring(88, 68, 2.4, 0.42)
            for i in 0..<8 {
                let angle = Double(i) * Double.pi / 4 + 0.2
                pencil.line([(88 + 3.4 * cos(angle), 68 + 3.4 * sin(angle)), (88 + 4.9 * cos(angle), 68 + 4.9 * sin(angle))], 0.34, wobble: 0.07)
            }
            pencil.line([(141, ground + 0.4), (141.4, ground - 4), (141, ground - 7)], 0.38)
            pencil.ring(141, ground - 8.3, 1.2, 0.36)
            for i in 0..<5 {
                let angle = Double(i) * 2 * Double.pi / 5 + 0.3
                pencil.ring(141 + 2.1 * cos(angle), ground - 8.3 + 2.1 * sin(angle), 1.0, 0.32)
            }
        case .shuttlecock:
            let kicks = shuttlecock(&pencil, cx: 106, ground: ground, t: shown)
            tally(&pencil, x: 128, y: 64, count: kicks + 1)
            // A kite someone drew earlier.
            pencil.line([(86, 68), (90, 64), (94, 68), (90, 72), (86, 68)], 0.38, wobble: 0.09)
            pencil.line([(90, 72), (89.2, 76), (90.8, 79), (89.6, 82)], 0.30, wobble: 0.1)
        }
        if wind > 0.01 { riffle(near, number: 37 + 2 * turned, lift: min(1, wind)) }
        // The film comes up out of black and goes back into it.
        let whole = ReelSheet(context: clipped, unit: unit, origin: origin)
        let fade = max(0, 1 - t / 0.8) + max(0, (t - (GoldReelPlan.seconds(.bronze) - 0.8)) / 0.8)
        if fade > 0.01 { whole.box(0, 0, ReelSheet.width, ReelSheet.height, Color.black.opacity(min(1, fade))) }
    }

    /// The wind gets under the pages' lower outer corner and blows them up: the top page's corner
    /// curls up and over a fold, showing its back, and under it the next pages lift too, each a little
    /// less than the one above and each fluttering in its own time, with the corner of the page beneath
    /// (and its number) bared where they were. (Page units: the page is 160 by 96, its corner at the
    /// bottom right; the film shows (78, 48) to (158, 96) of it.)
    private func riffle(_ d: ReelSheet, number: Int, lift: Double) {
        let width = ReelSheet.width, height = ReelSheet.height
        let corner = (width, height)
        typealias P = (Double, Double)
        // The fold for a page lifted `lev`: from the foot of the page to its outer edge.
        func fold(_ lev: Double) -> (P, P) { ((width - 50 * lev, height), (width, height - 38 * lev)) }
        // The corner turned over the fold, partly: the more it lifts, the further over it comes.
        func turned(_ p: P, _ a: P, _ b: P, _ lev: Double) -> P {
            let fx = b.0 - a.0, fy = b.1 - a.1, length = max(0.001, (fx * fx + fy * fy).squareRoot())
            let ux = fx / length, uy = fy / length
            let along = (p.0 - a.0) * ux + (p.1 - a.1) * uy
            let foot = (a.0 + ux * along, a.1 + uy * along)
            let over = 0.58 + 0.3 * lev   // (0.5: standing straight up; 1: laid flat over the fold)
            return (p.0 + 2 * (foot.0 - p.0) * over, p.1 + 2 * (foot.1 - p.1) * over)
        }
        // A page's free edge is not quite straight: it bows as the paper curls.
        func bowed(_ p: P, _ q: P, _ k: Double) -> [P] {
            let nx = -(q.1 - p.1), ny = q.0 - p.0
            return (0...6).map { i in
                let u = Double(i) / 6, b = 4 * u * (1 - u) * k
                return (p.0 + (q.0 - p.0) * u + nx * b, p.1 + (q.1 - p.1) * u + ny * b)
            }
        }
        // (the back of a page in the shade of its own curl by the fold, lit toward its tip)
        let back = ReelRGB(0.79, 0.75, 0.65), backLit = ReelRGB(0.985, 0.965, 0.90)
        // Four pages, the top one lifting most; each flutters a little out of step with the others.
        let parts = [0.3, 0.52, 0.76, 1.0]
        let levels = parts.enumerated().map { i, part in
            lift * part * (0.82 + 0.18 * sin(t * 2 * .pi * 3.1 + Double(i) * 1.9))
        }
        // Where each page's corner was, from the top page's down: the page beneath, a little in the
        // shadow of the one over it, with its own number at its corner.
        for (i, lev) in levels.enumerated().reversed() {
            let (a, b) = fold(lev)
            let bared = [a, b, corner]
            d.shape(bared, Self.paper)
            let under = d.clipped(to: bared)
            under.smallPrint(String(number + 2 * (4 - i)), 146.0, 90.4, 3.0, Self.printed.color.opacity(0.75))
            for k in 0..<6 {
                under.box(width - 3.2 + Double(k) * 0.55, 0, 0.16, height, ReelRGB(0.55, 0.50, 0.42).color.opacity(0.35 - Double(k) * 0.04))
            }
            under.glow((a.0 + b.0) / 2, (a.1 + b.1) / 2, 16 * lev, Color.black.opacity(0.24 * lev))
        }
        // Then the pages' turned-up corners, the deepest first (the top page's is nearest).
        for (i, lev) in levels.enumerated() where lev > 0.02 {
            let (a, b) = fold(lev)
            let tip = turned(corner, a, b, lev)
            let edge: [P] = bowed(a, tip, 0.06 + 0.03 * Double(i)) + bowed(tip, b, -0.05).dropFirst()
            // its shadow on the page below, then the page's back, lit toward its tip
            d.shape([a, (tip.0 + 1.6 * lev, tip.1 + 2.6 * lev), b], Color.black.opacity(0.16 + 0.12 * lev))
            d.shape(edge, from: ((a.0 + b.0) / 2, (a.1 + b.1) / 2), back.color, to: tip, backLit.color)
            d.path(edge, FlipPencil.lead.color.opacity(0.6), 0.28)
        }
    }

    /// One printed page: its lines of type (grey strokes), its number, the
    /// edge of the book, the shadow of the page being turned.
    private func page(_ d: ReelSheet, number: Int, book: Int, shade: Double) {
        var press = FlipRandom(number &* 7919 &+ book)
        d.box(0, 0, ReelSheet.width, ReelSheet.height, Self.paper)
        // The paper is never even.
        for _ in 0..<5 {
            let x = press.range(0, ReelSheet.width), y = press.range(0, ReelSheet.height), reach = press.range(30, 60)
            d.glow(x, y, reach, ReelRGB(0.93, 0.89, 0.78).color.opacity(0.10))
        }
        // Type: lines of words down to the middle of the page, another page's each time.
        let left = 9.0, right = 147.0
        var y = 6.0 - press.range(0, 3)
        var lines = Int(press.range(2, 6))
        while y < 55 {
            var x = left + (lines == 0 ? 7.0 : 0.0)
            let end = right - (lines == 1 ? press.range(8, 46) : press.range(0, 2.5))
            while x < end - 3 {
                let word = press.range(2.2, 7.5)
                d.box(x, y, min(word, end - x), 1.45, Self.printed.color.opacity(0.50), 0.4)
                x += word + 1.15
            }
            y += 4.1
            lines -= 1
            if lines < 0 {
                lines = Int(press.range(2, 6))
                y += 1.2
            }
        }
        // A printed rule under the type, and now and then a small printed picture.
        d.box(left, 59.6, right - left, 0.24, Self.printed.color.opacity(0.45))
        if press.unit() < 0.3 {
            let x = press.range(96, 122)
            let frame = Self.printed.color.opacity(0.5)
            d.box(x, 8, 22, 15, Self.paper)
            d.box(x, 8, 22, 0.3, frame)
            d.box(x, 22.7, 22, 0.3, frame)
            d.box(x, 8, 0.3, 15, frame)
            d.box(x + 21.7, 8, 0.3, 15, frame)
            d.disc(x + 6, 15, 3, Self.printed.color.opacity(0.25))
            d.box(x + 11, 12, 8, 1.2, Self.printed.color.opacity(0.3))
            d.box(x + 11, 15.5, 6, 1.2, Self.printed.color.opacity(0.3))
        }
        // The page's number in the outer corner.
        d.smallPrint(String(number), 146.0, 90.4, 3.0, Self.printed.color.opacity(0.75))
        // The outer edge: the pages under this one.
        let width = ReelSheet.width, height = ReelSheet.height
        for i in 0..<6 {
            d.box(width - 3.2 + Double(i) * 0.55, 0, 0.16, height, ReelRGB(0.55, 0.50, 0.42).color.opacity(0.35 - Double(i) * 0.04))
        }
        d.fade(width - 3.4, 0, 3.4, height, ReelRGB(0.80, 0.74, 0.62), ReelRGB(0.74, 0.68, 0.56))
        for i in 0..<6 {
            d.box(width - 3.2 + Double(i) * 0.55, 0, 0.16, height, ReelRGB(0.45, 0.40, 0.33).color.opacity(0.5))
        }
        if shade > 0 { d.glow(width + 10, height * 0.55, 95, ReelRGB(0.20, 0.16, 0.10).color.opacity(0.34 * shade)) }
    }

    /// A pencil person. `face`: -1 looking left ... +1 right, 0 toward us.
    private func person(_ p: inout FlipPencil, head: Point, neck: Point, hip: Point, arms: [Limb], legs: [Limb], face: Double, look: Point) {
        let waist: Point = ((neck.0 + hip.0) / 2 + 0.15, (neck.1 + hip.1) / 2)
        p.line([neck, waist, hip], 0.62)
        for limb in legs {
            let knee = limb.0, foot = limb.1
            p.line([hip, knee, foot], 0.58)
            let toe: Double
            if abs(face) < 0.5 { toe = foot.0 + (foot.0 >= knee.0 ? 1.3 : -1.3) } else { toe = foot.0 + 1.5 * face }
            p.line([foot, (toe, foot.1 + 0.1)], 0.58, wobble: 0.08)
        }
        let shoulder: Point = (neck.0, neck.1 + 0.9)
        for limb in arms { p.line([shoulder, limb.0, limb.1], 0.55) }
        p.ring(head.0, head.1, 2.7, 0.60)
        let ex = 0.9 * face + look.0 * 0.5, ey = look.1 * 0.5
        p.dot(head.0 - 0.85 + ex, head.1 - 0.3 + ey, 0.34)
        p.dot(head.0 + 0.85 + ex, head.1 - 0.3 + ey, 0.34)
        let smile: [Point] = [(head.0 - 0.8 + ex, head.1 + 0.85 + ey), (head.0 + ex, head.1 + 1.45 + ey), (head.0 + 0.8 + ex, head.1 + 0.85 + ey)]
        p.line(smile, 0.36, wobble: 0.05)
    }

    /// Skipping, seen from in front: a little under two turns of the rope a second.
    private func jumpRope(_ p: inout FlipPencil, cx: Double, ground: Double, t: Double, girl: Bool) {
        let period = 0.56
        let phase = (t / period).truncatingRemainder(dividingBy: 1.0)
        // -0.5 ... 0.5, 0 as the rope passes under the feet.
        let u = phase < 0.5 ? phase : phase - 1.0
        let rise = u / 0.23
        let jump = 5.2 * max(0.0, 1 - rise * rise)
        let between = (abs(u) - 0.5) / 0.10
        let hop = 1.1 * max(0.0, 1 - between * between)
        let up = jump + hop
        // The knees give on landing.
        let bend = 1.5 * Self.smooth((abs(u) - 0.20) / 0.07) * Self.smooth((0.40 - abs(u)) / 0.08)
        let hip: Point = (cx, ground - 9.0 - up + bend)
        let neck: Point = (cx + 0.1, hip.1 - 7.6)
        let head: Point = (cx + 0.1, neck.1 - 3.3)
        let turn = 2 * Double.pi * phase
        var hands: [Point] = []
        var arms: [Limb] = []
        var legs: [Limb] = []
        for side in [-1.0, 1.0] {
            let elbow: Point = (cx + side * 3.3, neck.1 + 4.3)
            let hand: Point = (elbow.0 + side * 2.6 + 0.8 * cos(turn) * side, elbow.1 + 0.6 + 0.8 * sin(turn))
            arms.append((elbow, hand))
            hands.append(hand)
            let foot: Point = (cx + side * 1.3, ground - up)
            let knee: Point = (cx + side * (1.45 + 0.9 * bend), (hip.1 + foot.1) / 2 + 0.2)
            legs.append((knee, foot))
        }
        // The rope: under the feet at 0, over the head half a turn later.
        let grip = hands[0].1
        let low = (ground + 0.9) - grip
        let high = grip - (head.1 - 6.5)
        let swing = cos(turn)
        let apex = grip + (swing >= 0 ? low * swing : high * swing)
        let reach = 10.2 + 1.6 * abs(sin(turn))
        let nearY = Self.mix(grip, apex, 0.22), farY = Self.mix(grip, apex, 0.80)
        let rope: [Point] = [hands[0], (cx - reach, nearY), (cx - reach * 0.72, farY), (cx, apex), (cx + reach * 0.72, farY), (cx + reach, nearY), hands[1]]
        // Coming up behind: drawn first, and fainter.
        let behind = sin(turn) < 0
        if behind { p.line(rope, 0.42, wobble: 0.12, alpha: 0.5) }
        // The ground, and a puff of dust at the landing.
        let floor: [Point] = [(cx - 13, ground + 0.7), (cx - 4, ground + 0.5), (cx + 5, ground + 0.75), (cx + 13, ground + 0.6)]
        p.line(floor, 0.4, wobble: 0.1, alpha: 0.6)
        if abs(u) > 0.23 && abs(u) < 0.34 {
            for side in [-1.0, 1.0] {
                p.line([(cx + side * 3.2, ground - 0.3), (cx + side * 4.6, ground - 1.2)], 0.34, wobble: 0.1, alpha: 0.6)
            }
        }
        person(&p, head: head, neck: neck, hip: hip, arms: arms, legs: legs, face: 0, look: (0, up > 2 ? -0.2 : 0.1))
        if girl {
            // Two short plaits that fly up on the way down.
            let fly = max(-1.0, min(1.0, u * 6)) * (jump > 0 ? 1.0 : 0.3)
            for side in [-1.0, 1.0] {
                let plait: [Point] = [(head.0 + side * 2.4, head.1 - 0.6), (head.0 + side * 3.9, head.1 + 0.4 - 1.6 * fly), (head.0 + side * 4.4, head.1 + 1.6 - 2.6 * fly)]
                p.line(plait, 0.5)
            }
        }
        if !behind { p.line(rope, 0.46, wobble: 0.12) }
    }

    /// Keeping a shuttlecock up with the side of the foot, seen from the
    /// side. Gives how many kicks there have been.
    private func shuttlecock(_ p: inout FlipPencil, cx: Double, ground: Double, t: Double) -> Int {
        let period = 0.98
        let kicks = Int(t / period)
        let phase = (t / period).truncatingRemainder(dividingBy: 1.0)
        var each = FlipRandom(kicks &* 31 &+ 7)
        let height = 19.5 + each.either(1.8)
        let y = ground - 5.0 - height * 4 * phase * (1 - phase)
        let x = cx + 5.2 + 0.9 * sin(Double(kicks) * 2.1) * (1 - 2 * abs(phase - 0.5))
        // The kicking leg comes up to meet it, and goes down again.
        let lift = phase > 0.5 ? Self.smooth((phase - 0.80) / 0.20) : 1 - Self.smooth(phase / 0.26)
        let give = 0.9 * lift
        let hip: Point = (cx - 0.6 * lift, ground - 9.2 + give)
        let neck: Point = (hip.0 - 1.0 * lift, hip.1 - 7.5)
        let head: Point = (neck.0 - 0.2, neck.1 - 3.3)
        let standingKnee: Point = (hip.0 - 0.4 - 0.9 * give, (hip.1 + ground) / 2)
        let standingFoot: Point = (cx - 0.8, ground)
        let knee: Point = (hip.0 + Self.mix(0.6, 4.0, lift), hip.1 + Self.mix(4.5, 1.2, lift))
        let foot: Point = (hip.0 + Self.mix(1.0, 5.2, lift), Self.mix(ground, ground - 5.0, lift))
        let legs: [Limb] = [(standingKnee, standingFoot), (knee, foot)]
        // Arms out for balance, the far one up as the leg lifts.
        let farElbow: Point = (neck.0 - 3.2, neck.1 + 2.6 - 1.2 * lift)
        let farHand: Point = (neck.0 - 5.6, neck.1 + 1.0 - 2.4 * lift)
        let nearElbow: Point = (neck.0 + 2.8, neck.1 + 3.6)
        let nearHand: Point = (neck.0 + 4.8, neck.1 + 2.2 + 1.6 * lift)
        let arms: [Limb] = [(farElbow, farHand), (nearElbow, nearHand)]
        let floor: [Point] = [(cx - 12, ground + 0.7), (cx - 3, ground + 0.5), (cx + 6, ground + 0.75), (cx + 14, ground + 0.6)]
        p.line(floor, 0.4, wobble: 0.1, alpha: 0.6)
        let look: Point = (0.9, max(-1.0, min(1.0, (y - head.1) / 9.0)))
        person(&p, head: head, neck: neck, hip: hip, arms: arms, legs: legs, face: 0.7, look: look)
        // The shuttlecock: a coin for its foot, three feathers that trail behind its going.
        let falling = -(4 * height * (1 - 2 * phase))
        let tilt = 0.5 * sin(Double(kicks) * 1.3 + phase * 6.0)
        var fx = -sin(tilt)
        // Feathers down while it rises, up while it falls, turning over at the top.
        var fy = falling < 0 ? 1.0 : -1.0
        if abs(falling) < height * 1.2 { fy = -falling / (height * 1.2) }
        let length = max(0.0001, (fx * fx + fy * fy).squareRoot())
        fx /= length
        fy /= length
        p.dot(x, y, 0.75)
        for spread in [-0.42, 0.0, 0.42] {
            let ca = cos(spread), sa = sin(spread)
            let ax = fx * ca - fy * sa, ay = fx * sa + fy * ca
            p.line([(x, y), (x - ax * 3.4, y + ay * 3.4)], 0.36, wobble: 0.08)
        }
        if phase < 0.10 || phase > 0.94 {
            // The knock of the kick.
            for angle in [0.3, 1.0, 1.7] {
                let from: Point = (x + 1.5 * cos(angle) + 1.0, y + 2.0 + 1.2 * sin(angle))
                let to: Point = (x + 2.8 * cos(angle) + 1.0, y + 2.0 + 2.6 * sin(angle))
                p.line([from, to], 0.3, wobble: 0.06, alpha: 0.6)
            }
        }
        return kicks
    }

    /// Counting in 正: five strokes to a character.
    private func tally(_ p: inout FlipPencil, x: Double, y: Double, count: Int) {
        let strokes: [[Point]] = [[(0, 0), (3.4, 0)], [(1.7, 0), (1.7, 3.6)], [(1.7, 1.8), (3.2, 1.8)], [(0.4, 1.5), (0.4, 3.6)], [(-0.3, 3.6), (3.7, 3.6)]]
        for i in 0..<min(max(0, count), 15) {
            let cx = x + Double(i / 5) * 5.2
            let from = strokes[i % 5][0], to = strokes[i % 5][1]
            p.line([(cx + from.0, y + from.1), (cx + to.0, y + to.1)], 0.42, wobble: 0.07)
        }
    }
}

/// A 典藏卡带 on the upper screen: the film, its line under it; first the
/// opening (the card, its films' name, its number and date); after the last
/// film its last picture, still; a gust when a finger asks for one.
/// (金卡带's film and 银卡带's seasons are videos: GoldFilmScreen,
/// SilverFilmScreen.)
struct GoldReelScreen: View {
    var s: Double
    @ObservedObject private var reel = GoldReel.shared
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    /// Where a film's last picture is held (before it would go dark).
    private static func holdAt(_ cartridge: Cartridge) -> Double { GoldReelPlan.seconds(cartridge) - 1.4 }
    var body: some View {
        if reel.isFilm {
            GoldFilmScreen(s: s)
        } else if reel.isSeasons {
            SilverFilmScreen(s: s)
        } else {
            drawn
        }
    }
    /// 铜卡带's games, drawn as they play.
    private var drawn: some View {
        let cartridge = reel.cartridge
        let game = reel.game
        let title = reel.title, key = reel.key
        let gameNumbers = reel.plan.random(for: game)
        let began = reel.began, opening = reel.opening, ended = reel.ended
        let wind = reel.wind
        return ZStack {
            ZStack(alignment: .bottom) {
                Color.black
                // Thirty pictures a second, so the wind runs smooth (the pages
                // turn twelve times a second all the same).
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let now = timeline.date
                    let openingAge = opening.map { now.timeIntervalSince($0) } ?? 99
                    let inOpening = openingAge < GoldReel.openingSeconds
                    // (the still goes dark as the opening ends: the film comes up out of black)
                    let scrim = 0.66 + 0.34 * min(1, max(0, (openingAge - (GoldReel.openingSeconds - 0.5)) / 0.5))
                    // In the opening, a picture of the first film stands dim behind the words.
                    let t = inOpening ? 4.0 : (ended ? Self.holdAt(cartridge) : max(0, now.timeIntervalSince(began)))
                    let blows = wind.blows(at: now), strongest = wind.strongest(at: now)
                    Canvas { context, size in
                        // (a gust blows the book's pages up at their corner and holds them up while it
                        // lasts — a breath's as long as the breath — swaying; each page flutters on its own as well)
                        let lift = inOpening ? 0 : strongest.map { abs(GoldFilm.windLevel("sway", age: $0.age, right: $0.right, strength: $0.strength)) } ?? 0
                        FlipBookPainter(game: game, random: gameNumbers, t: t, wind: lift).draw(context, size: size)
                        // the wind's white lines (the pages answer the wind)
                        for blow in blows where blow.age < ReelGust.seconds {
                            ReelGust(age: blow.age, right: blow.right, streaksOnly: true, strength: blow.left).draw(context, size: size)
                        }
                        if inOpening { context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.08, green: 0.05, blue: 0.04).opacity(scrim))) }
                    }
                }
                // (11-23: no line under the pictures any more)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityValue(Text(verbatim: key))
            .accessibilityIdentifier("gold-reel-screen")
            if let opening {
                ReelOpening(cartridge: cartridge, began: opening, welcome: reel.welcome, code: reel.plan.code, s: s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onReceive(clock) { reel.tick($0) }
    }
}

/// The opening, over a dim picture: the card's metal in a ring, its films'
/// name, its number and the day it became the player's; the first time,
/// 「这盘卡带是你的了」. It comes up and goes in the opening's few seconds.
struct ReelOpening: View {
    var cartridge: Cartridge
    var began: Date
    var welcome: Bool
    var code: String
    var s: Double
    var body: some View {
        let metal = Color(red: min(1, cartridge.tint.metal.0 * 1.08), green: min(1, cartridge.tint.metal.1 * 1.08), blue: min(1, cartridge.tint.metal.2 * 1.08))
        let line = String(localized: "No. \(code) · \(CartridgeRecord.sinceText(cartridge))入手")
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let age = timeline.date.timeIntervalSince(began)
            let shown = min(1, max(0, age / 0.45)) * min(1, max(0, (GoldReel.openingSeconds - age) / 0.45))
            VStack(spacing: 6 * s) {
                Text(cartridge.title)
                    .font(.system(size: 9 * s, weight: .bold, design: .rounded)).tracking(2 * s)
                    .foregroundStyle(metal)
                    .padding(.horizontal, 9 * s).padding(.vertical, 2.5 * s)
                    .overlay(Capsule().strokeBorder(metal, lineWidth: 1.3 * s))
                Text(cartridge == .gold ? GoldFilm.name : cartridge.subtitle)
                    .font(.system(size: 25 * s, weight: .bold, design: .serif)).tracking(5 * s)
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text(line)
                    .font(.system(size: 8.5 * s, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.94, green: 0.90, blue: 0.81))
                if welcome {
                    Text("这盘卡带是你的了")
                        .font(.system(size: 9.5 * s, weight: .bold, design: .rounded))
                        .foregroundStyle(metal)
                        .padding(.top, 2 * s)
                }
            }
            .padding(.horizontal, 16 * s)
            .opacity(shown)
            .scaleEffect(0.97 + 0.03 * shown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: welcome ? "welcome" : "again"))
        .accessibilityIdentifier("reel-opening")
    }
}

/// 金卡带's film on the upper screen: first the opening over a dim picture
/// of its first shot (going dark as it ends: the film comes up out of
/// black); then the film with its sound; after it the last picture, held,
/// its dust still drifting in the screens' light (faded in over the film's
/// own last picture). Dust lies on what was left in the attic (落灰, 翻出来,
/// 屏幕亮了). When a finger or a breath asks for a gust, the wind's white
/// lines cross the picture and what is in it answers (no leaves: the
/// picture's own things move), and the dust is blown off. The film stands
/// still while its screen is not showing or the app is away.
struct GoldFilmScreen: View {
    var s: Double
    @ObservedObject private var reel = GoldReel.shared
    @Environment(\.scenePhase) private var phase
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var body: some View {
        let opening = reel.opening, ended = reel.ended
        let wind = reel.wind
        let label = "\(GoldFilm.name)：\(reel.title)"
        let value = ended ? "\(reel.key).held" : reel.key
        return ZStack {
            ZStack {
                Color.black
                if let opening {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let age = timeline.date.timeIntervalSince(opening)
                        let scrim = 0.66 + 0.34 * min(1, max(0, (age - (GoldReel.openingSeconds - 0.5)) / 0.5))
                        ZStack {
                            GoldFilmPicture(file: GoldFilm.opening)
                            Color(red: 0.08, green: 0.05, blue: 0.04).opacity(scrim)
                        }
                    }
                } else {
                    #if os(iOS)
                    GoldFilmPlayer(cue: reel.cue, playing: reel.pausedAt == nil && !ended)
                    #else
                    GoldFilmPicture(file: GoldFilm.picture(reel.index), whole: true)
                    #endif
                    if ended {
                        GoldFilmHold()
                            .transition(.opacity)
                    }
                }
                // (from 落灰 on, the dust lying on the box and the console)
                if opening == nil, ended || reel.index >= GoldFilmDustPainter.firstShot {
                    GoldFilmDust(dusted: reel.dusted, ended: ended)
                }
                if !wind.isEmpty, opening == nil {
                    GoldFilmWind(wind: wind, ended: ended)
                    GoldFilmStreaks(wind: wind)
                }
            }
            .animation(.easeInOut(duration: 1.2), value: ended)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(Text(verbatim: value))
            .accessibilityIdentifier("gold-reel-screen")
            if let opening {
                ReelOpening(cartridge: .gold, began: opening, welcome: reel.welcome, code: reel.plan.code, s: s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onReceive(clock) { reel.tick($0) }
        .onAppear { reel.resume() }
        .onDisappear { reel.pause() }
        .onChange(of: phase) { _, now in
            if now == .active { reel.resume() } else { reel.pause() }
        }
    }
}

/// 银卡带's seasons on the upper screen: first the opening over a dim picture
/// of the season it begins with (going dark as it ends: the film comes up
/// out of black); then the seasons, a video each with its sound, one after
/// another round the year, each one's name in the picture's corner for a
/// moment as it begins; after the fourth its last picture, held (faded in
/// over the film before it goes dark, its last sound playing on). When a
/// finger or a breath asks for a gust, the wind's white lines cross the
/// picture and the season's own things blow across with them. The film
/// stands still while its screen is not showing or the app is away.
struct SilverFilmScreen: View {
    var s: Double
    @ObservedObject private var reel = GoldReel.shared
    @Environment(\.scenePhase) private var phase
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var body: some View {
        let opening = reel.opening, ended = reel.ended
        let season = reel.season
        let wind = reel.wind
        let label = "\(Cartridge.silver.title)：\(reel.title)"
        let value = ended ? "\(reel.key).held" : reel.key
        return ZStack {
            ZStack {
                Color.black
                if let opening {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let age = timeline.date.timeIntervalSince(opening)
                        let scrim = 0.66 + 0.34 * min(1, max(0, (age - (GoldReel.openingSeconds - 0.5)) / 0.5))
                        ZStack {
                            GoldFilmPicture(file: season.opening)
                            Color(red: 0.08, green: 0.05, blue: 0.04).opacity(scrim)
                        }
                    }
                } else {
                    #if os(iOS)
                    // (it plays on under the held picture: the film's last sound to its end)
                    GoldFilmPlayer(file: season.file, cue: reel.cue, playing: reel.pausedAt == nil)
                    #else
                    GoldFilmPicture(file: season.picture, whole: true)
                    #endif
                    if ended {
                        GoldFilmPicture(file: season.held, whole: true)
                            .transition(.opacity)
                    } else {
                        SilverSeasonName(title: reel.title, s: s)
                    }
                }
                if !wind.isEmpty, opening == nil {
                    SilverFilmGust(wind: wind, season: season)
                }
            }
            .animation(.easeInOut(duration: 1.2), value: ended)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(Text(verbatim: value))
            .accessibilityIdentifier("gold-reel-screen")
            if let opening {
                ReelOpening(cartridge: .silver, began: opening, welcome: reel.welcome, code: reel.plan.code, s: s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onReceive(clock) { reel.tick($0) }
        .onAppear { reel.resume() }
        .onDisappear { reel.pause() }
        .onChange(of: phase) { _, now in
            if now == .active { reel.resume() } else { reel.pause() }
        }
    }
}

/// Where a film's picture is on its screen: all of it seen, in the middle (a band either side of it
/// stays dark when the screen is wider or taller than the picture).
private func filmPictureRect(in size: CGSize) -> CGRect {
    let w = Double(size.width), h = Double(size.height)
    let scale = min(w / GoldFilm.pictureSize.width, h / GoldFilm.pictureSize.height)
    let pw = GoldFilm.pictureSize.width * scale, ph = GoldFilm.pictureSize.height * scale
    return CGRect(x: (w - pw) / 2, y: (h - ph) / 2, width: pw, height: ph)
}

/// A season's name in the picture's lower corner while its film comes up
/// out of black, then gone.
struct SilverSeasonName: View {
    var title: String
    var s: Double
    @ObservedObject private var reel = GoldReel.shared
    var body: some View {
        GeometryReader { proxy in
            let rect = filmPictureRect(in: proxy.size)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = reel.filmTime(timeline.date)
                let shown = min(1, max(0, (t - 0.5) / 0.6)) * min(1, max(0, (4.2 - t) / 0.8))
                Text(title)
                    .font(.system(size: 12 * s, weight: .semibold, design: .serif)).tracking(2 * s)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3 * s)
                    .padding(.horizontal, 12 * s).padding(.vertical, 10 * s)
                    .opacity(shown)
                    .frame(width: rect.width, height: rect.height, alignment: .bottomLeading)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A gust over 银卡带's film: the wind's white lines and the season's own
/// things blown across, over the film's picture only.
struct SilverFilmGust: View {
    var wind: ReelWind
    var season: SilverSeason
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let blows = wind.blows(at: timeline.date).filter { $0.age < ReelGust.seconds }
            Canvas { context, size in
                guard !blows.isEmpty else { return }
                let rect = filmPictureRect(in: size)
                var c = context
                c.clip(to: Path(rect))
                c.translateBy(x: rect.minX, y: rect.minY)
                // (each gust's own things on their way across; a breath's die down with it)
                for blow in blows { ReelGust(age: blow.age, right: blow.right, season: season, strength: blow.left).draw(c, size: rect.size) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A picture of 金卡带's film from the app (kept once read): filling its
/// place, or (`whole`) all of it seen, as the film itself is shown.
struct GoldFilmPicture: View {
    var file: String
    var whole = false
    var body: some View {
        if let image = GoldFilmPictures.image(file) {
            if whole { image.resizable().scaledToFit() } else { image.resizable().scaledToFill() }
        } else {
            Color.black
        }
    }
}

@MainActor enum GoldFilmPictures {
    private static var kept: [String: Image] = [:]
    static func image(_ file: String) -> Image? {
        if let image = kept[file] { return image }
        #if os(iOS)
        guard let path = Bundle.main.path(forResource: file, ofType: nil), let read = UIImage(contentsOfFile: path) else { return nil }
        let image = Image(uiImage: read)
        #else
        guard let url = Bundle.main.url(forResource: file, withExtension: nil), let read = NSImage(contentsOf: url) else { return nil }
        let image = Image(nsImage: read)
        #endif
        kept[file] = image
        return image
    }
}

/// After the film: its last picture stays, and the dust drifts on in the
/// screens' light, glinting as it turns (the film's own dust, drawn again).
struct GoldFilmHold: View {
    private static let clock = Date()
    var body: some View {
        ZStack {
            GoldFilmPicture(file: GoldFilm.held, whole: true)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let seconds = timeline.date.timeIntervalSince(Self.clock)
                Canvas { context, size in
                    // the whole picture, in the middle of the screen, as the film is shown (a band either side if the screen is not 5:3)
                    let scale = min(Double(size.width) / GoldFilm.pictureSize.width, Double(size.height) / GoldFilm.pictureSize.height)
                    let left = (Double(size.width) - GoldFilm.pictureSize.width * scale) / 2
                    let top = (Double(size.height) - GoldFilm.pictureSize.height * scale) / 2
                    let camera = GoldFilm.lastCamera, k = GoldFilm.pictureSize.width / camera.width
                    var soft = context
                    soft.addFilter(.blur(radius: 0.6 * scale))
                    for index in 0..<GoldFilm.dust.count {
                        let mote = GoldFilm.mote(index, at: seconds)
                        let x = left + (mote.x - camera.x) * k * scale, y = top + (mote.y - camera.y) * k * scale
                        let r = max(0.5, mote.radius * scale)
                        soft.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                                  with: .color(Color(red: 1.0, green: 0.965, blue: 0.88).opacity(mote.glint)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

/// What answers a gust over 金卡带's film, for as long as the gust lasts, each picture in its own way:
/// the places in it that move (the candle flames lean and the torn wrapping paper lifts in 生日礼物,
/// the curtains' lower half swings in 被窝里, the children's hair is blown over in 课间, the fan rocks
/// on the mat in 暑假, two papers' corners flap and the top book's cover lifts in 书堆, the carton's
/// back flap leans in 收拾: each drawn at a few strengths, the nearest laid exactly over the film where
/// its camera has it now), and dust stirred up where light falls through the air (课间, 收拾, 落灰,
/// 翻出来, 屏幕亮了 and the held picture).
struct GoldFilmWind: View {
    var wind: ReelWind
    var ended: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let blows = wind.blows(at: timeline.date), strongest = wind.strongest(at: timeline.date)
            let t = ended ? GoldFilm.length : GoldFilmClock.shared.time()
            let layers = GoldFilmWindPainter.layers(t: t, ended: ended)
            let images = GoldFilmWindPainter.images(for: layers)
            let _ = wind.gusts.last.map { GoldFilmWindPainter.note(gustAt: $0.at, t: t, layers: layers) }
            Canvas { context, size in
                guard !blows.isEmpty else { return }
                GoldFilmWindPainter.draw(context, size: size, layers: layers, images: images, blows: blows, strongest: strongest)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The pictures showing at a moment of the film, each with its camera and how much of the picture
/// it makes, and what in it answers the wind.
struct GoldFilmWindLayer {
    var picture: String
    var camera: GoldFilm.Window
    var weight: Double
    var places: [GoldWindPlace]
    var beams: [[(Double, Double)]]
    var area: (x: Double, y: Double, rx: Double, ry: Double)?
}

@MainActor enum GoldFilmWindPainter {
    static let places: [GoldWindPlace] = {
        guard let url = Bundle.main.url(forResource: "gold-wind", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return GoldWindPlace.decode(data)
    }()
    static func layers(t: Double, ended: Bool) -> [GoldFilmWindLayer] {
        let showing: [(index: Int, weight: Double)] = ended ? [(GoldFilm.clips.count - 1, 1)] : GoldFilm.weights(at: t)
        return showing.compactMap { item in
            let clip = GoldFilm.clips[item.index]
            let camera = ended ? GoldFilm.Window(x: GoldFilm.lastCamera.x, y: GoldFilm.lastCamera.y, w: GoldFilm.lastCamera.width) : GoldFilm.camera(clip, at: t)
            let own = places.filter { $0.picture == clip.picture }
            let beams = GoldFilm.beams[clip.picture] ?? []
            let area = GoldFilm.lightAreas[clip.picture]
            guard item.weight > 0.01, !own.isEmpty || !beams.isEmpty || area != nil else { return nil }
            return GoldFilmWindLayer(picture: clip.picture, camera: camera, weight: item.weight, places: own, beams: beams, area: area)
        }
    }
    /// The strips the layers need, read once (GoldFilmPictures keeps them).
    static func images(for layers: [GoldFilmWindLayer]) -> [String: Image] {
        var out: [String: Image] = [:]
        for layer in layers {
            for place in layer.places where out[place.file] == nil {
                if let image = GoldFilmPictures.image(place.file) { out[place.file] = image }
            }
        }
        return out
    }
    private static var noted: Date?
    /// One line in the log for each gust: what answered it.
    static func note(gustAt: Date, t: Double, layers: [GoldFilmWindLayer]) {
        guard noted != gustAt else { return }
        noted = gustAt
        let what = layers.map { "\($0.picture) (\($0.places.count) places\($0.beams.isEmpty && $0.area == nil ? "" : ", dust in the light"))" }
        NSLog("[gold] the wind over the film at %.1f s: %@", t, what.isEmpty ? "nothing in this picture answers it" : what.joined(separator: ", "))
    }
    /// `blows`: every gust still blowing; `strongest`: the one the places follow (ReelWind).
    nonisolated static func draw(_ context: GraphicsContext, size: CGSize, layers: [GoldFilmWindLayer], images: [String: Image], blows: [ReelWind.Blow], strongest: ReelWind.Blow?) {
        let w = Double(size.width), h = Double(size.height)
        let scale = min(w / GoldFilm.pictureSize.width, h / GoldFilm.pictureSize.height)
        let left = (w - GoldFilm.pictureSize.width * scale) / 2, top = (h - GoldFilm.pictureSize.height * scale) / 2
        // (the film laid its pictures one over another: each place is laid as much as its picture shows)
        let total = layers.filter { !$0.places.isEmpty }.reduce(0) { $0 + $1.weight }
        var above = total
        // (the places laid over the film come in and go as the wind does: at no wind each is the film's own picture)
        let master = strongest.map { GoldFilm.ease($0.age / 0.15) * GoldFilm.ease($0.strength / 0.08) } ?? 0
        for layer in layers {
            let k = GoldFilm.pictureSize.width / layer.camera.w
            func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: left + (x - layer.camera.x) * k * scale, y: top + (y - layer.camera.y) * k * scale) }
            if !layer.places.isEmpty, let strongest, master > 0 {
                above -= layer.weight
                let alpha = min(1, layer.weight / max(0.0001, 1 - above)) * master
                for place in layer.places {
                    guard let image = images[place.file] else { continue }
                    let level = GoldFilm.windLevel(place.kind, age: strongest.age, right: strongest.right, strength: strongest.strength)
                    let (i0, i1, f) = GoldFilm.frames(for: level, in: place.levels)
                    let origin = at(place.x, place.y)
                    let rect = CGRect(x: origin.x, y: origin.y, width: place.w * k * scale, height: place.h * k * scale)
                    let n = CGFloat(place.levels.count)
                    let resolved = context.resolve(image)
                    for (frame, opacity) in [(i0, alpha), (i1, alpha * f)] where opacity > 0.003 {
                        var c = context
                        c.clip(to: Path(rect))
                        c.opacity = opacity
                        c.draw(resolved, in: CGRect(x: rect.minX - CGFloat(frame) * rect.width, y: rect.minY, width: rect.width * n, height: rect.height))
                    }
                }
            }
            // dust stirred up in the light, blown the way the wind goes
            if !layer.beams.isEmpty || layer.area != nil {
                var soft = context
                soft.addFilter(.blur(radius: 0.6 * scale))
                let count = 46
                // (each gust stirs its own; a breath's settle with it)
                for blow in blows where blow.age < GoldFilm.gustSeconds {
                    for index in 0..<count {
                        let mote = GoldFilm.gustMote(index, age: blow.age, right: blow.right)
                        let glint = mote.glint * blow.left
                        guard glint > 0.01 else { continue }
                        let p: (Double, Double)
                        if let area = layer.area, layer.beams.isEmpty || index % 2 == 1 {
                            p = (area.x + (mote.u - 0.5) * 2 * area.rx, area.y + (mote.v - 0.5) * 2 * area.ry)
                        } else {
                            p = GoldFilm.point(in: layer.beams[index % layer.beams.count], u: mote.u, v: mote.v)
                        }
                        let c = at(p.0, p.1), r = max(0.5, mote.size * k / 2.4 * scale)
                        soft.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                                  with: .color(Color(red: 1.0, green: 0.965, blue: 0.88).opacity(glint * layer.weight)))
                    }
                }
            }
        }
    }
}

/// The wind's white lines across the film's picture while a gust lasts (the same lines 银卡带 and 铜卡带
/// have; no leaves: in this film what is in the picture answers the wind itself).
struct GoldFilmStreaks: View {
    var wind: ReelWind
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let blows = wind.blows(at: timeline.date).filter { $0.age < ReelGust.seconds }
            Canvas { context, size in
                guard !blows.isEmpty else { return }
                // over the film's picture only (a band either side of it stays dark)
                let w = Double(size.width), h = Double(size.height)
                let scale = min(w / GoldFilm.pictureSize.width, h / GoldFilm.pictureSize.height)
                let pw = GoldFilm.pictureSize.width * scale, ph = GoldFilm.pictureSize.height * scale
                let rect = CGRect(x: (w - pw) / 2, y: (h - ph) / 2, width: pw, height: ph)
                var c = context
                c.clip(to: Path(rect))
                c.translateBy(x: rect.minX, y: rect.minY)
                for blow in blows { ReelGust(age: blow.age, right: blow.right, streaksOnly: true, strength: blow.left).draw(c, size: rect.size) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Dust lying on what was left in the attic (the box in 落灰 and 翻出来, the console in 翻出来 and
/// 屏幕亮了): laid over the film where its picture shows, as much as the picture shows. A gust blows it
/// off: it lifts away in grains the way the wind goes, and stays off (GoldReel.dusted).
struct GoldFilmDust: View {
    var dusted: [String: GoldDustBlow]
    var ended: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let now = timeline.date
            let t = ended ? GoldFilm.length : GoldFilmClock.shared.time()
            let layers = GoldFilmDustPainter.layers(t: t, ended: ended)
            let images = GoldFilmDustPainter.images(for: layers)
            Canvas { context, size in
                GoldFilmDustPainter.draw(context, size: size, layers: layers, images: images, dusted: dusted, now: now)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A picture showing with dust on it: its camera, how much of the picture it makes, the dust.
struct GoldFilmDustLayer {
    var camera: GoldFilm.Window
    var weight: Double
    var places: [GoldDustPlace]
}

@MainActor enum GoldFilmDustPainter {
    static let places: [GoldDustPlace] = {
        guard let url = Bundle.main.url(forResource: "gold-dust", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return GoldDustPlace.decode(data)
    }()
    /// The first shot with dust (落灰).
    static let firstShot = GoldFilm.shots.firstIndex { $0.key == "attic" } ?? 6
    static func layers(t: Double, ended: Bool) -> [GoldFilmDustLayer] {
        let showing: [(index: Int, weight: Double)] = ended ? [(GoldFilm.clips.count - 1, 1)] : GoldFilm.weights(at: t)
        return showing.compactMap { item in
            let clip = GoldFilm.clips[item.index]
            let own = places.filter { $0.picture == clip.picture }
            guard item.weight > 0.01, !own.isEmpty else { return nil }
            let camera = ended ? GoldFilm.Window(x: GoldFilm.lastCamera.x, y: GoldFilm.lastCamera.y, w: GoldFilm.lastCamera.width) : GoldFilm.camera(clip, at: t)
            return GoldFilmDustLayer(camera: camera, weight: item.weight, places: own)
        }
    }
    /// The dust's pictures the layers need, read once (GoldFilmPictures keeps them).
    static func images(for layers: [GoldFilmDustLayer]) -> [String: Image] {
        var out: [String: Image] = [:]
        for layer in layers {
            for place in layer.places where out[place.file] == nil {
                if let image = GoldFilmPictures.image(place.file) { out[place.file] = image }
            }
        }
        return out
    }
    /// The things whose dust is in the picture at `t` (the film's time; its end: the held picture).
    static func things(t: Double, ended: Bool) -> [(thing: String, picture: String)] {
        let showing: [Int] = ended ? [GoldFilm.clips.count - 1] : GoldFilm.weights(at: t).filter { $0.weight > 0.05 }.map(\.index)
        var out: [(thing: String, picture: String)] = []
        for index in showing {
            for place in places where place.picture == GoldFilm.clips[index].picture && !out.contains(where: { $0.thing == place.thing }) {
                out.append((place.thing, place.picture))
            }
        }
        return out
    }
    nonisolated static func draw(_ context: GraphicsContext, size: CGSize, layers: [GoldFilmDustLayer], images: [String: Image], dusted: [String: GoldDustBlow], now: Date) {
        let w = Double(size.width), h = Double(size.height)
        let scale = min(w / GoldFilm.pictureSize.width, h / GoldFilm.pictureSize.height)
        let left = (w - GoldFilm.pictureSize.width * scale) / 2, top = (h - GoldFilm.pictureSize.height * scale) / 2
        for layer in layers {
            let k = GoldFilm.pictureSize.width / layer.camera.w
            func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: left + (x - layer.camera.x) * k * scale, y: top + (y - layer.camera.y) * k * scale) }
            for place in layer.places {
                let blow = dusted[place.thing]
                let age = blow.map { now.timeIntervalSince($0.at) } ?? -1
                let lying = blow == nil ? 1 : GoldFilm.dustLeft(age)
                if lying > 0.003, let image = images[place.file] {
                    let origin = at(place.x, place.y)
                    var c = context
                    c.opacity = layer.weight * lying
                    c.draw(image, in: CGRect(x: origin.x, y: origin.y, width: place.w * k * scale, height: place.h * k * scale))
                }
                // the grains it lifts away in, the way the wind went
                guard let blow, age >= 0, age < GoldFilm.dustBlowSeconds else { continue }
                var soft = context
                soft.addFilter(.blur(radius: 0.5 * scale))
                for (i, seed) in place.seeds.enumerated() where seed.count == 2 {
                    for j in 0..<2 {
                        let grain = GoldFilm.blownGrain(i * 2 + j, age: age, right: blow.right)
                        guard grain.alpha > 0.01 else { continue }
                        let p = at(seed[0] + grain.dx, seed[1] + grain.dy), r = max(0.6, grain.size * k * scale * 0.9)
                        soft.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                                  with: .color(Color(red: 0.86, green: 0.83, blue: 0.78).opacity(grain.alpha * layer.weight * 0.9)))
                    }
                }
            }
        }
    }
}

/// The film's time as its player has it (so what is laid over the film stays on what it covers);
/// the reel's own clock when no player is out.
@MainActor final class GoldFilmClock {
    static let shared = GoldFilmClock()
    #if os(iOS)
    weak var player: AVPlayer?
    #endif
    func time() -> Double {
        #if os(iOS)
        if let player, player.currentItem != nil {
            let seconds = player.currentTime().seconds
            if seconds.isFinite { return min(GoldReel.shared.filmLength, max(0, seconds)) }
        }
        #endif
        return GoldReel.shared.filmTime()
    }
}

#if os(iOS)
/// The film itself: the system's player in a layer, sent where the reel
/// says each time its cue changes (a shot chosen, stood still, let go on),
/// and stopped at the end on the last picture. 银卡带's next season puts its
/// own video in. Its sound goes out through the app's own audio session
/// (the console's sound rules); none in a silent test run.
struct GoldFilmPlayer: UIViewRepresentable {
    /// The video (in the app, `.mp4`).
    var file = GoldFilm.file
    var cue: Int
    var playing: Bool
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var file = ""
        var cue = -1
        var playing = false
        var watch: NSKeyValueObservation?
    }
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .black
        // all of the picture seen, as the films drawn by the app are (nothing at its edges cut off)
        view.playerLayer.videoGravity = .resizeAspect
        let player = AVPlayer()
        player.isMuted = SilentRun.on
        player.actionAtItemEnd = .pause
        view.playerLayer.player = player
        GoldFilmClock.shared.player = player
        load(view)
        go(view)
        return view
    }
    func updateUIView(_ view: PlayerView, context: Context) {
        if view.file != file {
            load(view)
            view.cue = -1
        }
        if view.cue != cue || view.playing != playing { go(view) }
    }
    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
        view.playerLayer.player = nil
        view.watch = nil
    }
    /// The video into the player, in place of the one it had.
    private func load(_ view: PlayerView) {
        let file = self.file
        view.file = file
        view.watch = nil
        guard let player = view.playerLayer.player else { return }
        guard let url = Bundle.main.url(forResource: file, withExtension: "mp4") else {
            player.replaceCurrentItem(with: nil)
            NSLog("[gold] the film %@ is not in the app", file)
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        view.watch = item.observe(\.status) { item, _ in
            switch item.status {
            case .readyToPlay: NSLog("[gold] the film %@ is ready (%.1f s)", file, item.duration.seconds)
            case .failed: NSLog("[gold] the film %@ did not open: %@", file, item.error.map { "\($0)" } ?? "?")
            default: break
            }
        }
    }
    /// To where the reel's film is now; playing or still.
    private func go(_ view: PlayerView) {
        let moved = view.cue != cue
        view.cue = cue
        view.playing = playing
        guard let player = view.playerLayer.player else { return }
        let t = GoldReel.shared.filmTime()
        if moved { player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        if playing {
            GoldFilmSound.prepare()
            player.play()
        } else {
            player.pause()
        }
        NSLog("[gold] the film %@ at %.1f s", playing ? "plays" : "stands still", t)
    }
}

/// The audio session as the console's sound rules want it, before the
/// film's sound starts (on a queue of its own: setting it can block).
enum GoldFilmSound {
    private static let queue = DispatchQueue(label: "FoldArc.gold.film", qos: .userInitiated)
    static func prepare() {
        queue.async {
            AudioPolicy.shared.configure("gold film")
            do { try AVAudioSession.sharedInstance().setActive(true) } catch { NSLog("[gold] the audio session not active: %@", "\(error)") }
        }
    }
}
#endif

/// A gust over the film: a few streaks of wind blown across from the side
/// the finger came from, two seconds and a little, and over 银卡带's seasons
/// the season's own things blown along with them — willow fluff in spring,
/// fireflies in summer, leaves in autumn, snow in winter (`streaksOnly`:
/// the streaks alone).
struct ReelGust {
    static let seconds = 2.4
    /// Seconds since the gust began.
    var age: Double
    var right: Bool
    var streaksOnly = false
    var season = SilverSeason.autumn
    /// How much of it is left (1; a breath's gust goes to 0 as the breath ends: ReelWind.Blow.left).
    var strength = 1.0
    func draw(_ context: GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        var random = ReelRandom(seed: 0x6A75_7374)
        let fade = min(1, age / 0.25) * min(1, max(0, (Self.seconds - age) / 0.5)) * min(1, max(0, strength))
        // the streaks
        for k in 0..<5 {
            let y = h * (0.15 + 0.17 * Double(k) + 0.05 * random.unit())
            let speed = 1.3 + 0.5 * random.unit(), delay = 0.12 * Double(k) * random.unit()
            let u = (age - delay) * speed / Self.seconds
            guard u > 0, u < 1.2 else { continue }
            let head = -0.2 * w + u * 1.4 * w, length = 0.3 * w
            var path = Path()
            for i in 0...16 {
                let x = head - length * Double(i) / 16
                let point = CGPoint(x: right ? x : w - x, y: y + sin(x / w * 7 + Double(k)) * h * 0.025)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(Color(red: 1, green: 0.97, blue: 0.88).opacity(0.5 * fade)), style: StrokeStyle(lineWidth: max(1, h * 0.006), lineCap: .round))
        }
        if streaksOnly { return }
        switch season {
        case .spring: fluff(context, w: w, h: h, fade: fade)
        case .summer: fireflies(context, w: w, h: h, fade: fade)
        case .autumn: leaves(context, w: w, h: h, fade: fade, random: &random)
        case .winter: snow(context, w: w, h: h, fade: fade)
        }
    }
    /// How far across one of the things is (0 at the side the wind comes from), or nil: not in the air.
    private func along(_ delay: Double, _ speed: Double, upTo end: Double = 1.15) -> Double? {
        let u = (age - delay) * speed / (Self.seconds - 0.3)
        return u > 0 && u < end ? u : nil
    }
    private func x(_ u: Double, _ w: Double, from start: Double = -0.08, span: Double = 1.16) -> Double {
        let x = start * w + u * span * w
        return right ? x : w - x
    }
    /// The leaves, tumbling.
    private func leaves(_ context: GraphicsContext, w: Double, h: Double, fade: Double, random: inout ReelRandom) {
        let colors: [(Double, Double, Double)] = [(0.93, 0.74, 0.25), (0.86, 0.52, 0.20), (0.72, 0.40, 0.18), (0.95, 0.84, 0.40)]
        for k in 0..<14 {
            let c = colors[k % colors.count]
            let y0 = h * (0.05 + 0.9 * random.unit()), delay = 0.6 * random.unit(), speed = 0.8 + 0.6 * random.unit()
            let size = h * (0.018 + 0.014 * random.unit())
            guard let u = along(delay, speed) else { continue }
            let y = y0 + sin(u * 9 + Double(k)) * h * 0.04 + u * h * 0.06
            let turn = (u * 12 + Double(k)) * (k % 2 == 0 ? 1 : -1)
            var leaf = context
            leaf.translateBy(x: x(u, w), y: y)
            leaf.rotate(by: .radians(turn))
            leaf.scaleBy(x: 1, y: 0.35 + 0.65 * abs(cos(turn * 0.7)))
            leaf.fill(Path(ellipseIn: CGRect(x: -size, y: -size * 0.45, width: size * 2, height: size * 0.9)),
                      with: .color(Color(red: c.0, green: c.1, blue: c.2).opacity(0.92 * fade)))
        }
    }
    /// Willow fluff: soft white tufts of cotton, a seed in each, slower than leaves, rising a little as
    /// they float along and turning slowly.
    private func fluff(_ context: GraphicsContext, w: Double, h: Double, fade: Double) {
        var random = ReelRandom(seed: 0x6C69_7578)
        var tufts: [(x: Double, y: Double, r: Double, turn: Double, puffs: [(Double, Double, Double)])] = []
        for k in 0..<22 {
            let y0 = h * (0.06 + 0.88 * random.unit()), delay = 0.8 * random.unit(), speed = 0.55 + 0.4 * random.unit()
            let r = h * (0.008 + 0.008 * random.unit()), phase = random.unit() * 6.28
            // each tuft a few puffs of its own, run together
            let puffs = (0..<3).map { _ in (random.range(-0.55, 0.55), random.range(-0.4, 0.4), random.range(0.55, 0.95)) }
            guard let u = along(delay, speed, upTo: 1.12) else { continue }
            let y = y0 - u * h * 0.1 + sin(u * 6 + phase) * h * 0.05
            tufts.append((x(u, w, from: -0.05, span: 1.1), y, r, phase + u * 1.6 * (k % 2 == 0 ? 1 : -1), puffs))
        }
        var soft = context
        soft.addFilter(.blur(radius: h * 0.0045))
        soft.drawLayer { layer in
            for tuft in tufts {
                let c = cos(tuft.turn), s = sin(tuft.turn)
                for puff in tuft.puffs {
                    let px = tuft.x + (puff.0 * c - puff.1 * s) * tuft.r * 1.6, py = tuft.y + (puff.0 * s + puff.1 * c) * tuft.r * 1.6
                    let r = tuft.r * puff.2
                    layer.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: 2 * r, height: 2 * r)),
                               with: .color(Color(red: 1, green: 0.99, blue: 0.96).opacity(0.55 * fade)))
                }
            }
        }
        for tuft in tufts {
            let r = max(0.6, tuft.r * 0.16)
            context.fill(Path(ellipseIn: CGRect(x: tuft.x - r, y: tuft.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color(red: 0.62, green: 0.58, blue: 0.48).opacity(0.5 * fade)))
        }
    }
    /// Fireflies: small green-gold lights carried on the wind, wandering as they go, each blinking in
    /// its own time.
    private func fireflies(_ context: GraphicsContext, w: Double, h: Double, fade: Double) {
        var random = ReelRandom(seed: 0x6669_7265)
        for _ in 0..<12 {
            let y0 = h * (0.28 + 0.62 * random.unit()), delay = 0.55 * random.unit(), speed = 0.5 + 0.35 * random.unit()
            let phase = random.unit() * 6.28, rate = 4 + 3 * random.unit()
            guard let u = along(delay, speed, upTo: 1.12) else { continue }
            let px = x(u, w, from: -0.05, span: 1.1) + sin(u * 5 + phase) * w * 0.02
            let py = y0 + sin(u * 6 + phase * 1.3) * h * 0.06 - u * h * 0.05
            let blink = 0.3 + 0.7 * (0.5 + 0.5 * sin(age * rate + phase))
            let glow = h * 0.032, core = max(1, h * 0.0055)
            let middle = CGPoint(x: px, y: py)
            context.fill(Path(ellipseIn: CGRect(x: px - glow, y: py - glow, width: 2 * glow, height: 2 * glow)),
                         with: .radialGradient(Gradient(colors: [Color(red: 0.86, green: 1, blue: 0.45).opacity(0.55 * blink * fade),
                                                                 Color(red: 0.86, green: 1, blue: 0.45).opacity(0)]),
                                               center: middle, startRadius: 0, endRadius: glow))
            context.fill(Path(ellipseIn: CGRect(x: px - core, y: py - core, width: 2 * core, height: 2 * core)),
                         with: .color(Color(red: 0.97, green: 1, blue: 0.72).opacity(0.95 * blink * fade)))
        }
    }
    /// Snow: flakes blown slantwise across, falling as they go; the near ones bigger, faster and soft.
    private func snow(_ context: GraphicsContext, w: Double, h: Double, fade: Double) {
        var random = ReelRandom(seed: 0x736E_6F77)
        var far: [(Double, Double, Double, Double)] = [], near: [(Double, Double, Double, Double)] = []
        for k in 0..<44 {
            let depth = random.unit(), y0 = h * (-0.12 + 0.95 * random.unit()), delay = 0.6 * random.unit()
            let r = h * (0.0035 + 0.008 * depth), speed = 0.9 + 0.8 * depth
            guard let u = along(delay, speed, upTo: 1.2) else { continue }
            let y = y0 + u * h * (0.18 + 0.12 * depth) + sin(u * 8 + Double(k)) * h * 0.015
            let flake = (x(u, w, from: -0.05, span: 1.1), y, r, 0.65 + 0.35 * depth)
            if depth > 0.72 { near.append(flake) } else { far.append(flake) }
        }
        for (px, py, r, a) in far {
            // (a faint cool edge, so a flake shows over white snow as well)
            let e = r * 1.3
            context.fill(Path(ellipseIn: CGRect(x: px - e, y: py - e, width: 2 * e, height: 2 * e)),
                         with: .color(Color(red: 0.55, green: 0.62, blue: 0.75).opacity(0.18 * a * fade)))
            context.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color(red: 0.97, green: 0.98, blue: 1).opacity(a * fade)))
        }
        var soft = context
        soft.addFilter(.blur(radius: h * 0.004))
        soft.drawLayer { layer in
            for (px, py, r, a) in near {
                let e = r * 1.3
                layer.fill(Path(ellipseIn: CGRect(x: px - e, y: py - e, width: 2 * e, height: 2 * e)),
                           with: .color(Color(red: 0.55, green: 0.62, blue: 0.75).opacity(0.16 * a * fade)))
                layer.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: 2 * r, height: 2 * r)),
                           with: .color(Color(red: 0.97, green: 0.98, blue: 1).opacity(a * fade)))
            }
        }
    }
}
