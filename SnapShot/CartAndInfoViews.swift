import SwiftUI

// MARK: - Trip cart

struct CartView: View {
    @EnvironmentObject private var appData: LocalStore

    var body: some View {
        NavigationStack {
            List {
                if appData.cart.isEmpty {
                    Section {
                        BenefitCard(balance: appData.monthlyBenefit, spent: nil)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "cart")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Theme.green)
                            Text("Your trip cart is empty")
                                .font(.rounded(.headline))
                            Text("Add items from Browse or Scan, and Snapshot will show what the whole trip costs at each store.")
                                .font(.rounded(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Theme.surface)
                    }
                } else {
                    let totals = appData.tripTotals()
                    let best = recommendedStore(totals)

                    Section {
                        BenefitCard(balance: appData.monthlyBenefit, spent: best?.total)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        tripSummary(best: best)
                        benefitEditor
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        ForEach(appData.cart) { item in
                            CartRow(item: item)
                        }
                        .onDelete { appData.removeFromCart(at: $0) }
                    } header: {
                        sectionHeader("In your cart (\(appData.cartCount))")
                    }
                    .listRowBackground(Theme.surface)

                    if !totals.isEmpty {
                        Section {
                            let maxTotal = totals.map(\.total).max() ?? 1
                            ForEach(totals) { total in
                                StoreTotalRow(total: total, isBest: total.store.id == best?.store.id,
                                              fraction: maxTotal > 0 ? total.total / maxTotal : 0)
                            }
                        } header: {
                            sectionHeader("Trip cost by store")
                        } footer: {
                            Text("Totals use real prices where they exist: each store's website price (closest matching item), live walmart.com prices, and prices you've entered. Where a store has no price, an estimate is used and counted below the total.")
                                .font(.rounded(.caption))
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .paperBackground()
            .navigationTitle("Trip Cart")
            .toolbar {
                if !appData.cart.isEmpty { EditButton() }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.rounded(.headline))
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    /// Recommend only stores where most prices are real, so a store priced mostly by estimates can't "win".
    private func recommendedStore(_ totals: [LocalStore.StoreTripTotal]) -> LocalStore.StoreTripTotal? {
        let mostlyReal = totals.filter { $0.isComplete && $0.estimatedItems.count * 2 <= appData.cart.count }
        return mostlyReal.min(by: { $0.total < $1.total }) ?? totals.first(where: \.isComplete)
    }

    @ViewBuilder
    private func tripSummary(best: LocalStore.StoreTripTotal?) -> some View {
        if let best {
            let left = appData.monthlyBenefit - best.total
            HStack(spacing: 12) {
                StoreAvatar(name: best.store.name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cheapest one-stop trip")
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                    Text(best.store.name)
                        .font(.rounded(.headline))
                }
                Spacer()
                Text(best.total, format: .currency(code: "USD"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.deepGreen)
            }
            .padding(.vertical, 4)
            if !best.estimatedItems.isEmpty {
                Label("Includes \(best.estimatedItems.count) estimated price\(best.estimatedItems.count == 1 ? "" : "s"), so the real total may differ.",
                      systemImage: "wand.and.stars")
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.orange)
            }
            if left < 0 {
                Label("This trip costs more than your benefit. The difference would need another payment method.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.red)
            }
        } else {
            Label("No single store has a price for every item yet. Open an item and tap a store to add the price you see, or check Compare Prices for similar staples.",
                  systemImage: "info.circle")
                .font(.rounded(.footnote))
                .foregroundStyle(.secondary)
        }

        let toCheck = appData.cart.filter { $0.product.eligibility == .checkAtStore }.count
        if toCheck > 0 {
            Label("\(toCheck) item\(toCheck == 1 ? "" : "s") should be confirmed at the register.",
                  systemImage: "questionmark.circle")
                .font(.rounded(.footnote))
                .foregroundStyle(Theme.orange)
        }
    }

    private var benefitEditor: some View {
        HStack {
            Label("Monthly benefit", systemImage: "creditcard")
                .font(.rounded(.subheadline))
            Spacer()
            TextField("Amount", value: $appData.monthlyBenefit, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.rounded(.subheadline, .semibold))
                .monospacedDigit()
                .frame(maxWidth: 130)
        }
    }
}

struct StoreTotalRow: View {
    let total: LocalStore.StoreTripTotal
    let isBest: Bool
    let fraction: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StoreAvatar(name: total.store.name, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(total.store.name).font(.rounded(.subheadline, .semibold))
                    if isBest {
                        Text("Best")
                            .font(.rounded(.caption2, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.green, in: Capsule())
                    }
                    Spacer()
                    Text(total.total, format: .currency(code: "USD"))
                        .font(.rounded(.subheadline, .bold))
                        .monospacedDigit()
                        .foregroundStyle(total.isComplete ? Theme.deepGreen : Color.secondary)
                }
                PriceBar(fraction: fraction, color: isBest ? Theme.green : Theme.green.opacity(0.4))
                if !total.isComplete {
                    Text("No price yet for: \(total.missingItems.joined(separator: ", "))")
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.orange)
                }
                if !total.estimatedItems.isEmpty {
                    Text("Includes \(total.estimatedItems.count) estimated price\(total.estimatedItems.count == 1 ? "" : "s")")
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CartRow: View {
    let item: CartItem
    @EnvironmentObject private var appData: LocalStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductThumbnail(url: item.product.imageURL, size: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.product.name)
                    .font(.rounded(.subheadline, .semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    EligibilityBadge(eligibility: item.product.eligibility)
                    if let cheapest = appData.cheapestPrice(for: item.product) {
                        Text("\(cheapest.isEstimate ? "est." : "lowest") \(cheapest.priceText) at \(cheapest.storeName)")
                            .font(.rounded(.caption))
                            .monospacedDigit()
                            .foregroundStyle(cheapest.isEstimate ? Theme.orange : .secondary)
                            .lineLimit(1)
                    } else {
                        Text("No prices yet")
                            .font(.rounded(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: Binding(
                    get: { item.quantity },
                    set: { appData.setQuantity($0, for: item.id) }
                ), in: 1...20) {
                    Text("Qty \(item.quantity)")
                        .font(.rounded(.subheadline, .medium))
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Store directory

struct StoreDirectoryView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(nj12Stores) { store in
                        HStack(alignment: .top, spacing: 14) {
                            StoreAvatar(name: store.name, size: 44)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(store.name).font(.rounded(.body, .semibold))
                                    Spacer()
                                    Text(store.distance)
                                        .font(.rounded(.caption, .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Text(store.address).font(.rounded(.caption)).foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    if store.acceptsSNAPInStore { chip("SNAP in store", "creditcard.fill", Theme.green) }
                                    if store.acceptsOnlineEBT { chip("Online EBT", "cart.fill", Theme.deepGreen) }
                                    if store.hasMatching { chip("SNAP Match", "star.fill", Theme.orange) }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } footer: {
                    Text("Every store listed accepts SNAP EBT at the register.")
                        .font(.rounded(.caption))
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped)
            .paperBackground()
            .navigationTitle("Stores near you")
        }
    }

    private func chip(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.rounded(.caption2, .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - SNAP rules and data sources

struct GuideView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    rule("Fruits and vegetables: fresh, frozen, or canned", "carrot.fill")
                    rule("Meat, poultry, and fish", "fish.fill")
                    rule("Milk, cheese, yogurt, and other dairy", "cup.and.saucer.fill")
                    rule("Bread, cereal, rice, and pasta", "basket.fill")
                    rule("Snacks and non-alcoholic drinks", "mug.fill")
                    rule("Seeds and plants that grow food", "leaf.fill")
                } header: {
                    header("SNAP can buy", "checkmark.seal.fill", Theme.green)
                }
                .listRowBackground(Theme.surface)

                Section {
                    rule("Alcohol and tobacco", "xmark", Theme.red)
                    rule("Vitamins, medicine, and supplements (anything with a Supplement Facts label)", "xmark", Theme.red)
                    rule("Food that is hot when you buy it", "xmark", Theme.red)
                    rule("Food eaten in the store", "xmark", Theme.red)
                    rule("Live animals (except shellfish, fish removed from water, and animals slaughtered before pickup)", "xmark", Theme.red)
                    rule("Pet food, cleaning supplies, paper products, hygiene items, and cosmetics", "xmark", Theme.red)
                } header: {
                    header("SNAP can't buy", "xmark.octagon.fill", Theme.red)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Text("The answer depends on the package. For example, an energy drink with a Nutrition Facts label is eligible, but one with a Supplement Facts label is not.")
                        .font(.rounded(.subheadline))
                } header: {
                    header("When Snapshot says “Check at store”", "questionmark.circle.fill", Theme.orange)
                }
                .listRowBackground(Theme.surface)

                Section {
                    source("Products", "Names, photos, and categories come from Open Food Facts, a free public food database.")
                    source("Eligibility", "The federal SNAP rules above, applied to each product's category. If a retailer marks an item itself, Snapshot uses the retailer's label.")
                    source("Store prices", "Collected from the ALDI, ShopRite, Stop & Shop, BJ's, CVS, and Walgreens online stores (through Instacart) for ZIP 08902, with the collection date shown. Online prices can be higher than shelf prices.")
                    source("Walmart prices", "Live from walmart.com. In-store prices can differ.")
                    source("Your prices", "Prices you enter from the shelf tag are saved only on this phone with the date, and replace the website price for that store.")
                    source("Estimates (≈)", "When a store has no price for an item, Snapshot estimates one from the item's real prices at other stores, or typical prices for similar items, adjusted for how expensive that store usually is. Estimates are never shown as real prices.")
                } header: {
                    header("Where Snapshot's information comes from", "info.circle.fill", Theme.deepGreen)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Link(destination: URL(string: "https://www.fns.usda.gov/snap/eligible-food-items")!) {
                        Label("USDA: What can SNAP buy?", systemImage: "safari")
                            .font(.rounded(.subheadline, .semibold))
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped)
            .paperBackground()
            .navigationTitle("SNAP Rules")
        }
    }

    private func header(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.rounded(.headline))
            .foregroundStyle(color)
            .textCase(nil)
    }

    private func rule(_ text: String, _ icon: String, _ color: Color = Theme.green) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text).font(.rounded(.subheadline))
        }
    }

    private func source(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.rounded(.subheadline, .semibold))
            Text(text).font(.rounded(.caption)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
