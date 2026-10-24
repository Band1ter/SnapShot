import Foundation

// MARK: - Open Food Facts (product names, categories, photos)

enum OFFError: LocalizedError {
    case badResponse(Int)
    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "The product database returned an error (\(code))."
        }
    }
}

struct OpenFoodFactsService {
    static let userAgent = "Snapshot/1.0 (iOS; Congressional App Challenge)"
    private static let fields = "code,product_name,product_name_en,brands,quantity,categories_tags,image_front_small_url,nutriments"

    /// Text and/or category search, limited to products sold in the United States.
    /// Uses Open Food Facts' newer search service (search.openfoodfacts.org) first, because the old
    /// cgi/search.pl endpoint often answers 503 when it's busy. Falls back to the old endpoint if needed.
    func search(text: String, category: FoodCategory) async throws -> [SNAPProduct] {
        do {
            return try await searchNewService(text: text, category: category)
        } catch {
            if Task.isCancelled { throw error }   // a newer search replaced this one
            print("Snapshot: new search service failed (\(error)); trying the old endpoint")
            return try await searchLegacy(text: text, category: category)
        }
    }

    private func searchNewService(text: String, category: FoodCategory) async throws -> [SNAPProduct] {
        var clauses: [String] = []
        let cleaned = text.replacingOccurrences(of: "\"", with: " ").trimmingCharacters(in: .whitespaces)
        if !cleaned.isEmpty { clauses.append(cleaned) }
        clauses.append("countries_tags:\"en:united-states\"")
        if let tag = category.offCategoryTag {
            clauses.append("categories_tags:\"en:\(tag)\"")
        }

        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: clauses.joined(separator: " ")),
            URLQueryItem(name: "page_size", value: "40"),
            URLQueryItem(name: "langs", value: "en"),
            URLQueryItem(name: "fields", value: Self.fields)
        ]

        let json = try await fetchJSON(components.url!)
        let raw = (json["hits"] as? [[String: Any]]) ?? (json["products"] as? [[String: Any]]) ?? []
        return Self.uniqueProducts(from: raw)
    }

    private func searchLegacy(text: String, category: FoodCategory) async throws -> [SNAPProduct] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        var items = [
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "40"),
            URLQueryItem(name: "fields", value: Self.fields),
            URLQueryItem(name: "tagtype_0", value: "countries"),
            URLQueryItem(name: "tag_contains_0", value: "contains"),
            URLQueryItem(name: "tag_0", value: "united-states")
        ]
        if !text.isEmpty {
            items.append(URLQueryItem(name: "search_terms", value: text))
        }
        if let tag = category.offCategoryTag {
            items.append(URLQueryItem(name: "tagtype_1", value: "categories"))
            items.append(URLQueryItem(name: "tag_contains_1", value: "contains"))
            items.append(URLQueryItem(name: "tag_1", value: tag))
        }
        components.queryItems = items

        let json = try await fetchJSON(components.url!)
        return Self.uniqueProducts(from: json["products"] as? [[String: Any]] ?? [])
    }

    private static func uniqueProducts(from raw: [[String: Any]]) -> [SNAPProduct] {
        var seen = Set<String>()
        return raw
            .compactMap { makeProduct(from: $0, requireName: true) }
            .filter { seen.insert($0.id).inserted }
    }

    /// Looks up one product by barcode. Returns nil if the database doesn't have it.
    func product(barcode: String) async throws -> SNAPProduct? {
        guard !barcode.isEmpty, barcode.allSatisfy(\.isNumber) else { return nil }
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode)?fields=\(Self.fields)")!
        let json = try await fetchJSON(url, allowNotFound: true)
        guard (json["status"] as? Int) == 1, var dict = json["product"] as? [String: Any] else { return nil }
        if (dict["code"] as? String)?.isEmpty ?? true { dict["code"] = barcode }
        return Self.makeProduct(from: dict, requireName: false)
    }

    /// Stand-in for a scanned barcode the database doesn't know yet.
    static func unknownProduct(barcode: String) -> SNAPProduct {
        SNAPProduct(
            id: barcode, barcode: barcode, name: "Unknown item (\(barcode))", brand: nil, packageSize: nil,
            category: .snacksStaples, eligibility: .checkAtStore, basis: .insufficientData,
            reason: "This barcode isn't in the Open Food Facts database yet. Most packaged foods with a Nutrition Facts label are SNAP-eligible; items with a Supplement Facts label are not.",
            alternative: nil, imageURL: nil)
    }

    private func fetchJSON(_ url: URL, allowNotFound: Bool = false) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 && allowNotFound { return [:] }
        guard (200..<300).contains(status) else { throw OFFError.badResponse(status) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OFFError.badResponse(status)
        }
        return object
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        if let list = value as? [Any] { return list.lazy.compactMap { nonEmpty($0) }.first }
        if let perLanguage = value as? [String: Any] {
            return nonEmpty(perLanguage["en"]) ?? nonEmpty(perLanguage["main"]) ?? perLanguage.values.lazy.compactMap { nonEmpty($0) }.first
        }
        if let number = value as? NSNumber { return number.stringValue }
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    static func makeProduct(from d: [String: Any], requireName: Bool) -> SNAPProduct? {
        guard let code = nonEmpty(d["code"]) else { return nil }
        let foundName = nonEmpty(d["product_name_en"]) ?? nonEmpty(d["product_name"])
        if requireName && foundName == nil { return nil }
        let name = foundName ?? "Unnamed item (\(code))"

        let tags = d["categories_tags"] as? [String] ?? []
        let nutriments = d["nutriments"] as? [String: Any] ?? [:]
        let brand = nonEmpty(d["brands"]).flatMap { brands in
            brands.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        }

        let result = EligibilityEngine.classify(name: name, categoryTags: tags, hasNutritionData: !nutriments.isEmpty)
        return SNAPProduct(
            id: code, barcode: code, name: name, brand: brand, packageSize: nonEmpty(d["quantity"]),
            category: result.category, eligibility: result.eligibility, basis: result.basis,
            reason: result.reason, alternative: result.alternative,
            imageURL: nonEmpty(d["image_front_small_url"]))
    }
}

