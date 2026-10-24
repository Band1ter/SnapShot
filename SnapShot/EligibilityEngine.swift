import Foundation

struct EligibilityResult {
    let eligibility: SNAPEligibility
    let basis: EligibilityBasis
    let reason: String
    let alternative: String?
    let category: FoodCategory
}

/// Applies the general federal SNAP rules (https://www.fns.usda.gov/snap/eligible-food-items)
/// to a product's Open Food Facts category tags and name.
///
/// Matching is done on whole words and Open Food Facts category tags, not substrings,
/// so "root beer", "steak" (contains "tea") and "vitamin D milk" are classified correctly.
enum EligibilityEngine {

    static func classify(name: String, categoryTags: [String], hasNutritionData: Bool) -> EligibilityResult {
        let tags = Set(categoryTags.map { $0.lowercased() })
        let text = normalize(name)
        let padded = " \(text) "
        let words = Set(text.split(separator: " ").map(String.init))

        func hasTag(_ candidates: [String]) -> Bool { candidates.contains { tags.contains($0) } }
        func hasWord(_ candidates: [String]) -> Bool { candidates.contains { words.contains($0) } }
        func hasPhrase(_ candidates: [String]) -> Bool { candidates.contains { padded.contains(" \($0) ") } }

        func notEligible(_ reason: String, alternative: String? = nil) -> EligibilityResult {
            EligibilityResult(eligibility: .notEligible, basis: .federalRule, reason: reason,
                              alternative: alternative, category: .prohibited)
        }

        // 1. Alcohol
        let alcoholExempt = hasPhrase(["root beer", "ginger beer", "birch beer", "non alcoholic", "alcohol free",
                                       "cooking wine", "wine vinegar", "vinegar"])
            || hasTag(["en:non-alcoholic-beverages", "en:alcohol-free-beers", "en:non-alcoholic-beers"])
        if !alcoholExempt &&
            (hasTag(["en:alcoholic-beverages", "en:beers", "en:wines", "en:spirits", "en:hard-ciders"])
             || hasWord(["beer", "beers", "wine", "wines", "vodka", "whiskey", "whisky", "bourbon",
                         "tequila", "liquor", "liqueur", "lager"])
             || hasPhrase(["hard cider", "hard seltzer"])) {
            return notEligible("Alcoholic drinks can't be bought with SNAP.",
                               alternative: "Sparkling water or 100% juice")
        }

        // 2. Tobacco and nicotine
        if hasWord(["tobacco", "cigarette", "cigarettes", "cigar", "cigars", "vape", "nicotine"]) {
            return notEligible("Tobacco and nicotine products can't be bought with SNAP.")
        }

        // 3. Vitamins, supplements and medicine (anything with a Supplement Facts label)
        if hasTag(["en:dietary-supplements", "en:food-supplements", "en:vitamins", "en:protein-supplements"])
            || hasWord(["multivitamin", "multivitamins", "supplement", "supplements", "softgels", "capsules",
                        "ibuprofen", "acetaminophen", "antacid", "medicine"]) {
            return notEligible("Vitamins, supplements and medicine (anything with a Supplement Facts label) aren't eligible.",
                               alternative: "Fruits, vegetables, or 100% juice")
        }

        // 4. Pet food
        if hasTag(["en:pet-food", "en:dog-food", "en:cat-food", "en:pet-foods"])
            || hasPhrase(["dog food", "cat food", "pet food", "dog treats", "cat treats"]) {
            return notEligible("Pet food isn't eligible for SNAP.")
        }

        // 5. Household and personal-care items
        if hasWord(["detergent", "shampoo", "conditioner", "toothpaste", "deodorant", "diapers", "bleach", "lotion"])
            || hasPhrase(["paper towels", "toilet paper", "dish soap", "hand soap", "bar soap", "trash bags"]) {
            return notEligible("Household and personal-care items aren't food, so SNAP doesn't cover them.")
        }

        let category = foodCategory(tags: tags, words: words)

        // 6. Energy drinks: depends on which label is on the can
        if hasTag(["en:energy-drinks"]) || (words.contains("energy") && hasWord(["drink", "drinks", "shot", "shots"])) {
            return EligibilityResult(
                eligibility: .checkAtStore, basis: .federalRule,
                reason: "Energy drinks are eligible only if the can has a Nutrition Facts label. If it says “Supplement Facts,” it isn't eligible.",
                alternative: nil, category: category)
        }

        // 7. Foods that are often sold hot
        if hasPhrase(["rotisserie chicken", "hot food", "hot soup", "hot meal"]) {
            return EligibilityResult(
                eligibility: .checkAtStore, basis: .federalRule,
                reason: "Food that is hot when you buy it isn't eligible. The same item sold cold or frozen is.",
                alternative: "The chilled or frozen version", category: category)
        }

        // 8. Ordinary food for home preparation
        if !tags.isEmpty || hasNutritionData {
            return EligibilityResult(
                eligibility: .eligible, basis: .federalRule,
                reason: "Food meant to be prepared or eaten at home is SNAP-eligible.",
                alternative: nil, category: category)
        }

        // 9. Not enough information to decide
        return EligibilityResult(
            eligibility: .checkAtStore, basis: .insufficientData,
            reason: "We couldn't confirm what this item is. Most packaged foods with a Nutrition Facts label are eligible; items with a Supplement Facts label are not.",
            alternative: nil, category: category)
    }

    /// Lowercases and replaces punctuation with spaces: "Non-Alcoholic Ginger Beer!" -> "non alcoholic ginger beer"
    static func normalize(_ s: String) -> String {
        let mapped = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func foodCategory(tags: Set<String>, words: Set<String>) -> FoodCategory {
        func any(_ c: [String]) -> Bool { c.contains { tags.contains($0) } }

        if any(["en:frozen-foods"]) { return .frozen }
        if any(["en:beverages", "en:fruit-juices", "en:waters"]) { return .beverages }
        if any(["en:meats", "en:poultries", "en:seafood", "en:fishes", "en:meat-based-products"]) { return .meatSeafood }
        if any(["en:dairies", "en:milks", "en:cheeses", "en:yogurts", "en:milk-substitutes"]) { return .dairy }
        if any(["en:snacks", "en:sweet-snacks", "en:salty-snacks"]) { return .snacksStaples }
        if any(["en:fruits", "en:vegetables", "en:fruits-and-vegetables-based-foods", "en:fresh-vegetables", "en:fresh-fruits"]) { return .produce }
        if any(["en:breads", "en:cereals-and-their-products", "en:breakfast-cereals", "en:pastas", "en:rices"]) { return .bakeryGrains }
        if any(["en:seeds"]) { return .seedsPlants }

        // No category tags: fall back to whole words in the name.
        let w = words
        if !w.isDisjoint(with: ["apple", "apples", "banana", "bananas", "orange", "oranges", "lettuce", "carrots", "potatoes", "tomatoes"]) { return .produce }
        if !w.isDisjoint(with: ["chicken", "beef", "pork", "turkey", "fish", "salmon", "tuna", "shrimp", "steak"]) { return .meatSeafood }
        if !w.isDisjoint(with: ["milk", "cheese", "yogurt", "butter"]) { return .dairy }
        if !w.isDisjoint(with: ["bread", "rice", "pasta", "cereal", "tortillas", "bagels"]) { return .bakeryGrains }
        if !w.isDisjoint(with: ["water", "soda", "coffee", "tea", "juice"]) { return .beverages }
        return .snacksStaples
    }
}
