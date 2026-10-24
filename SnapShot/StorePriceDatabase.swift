import Foundation

/// Prices collected from the stores' own online storefronts (via Instacart, priced for ZIP 08902)
/// and shipped inside the app as store_prices.json. Re-run the collection script to refresh them.
///
/// The website catalogs don't include barcodes, so a product is matched to each store's closest item
/// by name. The matched item's exact name and size are always shown, so the shopper can judge the match.
final class StorePriceDatabase {
    static let shared = StorePriceDatabase()

    struct Item: Codable, Hashable {
        let t: String          // staple search term the item was found under, e.g. "whole milk"
        let n: String          // item name on the store's website
        let s: String          // package size, e.g. "1 gal"
        let p: Double          // current price
        let r: Double?         // regular price when the item is on sale
        let u: String?         // pricing unit when it isn't "each", e.g. "lb"
        let rank: Int          // position in the store's search results (0 = best match)
    }

    private struct FileFormat: Codable {
        let collectedAt: String
        let postalCode: String
        let source: String
        let stores: [String: [Item]]
    }

    struct Match {
        let store: String
        let item: Item
        let score: Double
    }

    let collectedAt: Date?
    let postalCode: String
    let source: String
    let stores: [String: [Item]]
    let terms: [String]
    private let tokenCache: [String: Set<String>]   // item name -> tokens

    var isLoaded: Bool { !stores.isEmpty }

    private init() {
        guard let url = Bundle.main.url(forResource: "store_prices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(FileFormat.self, from: data) else {
            collectedAt = nil; postalCode = ""; source = ""; stores = [:]; terms = []; tokenCache = [:]
            return
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        collectedAt = iso.date(from: file.collectedAt) ?? ISO8601DateFormatter().date(from: file.collectedAt)
        postalCode = file.postalCode
        source = file.source
        stores = file.stores

        var cache: [String: Set<String>] = [:]
        var allTerms = Set<String>()
        for items in file.stores.values {
            for item in items {
                allTerms.insert(item.t)
                if cache[item.n] == nil { cache[item.n] = Self.tokens(item.n) }
            }
        }
        tokenCache = cache
        terms = allTerms.sorted()
    }

    // MARK: Matching a product to store items

    /// Best-matching item at each store for a product, or nothing for stores without a close enough match.
    func matches(for product: SNAPProduct) -> [String: Match] {
        let key = product.id + "|" + product.name
        if let cached = matchCache[key] { return cached }
        let result = computeMatches(for: product)
        matchCache[key] = result
        return result
    }

    private var matchCache: [String: [String: Match]] = [:]

    private func computeMatches(for product: SNAPProduct) -> [String: Match] {
        let brandTokens = product.brand.map(Self.tokens) ?? []
        // Match on what the item is, not who makes it, so store brands can match name brands.
        let allWords = Self.tokens(product.name)
        let withoutBrand = allWords.subtracting(brandTokens)
        let wanted = withoutBrand.isEmpty ? allWords : withoutBrand
        guard !wanted.isEmpty else { return [:] }

        var result: [String: Match] = [:]
        for (store, items) in stores {
            var best: Match?
            for item in items {
                let have = tokenCache[item.n] ?? Self.tokens(item.n)
                let overlap = wanted.intersection(have).count
                guard overlap > 0 else { continue }
                let coverage = Double(overlap) / Double(wanted.count)     // how much of the product name is found
                let precision = Double(overlap) / Double(max(have.count, 1)) // how little extra the item has
                // Names with 3+ key words must match at least 3 of every 4 (so "black beans" won't match "pinto beans").
                let neededCoverage = wanted.count >= 3 ? 0.75 : 0.5
                guard overlap >= min(2, wanted.count), coverage >= neededCoverage, precision >= 0.4 else { continue }
                var score = 0.65 * coverage + 0.35 * precision
                if !brandTokens.isEmpty, !brandTokens.isDisjoint(with: have) { score += 0.1 }
                if let current = best {
                    if score > current.score + 0.001 || (abs(score - current.score) <= 0.001 && item.p < current.item.p) {
                        best = Match(store: store, item: item, score: score)
                    }
                } else {
                    best = Match(store: store, item: item, score: score)
                }
            }
            if let best, best.score >= 0.55 { result[store] = best }
        }
        return result
    }

    // MARK: Staple comparison

    /// For one staple (e.g. "eggs"), each store's matching items, cheapest first; stores ordered by their cheapest item.
    func items(forTerm term: String) -> [(store: String, items: [Item])] {
        stores
            .map { (store: $0.key, items: $0.value.filter { $0.t == term }.sorted { $0.p < $1.p }) }
            .filter { !$0.items.isEmpty }
            .sorted { ($0.items.first?.p ?? .infinity) < ($1.items.first?.p ?? .infinity) }
    }

    // MARK: Text helpers

    private static let stopwords: Set<String> = [
        "the", "and", "with", "of", "a", "an", "for", "in", "to", "or", "by", "from", "style", "brand",
        "oz", "fl", "lb", "lbs", "ct", "count", "pk", "pack", "gal", "gallon", "qt", "pt", "ml", "l", "g", "kg",
        "each", "ea", "size", "value", "family", "original", "classic", "new", "fresh", "premium", "iu", "mg"
    ]

    /// Lowercased words without punctuation, numbers, units or filler, with simple plurals removed.
    static func tokens(_ text: String) -> Set<String> {
        let cleaned = String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
        var out = Set<String>()
        for raw in cleaned.split(separator: " ") {
            var w = String(raw)
            if w.count < 2 || w.allSatisfy(\.isNumber) || stopwords.contains(w) { continue }
            if w.first!.isNumber { continue }   // "12oz", "2pk"
            if w.count > 4, w.hasSuffix("oes") || w.hasSuffix("ches") || w.hasSuffix("shes") {
                w.removeLast(2)
            } else if w.count > 3, w.hasSuffix("ies") {
                w.removeLast(3); w += "y"
            } else if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") {
                w.removeLast()
            }
            out.insert(w)
        }
        return out
    }

    static func priceText(_ item: Item) -> String {
        let price = item.p.formatted(.currency(code: "USD"))
        if let unit = item.u, !unit.isEmpty, unit.lowercased() != "each", unit != item.s {
            return "\(price) / \(unit)"
        }
        return price
    }
}
