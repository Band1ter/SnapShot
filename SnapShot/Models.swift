import SwiftUI

// MARK: - Theme

enum Theme {
    static let green = Color(red: 0.08, green: 0.55, blue: 0.30)
    static let orange = Color(red: 0.90, green: 0.50, blue: 0.10)
    static let red = Color(red: 0.85, green: 0.20, blue: 0.20)
}

extension Font {
    /// Rounded system font that still grows and shrinks with the user's text-size (Dynamic Type) setting.
    static func rounded(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

// MARK: - Eligibility

enum SNAPEligibility: String, Codable, Hashable {
    case eligible = "Eligible"
    case notEligible = "Not eligible"
    case checkAtStore = "Check at store"

    var color: Color {
        switch self {
        case .eligible: return Theme.green
        case .notEligible: return Theme.red
        case .checkAtStore: return Theme.orange
        }
    }

    var icon: String {
        switch self {
        case .eligible: return "checkmark.seal.fill"
        case .notEligible: return "xmark.octagon.fill"
        case .checkAtStore: return "questionmark.circle.fill"
        }
    }
}

/// Where an eligibility answer came from, shown to the user so they know how much to trust it.
enum EligibilityBasis: String, Codable, Hashable {
    case retailerFlag = "Marked by the retailer"
    case federalRule = "Based on federal SNAP rules"
    case insufficientData = "Not enough product information"
}

// MARK: - Categories

enum FoodCategory: String, CaseIterable, Identifiable, Codable {
    case all = "All Items"
    case produce = "Fruits & Veggies"
    case meatSeafood = "Meat & Seafood"
    case dairy = "Dairy & Alternatives"
    case bakeryGrains = "Bakery & Grains"
    case beverages = "Beverages"
    case frozen = "Frozen Foods"
    case snacksStaples = "Snacks & Staples"
    case seedsPlants = "Seeds & Plants"
    case prohibited = "Not Eligible"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .produce: return "carrot.fill"
        case .meatSeafood: return "fish.fill"
        case .dairy: return "cup.and.saucer.fill"
        case .bakeryGrains: return "basket.fill"
        case .beverages: return "mug.fill"
        case .frozen: return "snowflake"
        case .snacksStaples: return "bag.fill"
        case .seedsPlants: return "leaf.fill"
        case .prohibited: return "xmark.octagon.fill"
        }
    }

    /// Open Food Facts category tag used when browsing this category.
    /// Sent as a real category filter, not as search words.
    var offCategoryTag: String? {
        switch self {
        case .all: return nil
        case .produce: return "fruits-and-vegetables-based-foods"
        case .meatSeafood: return "meats"
        case .dairy: return "dairies"
        case .bakeryGrains: return "breads"
        case .beverages: return "beverages"
        case .frozen: return "frozen-foods"
        case .snacksStaples: return "snacks"
        case .seedsPlants: return "seeds"
        case .prohibited: return "alcoholic-beverages"
        }
    }
}

// MARK: - Products

struct SNAPProduct: Identifiable, Codable, Hashable {
    let id: String              // the barcode
    let barcode: String?
    var name: String
    let brand: String?
    let packageSize: String?
    let category: FoodCategory
    var eligibility: SNAPEligibility
    var basis: EligibilityBasis
    var reason: String
    var alternative: String?
    let imageURL: String?
}

// MARK: - Prices

enum PriceSource: String, Codable {
    case walmartAPI = "Walmart.com (live)"
    case shopperReported = "Entered by you"
    case storeWebsite = "Store website"
    case estimate = "Estimate"
}

/// One observed price for one product at one store. Only real prices are stored; nothing is estimated.
struct PriceReport: Identifiable, Codable, Hashable {
    var id = UUID()
    let productID: String
    let storeName: String
    let price: Double
    let source: PriceSource
    let date: Date
    /// For website prices: the store's own item name and size that was matched to this product.
    var matchedName: String? = nil
    /// For website prices sold by weight: the unit, e.g. "lb".
    var unit: String? = nil

    var isEstimate: Bool { source == .estimate }

    var priceText: String {
        let text = (isEstimate ? "≈ " : "") + price.formatted(.currency(code: "USD"))
        if let unit, !unit.isEmpty { return "\(text) / \(unit)" }
        return text
    }
}

struct CartItem: Identifiable, Codable, Hashable {
    var id: String { product.id }
    var product: SNAPProduct
    var quantity: Int
}

// MARK: - Stores

struct SNAPStore: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let address: String
    let distance: String
    let acceptsSNAPInStore: Bool
    let acceptsOnlineEBT: Bool
    let hasMatching: Bool
}

let walmartStoreName = "Walmart Supercenter"

// TODO before submission: confirm each store against the USDA SNAP Retailer Locator
// (https://usda-fns.maps.arcgis.com/apps/webappviewer/index.html?id=15e1c457b56c4a729861d015cd626a23)
// and confirm each address is inside the 12th District.
let nj12Stores: [SNAPStore] = [
    SNAPStore(id: "s1", name: walmartStoreName, address: "979 Route 1, North Brunswick, NJ", distance: "0.8 mi", acceptsSNAPInStore: true, acceptsOnlineEBT: true, hasMatching: false),
    SNAPStore(id: "s2", name: "ALDI", address: "239 North Ave, Edison, NJ", distance: "2.1 mi", acceptsSNAPInStore: true, acceptsOnlineEBT: true, hasMatching: false),
    SNAPStore(id: "s3", name: "ShopRite of New Brunswick", address: "432 Remsen Ave, New Brunswick, NJ", distance: "1.4 mi", acceptsSNAPInStore: true, acceptsOnlineEBT: true, hasMatching: false),
    SNAPStore(id: "s4", name: "BJ's Wholesale Club", address: "26 Modern Way, Milltown, NJ", distance: "2.8 mi", acceptsSNAPInStore: true, acceptsOnlineEBT: true, hasMatching: false),
    SNAPStore(id: "s5", name: "Stop & Shop", address: "940 Easton Ave, Somerset, NJ", distance: "3.2 mi", acceptsSNAPInStore: true, acceptsOnlineEBT: true, hasMatching: false),
    SNAPStore(id: "s6", name: "Trader Joe's", address: "4228 US-1, Princeton, NJ", distance: "4.5 mi", acceptsSNAPInStore: true, acceptsOnlineEBT: false, hasMatching: false),
    SNAPStore(id: "s7", name: "New Brunswick Farmers Market", address: "178 Jones Ave, New Brunswick, NJ", distance: "1.6 mi", acceptsSNAPInStore: true, acceptsOnlineEBT: true, hasMatching: true),
    SNAPStore(id: "s8", name: "CVS Pharmacy", address: "949 Livingston Ave, North Brunswick, NJ", distance: "0.4 mi", acceptsSNAPInStore: true, acceptsOnlineEBT: false, hasMatching: false),
    SNAPStore(id: "s9", name: "Walgreens", address: "2703 US Highway 130, North Brunswick, NJ", distance: "1.2 mi", acceptsSNAPInStore: true, acceptsOnlineEBT: false, hasMatching: false)
]
