import SwiftUI

// MARK: - Palette (same greens and orange as before, plus tints; all adapt to dark mode)

extension Theme {
    /// Darker leaf green for the benefit card and headings.
    static let deepGreen = Color(light: rgb(0.04, 0.32, 0.19), dark: rgb(0.06, 0.36, 0.22))
    /// Soft green tint behind photos, chips and banners.
    static let mint = Color(light: rgb(0.91, 0.96, 0.93), dark: rgb(0.10, 0.20, 0.15))
    /// Screen background: a cool, faintly green off-white.
    static let paper = Color(light: rgb(0.965, 0.975, 0.965), dark: rgb(0.06, 0.07, 0.065))
    /// Surfaces that sit on the paper background.
    static let surface = Color(light: .white, dark: rgb(0.12, 0.13, 0.125))
    static let orangeTint = Color(light: rgb(0.99, 0.94, 0.88), dark: rgb(0.25, 0.16, 0.07))
    static let redTint = Color(light: rgb(0.99, 0.91, 0.91), dark: rgb(0.26, 0.09, 0.09))
}

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
    UIColor(red: r, green: g, blue: b, alpha: 1)
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension SNAPEligibility {
    var tint: Color {
        switch self {
        case .eligible: return Theme.mint
        case .notEligible: return Theme.redTint
        case .checkAtStore: return Theme.orangeTint
        }
    }

    var headline: String {
        switch self {
        case .eligible: return "You can buy this with SNAP"
        case .notEligible: return "SNAP doesn't cover this"
        case .checkAtStore: return "Check this one at the register"
        }
    }
}

// MARK: - Screen styling

extension View {
    /// Paper background behind lists and scroll views.
    func paperBackground() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.paper.ignoresSafeArea())
    }

    /// A white rounded surface for grouped content.
    func surfaceCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Benefit card (the app's signature element: looks like an EBT card)

struct BenefitCard: View {
    let balance: Double
    let spent: Double?
    var compact = false

    private var remaining: Double { balance - (spent ?? 0) }
    private var usedFraction: Double {
        guard balance > 0, let spent else { return 0 }
        return min(max(spent / balance, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            HStack(alignment: .top) {
                Text("SNAP benefit")
                    .font(.rounded(.subheadline, .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                // A small "card chip" so it reads as a benefits card.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.83, blue: 0.52), Color(red: 0.83, green: 0.68, blue: 0.36)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(remaining, format: .currency(code: "USD"))
                    .font(.system(compact ? .title : .largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(spent == nil ? "available this month" : "left after this trip")
                    .font(.rounded(.footnote))
                    .foregroundStyle(.white.opacity(0.8))
            }

            if let spent, !compact {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.2))
                            Capsule()
                                .fill(remaining < 0 ? Theme.orange : .white)
                                .frame(width: max(geo.size.width * usedFraction, 6))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("Trip \(spent, format: .currency(code: "USD"))")
                        Spacer()
                        Text("of \(balance, format: .currency(code: "USD"))")
                    }
                    .font(.rounded(.caption, .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(compact ? 16 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .bottomTrailing) {
                Theme.deepGreen
                // Faint leaf mark in the corner, like a card's printed pattern.
                Image(systemName: "leaf.fill")
                    .font(.system(size: compact ? 90 : 130))
                    .foregroundStyle(.white.opacity(0.06))
                    .rotationEffect(.degrees(-20))
                    .offset(x: 20, y: 30)
                    .accessibilityHidden(true)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.deepGreen.opacity(0.25), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Store avatar (colored initials stand in for store logos)

struct StoreAvatar: View {
    let name: String
    var size: CGFloat = 36

    private var initials: String {
        let skip: Set<String> = ["of", "the", "&", "new"]
        let words = name.split(separator: " ").map(String.init).filter { !skip.contains($0.lowercased()) }
        let letters = words.prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    /// Each store keeps the same color everywhere in the app.
    private var color: Color {
        let palette: [Color] = [
            Theme.green, Theme.deepGreen, Theme.orange,
            Color(red: 0.20, green: 0.45, blue: 0.70), Color(red: 0.55, green: 0.30, blue: 0.60),
            Color(red: 0.70, green: 0.25, blue: 0.30), Color(red: 0.25, green: 0.55, blue: 0.55)
        ]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Category tile

struct CategoryTile: View {
    let category: FoodCategory
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: category.iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSelected ? .white : tileColor)
                .frame(width: 56, height: 56)
                .background(isSelected ? tileColor : tileColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(category.shortName)
                .font(.rounded(.caption, isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Theme.deepGreen : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var tileColor: Color {
        category == .prohibited ? Theme.red : (category == .all ? Theme.deepGreen : Theme.green)
    }
}

extension FoodCategory {
    var shortName: String {
        switch self {
        case .all: return "Everything"
        case .produce: return "Fruits & veggies"
        case .meatSeafood: return "Meat & fish"
        case .dairy: return "Dairy"
        case .bakeryGrains: return "Bread & grains"
        case .beverages: return "Drinks"
        case .frozen: return "Frozen"
        case .snacksStaples: return "Snacks & pantry"
        case .seedsPlants: return "Seeds & plants"
        case .prohibited: return "Not covered"
        }
    }
}

// MARK: - Price bar (shows how a price compares with the others on the same screen)

struct PriceBar: View {
    let fraction: Double      // 0…1 of the most expensive price shown
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.06))
                Capsule().fill(color).frame(width: max(geo.size.width * fraction, 4))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
