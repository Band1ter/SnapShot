import Foundation

/// Estimates a price when a store has no real price for an item, using the real prices collected from
/// store websites. Estimates are always labeled as estimates in the app and are never saved as real prices.
///
/// How an estimate is made, most specific first:
///  1. The same item's real prices at other stores, adjusted for how expensive this store is overall.
///  2. The typical price of the closest staple (e.g. "peanut butter") across stores, adjusted the same way.
///  3. The typical price of the item's food category, adjusted the same way.
final class PriceEstimator {
    static let shared = PriceEstimator()

    struct Estimate {
        let price: Double
        let unit: String?
        let basis: String
    }

    private let db = StorePriceDatabase.shared
    /// How expensive each store is compared with the area's typical price (1.0 = typical, 0.8 = 20% cheaper).
    let storeIndex: [String: Double]
    /// Typical (median) price per staple, normalized to an average store, for items priced "each".
    private let termPrice: [String: Double]
    /// Typical price per staple sold by weight, e.g. bananas → 0.59 per lb.
    private let termWeightPrice: [String: (price: Double, unit: String)]
    /// Typical price per food category.
    private let categoryPrice: [FoodCategory: Double]
    private let termTokens: [String: Set<String>]

    /// Warehouse clubs sell bulk sizes, so their prices would distort estimates for regular package sizes.
    static let bulkStores: Set<String> = ["BJ's Wholesale Club"]

    private init() {
        let stores = StorePriceDatabase.shared.stores.filter { !Self.bulkStores.contains($0.key) }

        // 1. Store price levels: compare each store's median price per staple with the cross-store median.
        var perTermStoreMedian: [String: [String: Double]] = [:]   // term -> store -> median
        for (store, items) in stores {
            let byTerm = Dictionary(grouping: items.filter { $0.u == nil }, by: \.t)
            for (term, termItems) in byTerm {
                perTermStoreMedian[term, default: [:]][store] = Self.median(termItems.map(\.p))
            }
        }
        var ratios: [String: [Double]] = [:]
        for (_, storeMedians) in perTermStoreMedian where storeMedians.count >= 3 {
            let mid = Self.median(Array(storeMedians.values))
            guard mid > 0 else { continue }
            for (store, value) in storeMedians { ratios[store, default: []].append(value / mid) }
        }
        var index: [String: Double] = [:]
        for (store, list) in ratios where list.count >= 10 {
            index[store] = min(max(Self.median(list), 0.5), 2.0)
        }
        storeIndex = index

        // 2. Typical price per staple, with each store's price level removed.
        var tPrice: [String: Double] = [:]
        for (term, storeMedians) in perTermStoreMedian {
            let normalized = storeMedians.map { $0.value / (index[$0.key] ?? 1) }
            tPrice[term] = Self.median(normalized)
        }
        termPrice = tPrice

        var weight: [String: (Double, String)] = [:]
        let weighed = stores.flatMap { store, items in items.filter { $0.u != nil }.map { (store, $0) } }
        for (term, list) in Dictionary(grouping: weighed, by: { $0.1.t }) {
            let unit = list.first!.1.u!
            let same = list.filter { $0.1.u == unit }
            weight[term] = (Self.median(same.map { $0.1.p / (index[$0.0] ?? 1) }), unit)
        }
        termWeightPrice = weight.mapValues { (price: $0.0, unit: $0.1) }

        // 3. Typical price per food category, from the staples that belong to it.
        var catPrices: [FoodCategory: [Double]] = [:]
        var tokensByTerm: [String: Set<String>] = [:]
        for (term, price) in tPrice {
            let words = Set(EligibilityEngine.normalize(term).split(separator: " ").map(String.init))
            catPrices[EligibilityEngine.foodCategory(tags: [], words: words), default: []].append(price)
            tokensByTerm[term] = StorePriceDatabase.tokens(term)
        }
        categoryPrice = catPrices.mapValues(Self.median)
        termTokens = tokensByTerm
    }

    var isAvailable: Bool { !termPrice.isEmpty }

    /// Estimated price at `store`, given the real prices already known for this product (store -> price).
    func estimate(for product: SNAPProduct, at store: String, knownPrices: [String: PriceReport]) -> Estimate? {
        guard isAvailable, !Self.bulkStores.contains(store) else { return nil }
        let level = storeIndex[store] ?? 1.0
        let levelNote = storeIndex[store] == nil ? "" : levelDescription(level)

        // 1. Same item at other stores (only items priced the same way, i.e. not per-lb mixed with each).
        let others = knownPrices.values.filter {
            $0.storeName != store && $0.source != .estimate && !Self.bulkStores.contains($0.storeName)
        }
        if !others.isEmpty {
            let units = Set(others.map { $0.unit ?? "" })
            if units.count == 1 {
                let base = Self.median(others.map { $0.price / (storeIndex[$0.storeName] ?? 1) })
                let n = others.count
                return Estimate(price: Self.round(base * level), unit: others.first?.unit,
                                basis: "Estimated from this item's price at \(n) other store\(n == 1 ? "" : "s")\(levelNote)")
            }
        }

        // 2. Closest staple.
        if let term = closestTerm(to: product) {
            // Produce and meat are usually sold by weight; prefer the per-pound price when there is one.
            if let byWeight = termWeightPrice[term] {
                return Estimate(price: Self.round(byWeight.price * level), unit: byWeight.unit,
                                basis: "Estimated from typical \(term) prices in the area\(levelNote)")
            }
            if let typical = termPrice[term] {
                return Estimate(price: Self.round(typical * level), unit: nil,
                                basis: "Estimated from typical \(term) prices in the area\(levelNote)")
            }
        }

        // 3. Food category.
        if let typical = categoryPrice[product.category] {
            return Estimate(price: Self.round(typical * level), unit: nil,
                            basis: "Estimated from typical \(product.category.rawValue.lowercased()) prices\(levelNote)")
        }
        return nil
    }

    private func levelDescription(_ level: Double) -> String {
        let pct = Int(((level - 1) * 100).rounded())
        if abs(pct) < 3 { return " (this store's prices are about average)" }
        return pct < 0 ? " (this store is about \(-pct)% cheaper than average)"
                       : " (this store is about \(pct)% pricier than average)"
    }

    /// The staple whose words best appear in the product name, e.g. "Jif Creamy Peanut Butter" → "peanut butter".
    private func closestTerm(to product: SNAPProduct) -> String? {
        let words = StorePriceDatabase.tokens(product.name)
        guard !words.isEmpty else { return nil }
        var best: (term: String, score: Double)?
        for (term, tTokens) in termTokens where !tTokens.isEmpty {
            let overlap = tTokens.intersection(words).count
            guard overlap == tTokens.count else { continue }   // every word of the staple must be in the name
            let score = Double(overlap) + Double(overlap) / Double(words.count)
            if best == nil || score > best!.score { best = (term, score) }
        }
        return best?.term
    }

    private static func median(_ values: [Double]) -> Double {
        let s = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    private static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
