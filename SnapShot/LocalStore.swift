import Foundation

/// Everything the app remembers, saved as one JSON file on this phone (no account, no server).
@MainActor
final class LocalStore: ObservableObject {
    @Published private(set) var cart: [CartItem] = []
    @Published private(set) var priceReports: [PriceReport] = []
    @Published private(set) var knownProducts: [String: SNAPProduct] = [:]
    @Published var monthlyBenefit: Double = 180 { didSet { save() } }

    private var isLoaded = false
    private let fileURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("snapshot-data.json")

    private struct SavedData: Codable {
        var cart: [CartItem]
        var priceReports: [PriceReport]
        var knownProducts: [String: SNAPProduct]
        var monthlyBenefit: Double
    }

    init() { load() }

    // MARK: Products

    /// Keeps a copy of products the user has opened, so they show up offline and in "Items you've looked at".
    func remember(_ product: SNAPProduct) {
        guard knownProducts[product.id] != product else { return }
        knownProducts[product.id] = product
        save()
    }

    /// Replaces a product everywhere it's stored (used when Walmart supplies a name or SNAP flag).
    func update(_ product: SNAPProduct) {
        knownProducts[product.id] = product
        if let index = cart.firstIndex(where: { $0.id == product.id }) {
            cart[index].product = product
        }
        save()
    }

    // MARK: Cart

    var cartCount: Int { cart.reduce(0) { $0 + $1.quantity } }

    func quantityInCart(_ product: SNAPProduct) -> Int {
        cart.first(where: { $0.id == product.id })?.quantity ?? 0
    }

    func addToCart(_ product: SNAPProduct) {
        guard product.eligibility != .notEligible else { return }
        if let index = cart.firstIndex(where: { $0.id == product.id }) {
            cart[index].quantity += 1
        } else {
            cart.append(CartItem(product: product, quantity: 1))
        }
        knownProducts[product.id] = product
        save()
    }

    func setQuantity(_ quantity: Int, for productID: String) {
        guard let index = cart.firstIndex(where: { $0.id == productID }) else { return }
        if quantity <= 0 { cart.remove(at: index) } else { cart[index].quantity = quantity }
        save()
    }

    func removeFromCart(at offsets: IndexSet) {
        cart.remove(atOffsets: offsets)
        save()
    }

    // MARK: Prices

    /// Most recent price per store for one product.
    func latestPrices(for productID: String) -> [String: PriceReport] {
        var latest: [String: PriceReport] = [:]
        for report in priceReports where report.productID == productID {
            if let existing = latest[report.storeName], existing.date >= report.date { continue }
            latest[report.storeName] = report
        }
        return latest
    }

    /// Every known price for a product, one per store: prices collected from the stores' websites,
    /// replaced by a live Walmart price or a price the shopper entered when there is one.
    func prices(for product: SNAPProduct) -> [String: PriceReport] {
        var result: [String: PriceReport] = [:]
        let database = StorePriceDatabase.shared
        let collected = database.collectedAt ?? Date.distantPast
        for (store, match) in database.matches(for: product) {
            let s = match.item.s
            let size = (s.isEmpty || match.item.n.lowercased().contains(s.lowercased())) ? "" : ", \(s)"
            let unit = match.item.u.flatMap { u in
                (u.isEmpty || u.lowercased() == "each" || u == match.item.s) ? nil : u
            }
            result[store] = PriceReport(productID: product.id, storeName: store, price: match.item.p,
                                        source: .storeWebsite, date: collected,
                                        matchedName: match.item.n + size, unit: unit)
        }
        for (store, report) in latestPrices(for: product.id) {
            result[store] = report
        }
        return result
    }

    /// Real prices plus a labeled estimate for every listed store that has no real price.
    func pricesWithEstimates(for product: SNAPProduct) -> [String: PriceReport] {
        var result = prices(for: product)
        let real = result
        for store in nj12Stores where result[store.name] == nil {
            if let estimate = PriceEstimator.shared.estimate(for: product, at: store.name, knownPrices: real) {
                result[store.name] = PriceReport(productID: product.id, storeName: store.name, price: estimate.price,
                                                 source: .estimate, date: StorePriceDatabase.shared.collectedAt ?? Date(),
                                                 matchedName: estimate.basis, unit: estimate.unit)
            }
        }
        return result
    }

    /// Cheapest real price; falls back to the cheapest estimate only when there are no real prices.
    func cheapestPrice(for product: SNAPProduct) -> PriceReport? {
        if let real = prices(for: product).values.min(by: { $0.price < $1.price }) { return real }
        return pricesWithEstimates(for: product).values.min { $0.price < $1.price }
    }

    func addPrice(_ price: Double, store: String, productID: String, source: PriceSource) {
        if source == .walmartAPI {
            // Keep only the newest live Walmart price; shopper-entered history stays.
            priceReports.removeAll { $0.productID == productID && $0.source == .walmartAPI }
        }
        priceReports.append(PriceReport(productID: productID, storeName: store, price: price,
                                        source: source, date: Date()))
        save()
    }

    func deletePrice(_ report: PriceReport) {
        priceReports.removeAll { $0.id == report.id }
        save()
    }

    // MARK: Trip planning

    struct StoreTripTotal: Identifiable {
        let store: SNAPStore
        let total: Double
        let missingItems: [String]
        let estimatedItems: [String]
        var id: String { store.id }
        var isComplete: Bool { missingItems.isEmpty }
    }

    /// Cost of the whole cart at each store, using only real prices.
    /// Stores with every price come first (cheapest first), then stores missing the fewest prices.
    func tripTotals() -> [StoreTripTotal] {
        guard !cart.isEmpty else { return [] }
        let pricesByProduct = Dictionary(uniqueKeysWithValues: cart.map { ($0.id, pricesWithEstimates(for: $0.product)) })

        return nj12Stores
            .map { store in
                var total = 0.0
                var missing: [String] = []
                var estimated: [String] = []
                for item in cart {
                    if let report = pricesByProduct[item.id]?[store.name] {
                        total += report.price * Double(item.quantity)
                        if report.isEstimate { estimated.append(item.product.name) }
                    } else {
                        missing.append(item.product.name)
                    }
                }
                return StoreTripTotal(store: store, total: total, missingItems: missing, estimatedItems: estimated)
            }
            .filter { $0.missingItems.count < cart.count }   // need at least one known price
            .sorted {
                if $0.missingItems.count != $1.missingItems.count { return $0.missingItems.count < $1.missingItems.count }
                return $0.total < $1.total
            }
    }

    // MARK: Saving

    private func save() {
        guard isLoaded else { return }
        let snapshot = SavedData(cart: cart, priceReports: priceReports,
                                 knownProducts: knownProducts, monthlyBenefit: monthlyBenefit)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Snapshot: couldn't save local data: \(error)")
        }
    }

    private func load() {
        defer { isLoaded = true }
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SavedData.self, from: data) else { return }
        cart = saved.cart
        priceReports = saved.priceReports
        knownProducts = saved.knownProducts
        monthlyBenefit = saved.monthlyBenefit
    }
}