// MARK: - Spanish search support

enum SpanishTranslator {
    private static let words: [String: String] = [
        "leche": "milk", "pan": "bread", "manzana": "apple", "manzanas": "apples", "pollo": "chicken",
        "carne": "meat", "res": "beef", "cerdo": "pork", "pavo": "turkey", "queso": "cheese", "arroz": "rice",
        "frijoles": "beans", "agua": "water", "jugo": "juice", "pescado": "fish", "atun": "tuna", "atún": "tuna",
        "huevo": "egg", "huevos": "eggs", "fruta": "fruit", "frutas": "fruit", "verduras": "vegetables",
        "papas": "potatoes", "tomate": "tomato", "tomates": "tomatoes", "cebolla": "onion",
        "platano": "banana", "plátano": "banana", "platanos": "bananas", "plátanos": "bananas",
        "naranja": "orange", "naranjas": "oranges", "yogur": "yogurt", "mantequilla": "butter",
        "azucar": "sugar", "azúcar": "sugar", "harina": "flour", "aceite": "oil", "galletas": "cookies",
        "congelado": "frozen", "congelados": "frozen", "entera": "whole", "integral": "whole wheat",
        "sopa": "soup", "frijol": "beans", "maiz": "corn", "maíz": "corn"
    ]

    /// Translates word by word, so "leche entera" becomes "milk whole". Unknown words pass through.
    static func translate(_ text: String) -> String {
        text.split(separator: " ")
            .map { words[$0.lowercased()] ?? String($0) }
            .joined(separator: " ")
    }
}

// MARK: - Catalog view model

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published private(set) var results: [SNAPProduct] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasSearched = false
    @Published private(set) var statusMessage: String?

    private let service = OpenFoodFactsService()
    private var currentTask: Task<Void, Never>?
    private var lastKey: String?

    func search(text: String, category: FoodCategory) {
        let query = SpanishTranslator.translate(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let key = "\(query.lowercased())|\(category.rawValue)"

        // Skip repeat requests for the same search (Open Food Facts limits how often apps can search).
        if key == lastKey { return }
        lastKey = key
        currentTask?.cancel()

        guard !query.isEmpty || category != .all else {
            results = []
            hasSearched = false
            statusMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        statusMessage = nil
        currentTask = Task {
            do {
                let found = try await service.search(text: query, category: category)
                guard !Task.isCancelled else { return }
                results = found
                hasSearched = true
                statusMessage = found.isEmpty ? "No matches. Try a simpler word, or scan the barcode." : nil
            } catch {
                guard !Task.isCancelled else { return }
                print("Snapshot search error: \(error)")
                results = []
                hasSearched = true
                lastKey = nil   // allow retrying the same search
                statusMessage = "Couldn't reach the product database. Check your connection and try again."
            }
            isLoading = false
        }
    }
}
