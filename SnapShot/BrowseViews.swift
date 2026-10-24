import SwiftUI

// MARK: - App root

struct ContentView: View {
    @StateObject private var appData = LocalStore()
    @StateObject private var catalog = CatalogViewModel()

    var body: some View {
        TabView {
            BrowseView()
                .tabItem { Label("Browse", systemImage: "basket.fill") }
            ScannerView()
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
            CartView()
                .tabItem { Label("Trip Cart", systemImage: "cart.fill") }
                .badge(appData.cartCount)
            StoreDirectoryView()
                .tabItem { Label("Stores", systemImage: "mappin.and.ellipse") }
            GuideView()
                .tabItem { Label("SNAP Rules", systemImage: "book.closed.fill") }
        }
        .tint(Theme.green)
        .environmentObject(appData)
        .environmentObject(catalog)
    }
}

// MARK: - Browse & search

enum EligibilityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case eligible = "Eligible"
    case notEligible = "Not eligible"
    case check = "Check"

    var id: String { rawValue }

    func matches(_ product: SNAPProduct) -> Bool {
        switch self {
        case .all: return true
        case .eligible: return product.eligibility == .eligible
        case .notEligible: return product.eligibility == .notEligible
        case .check: return product.eligibility == .checkAtStore
        }
    }
}

struct BrowseView: View {
    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var appData: LocalStore
    @State private var searchText = ""
    @State private var category: FoodCategory = .all
    @State private var filter: EligibilityFilter = .all

    /// Live results once the user has searched; otherwise items they've already opened.
    private var baseList: [SNAPProduct] {
        if catalog.hasSearched || catalog.isLoading { return catalog.results }
        return appData.knownProducts.values.sorted { $0.name < $1.name }
    }

    private var shown: [SNAPProduct] { baseList.filter(filter.matches) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !catalog.hasSearched && !catalog.isLoading {
                        header
                    }
                    categoryTiles
                    Picker("Eligibility", selection: $filter) {
                        ForEach(EligibilityFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let message = catalog.statusMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.rounded(.footnote))
                            .foregroundStyle(.secondary)
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Snapshot")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        StaplePricesView()
                    } label: {
                        Label("Compare Prices", systemImage: "chart.bar.xaxis")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search foods: milk, leche, cereal…")
            .onSubmit(of: .search) { catalog.search(text: searchText, category: category) }
            .task(id: searchText) {
                // Search automatically once the user pauses typing.
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.count >= 3 {
                    catalog.search(text: trimmed, category: category)
                }
            }
            .navigationDestination(for: SNAPProduct.self) { ProductDetailView(product: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you shopping for today?")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.deepGreen)
            BenefitCard(balance: appData.monthlyBenefit, spent: nil, compact: true)
        }
        .padding(.top, 4)
    }

    private var categoryTiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse by aisle")
                .font(.rounded(.headline))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(FoodCategory.allCases) { cat in
                        Button {
                            category = cat
                            catalog.search(text: searchText, category: cat)
                        } label: {
                            CategoryTile(category: cat, isSelected: category == cat)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -16)
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }

    @ViewBuilder
    private var content: some View {
        if catalog.isLoading {
            HStack {
                Spacer()
                ProgressView("Looking for groceries…").font(.rounded(.subheadline))
                Spacer()
            }
            .padding(.vertical, 40)
        } else if shown.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: catalog.hasSearched ? "magnifyingglass" : "cart.badge.questionmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.green)
                Text(catalog.hasSearched ? "Nothing matches this filter" : "Find out if SNAP covers it, and where it costs less")
                    .font(.rounded(.headline))
                Text(catalog.hasSearched
                     ? "Try All, or search with a simpler word."
                     : "Search for a food, pick an aisle above, or scan a barcode in the store.")
                    .font(.rounded(.subheadline))
                    .foregroundStyle(.secondary)
                if !catalog.hasSearched && StorePriceDatabase.shared.isLoaded {
                    NavigationLink {
                        StaplePricesView()
                    } label: {
                        Label("Compare staple prices by store", systemImage: "chart.bar.xaxis")
                            .font(.rounded(.body, .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(padding: 20)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(catalog.hasSearched ? "\(shown.count) result\(shown.count == 1 ? "" : "s")" : "Recently viewed")
                    .font(.rounded(.headline))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, product in
                        NavigationLink(value: product) {
                            ProductRow(product: product)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < shown.count - 1 {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
}

// MARK: - Shared row pieces

struct ProductRow: View {
    let product: SNAPProduct
    @EnvironmentObject private var appData: LocalStore

    private var details: String {
        [product.brand, product.packageSize].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ProductThumbnail(url: product.imageURL, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.rounded(.body, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !details.isEmpty {
                    Text(details).font(.rounded(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    EligibilityBadge(eligibility: product.eligibility)
                    if let cheapest = appData.cheapestPrice(for: product) {
                        Text(cheapest.isEstimate ? "est. \(cheapest.priceText)" : "from \(cheapest.priceText)")
                            .font(.rounded(.caption, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(cheapest.isEstimate ? Theme.orange : Theme.deepGreen)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

struct ProductThumbnail: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().padding(size * 0.08)
            } else {
                Image(systemName: "takeoutbag.and.cup.and.straw")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(Theme.green.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct EligibilityBadge: View {
    let eligibility: SNAPEligibility

    var body: some View {
        Label(eligibility.rawValue, systemImage: eligibility.icon)
            .font(.rounded(.caption2, .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(eligibility.tint, in: Capsule())
            .foregroundStyle(eligibility.color)
            .fixedSize()
    }
}

// MARK: - Product detail

struct ProductDetailView: View {
    @EnvironmentObject private var appData: LocalStore
    @State private var product: SNAPProduct
    @State private var walmartState: WalmartState = .idle
    @State private var storeForReport: SNAPStore?

    enum WalmartState: Equatable {
        case idle, loading, loaded, notFound
        case unavailable(String)
    }

    init(product: SNAPProduct) {
        _product = State(initialValue: product)
    }

    private var prices: [String: PriceReport] { appData.pricesWithEstimates(for: product) }

    private var details: String {
        [product.brand, product.packageSize].compactMap { $0 }.joined(separator: ", ")
    }

    /// Stores with real prices first (cheapest first), then estimates, then stores with no price.
    private func orderedStores(_ p: [String: PriceReport]) -> [SNAPStore] {
        nj12Stores.sorted { a, b in
            switch (p[a.name], p[b.name]) {
            case let (x?, y?):
                if x.isEstimate != y.isEstimate { return !x.isEstimate }
                return x.price < y.price
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.name < b.name
            }
        }
    }

    /// Lowest real price, compared only among prices sold the same way (each vs. per lb),
    /// using whichever way most stores price it. Needs at least two comparable prices.
    private func lowestRealStore(_ p: [String: PriceReport]) -> String? {
        let real = p.values.filter { !$0.isEstimate }
        let groups = Dictionary(grouping: real, by: { $0.unit ?? "" })
        guard let group = groups.values.max(by: { $0.count < $1.count }), group.count >= 2 else { return nil }
        return group.min { $0.price < $1.price }?.storeName
    }

    private func barFraction(_ report: PriceReport, in p: [String: PriceReport]) -> Double {
        let comparable = p.values.filter { $0.unit == report.unit }.map(\.price)
        guard let maxPrice = comparable.max(), maxPrice > 0 else { return 0 }
        return report.price / maxPrice
    }

    private var websitePriceNote: String {
        let db = StorePriceDatabase.shared
        guard db.isLoaded else { return "Walmart prices load from walmart.com and can differ from the price in the store." }
        let date = db.collectedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "recently"
        return "Website prices are for the closest matching item on each store's online store (ZIP \(db.postalCode)), collected \(date). Online prices can be higher than shelf prices."
    }

    private var walmartNote: String? {
        switch walmartState {
        case .notFound: return "Walmart: this item isn't sold on walmart.com."
        case .unavailable(let why): return "Walmart: \(why)"
        default: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                eligibilityBanner
                addToCartButton
                priceLadder
                notes
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $storeForReport) { s in
            ReportPriceSheet(product: product, initialStore: s)
                .environmentObject(appData)
        }
        .task {
            appData.remember(product)
            await loadWalmartPrice()
        }
        .refreshable { await loadWalmartPrice(force: true) }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            ProductThumbnail(url: product.imageURL, size: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text(product.name)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if !details.isEmpty {
                    Text(details).font(.rounded(.subheadline)).foregroundStyle(.secondary)
                }
                Label(product.category.shortName, systemImage: product.category.iconName)
                    .font(.rounded(.caption, .semibold))
                    .foregroundStyle(Theme.deepGreen)
            }
        }
        .padding(.top, 8)
    }

    private var eligibilityBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: product.eligibility.icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(product.eligibility.color)
                Text(product.eligibility.headline)
                    .font(.rounded(.headline))
                    .foregroundStyle(product.eligibility.color)
            }
            Text(product.reason)
                .font(.rounded(.subheadline))
                .fixedSize(horizontal: false, vertical: true)
            if let alternative = product.alternative {
                Label("Try instead: \(alternative)", systemImage: "arrow.triangle.swap")
                    .font(.rounded(.subheadline, .semibold))
                    .foregroundStyle(Theme.deepGreen)
            }
            Text(product.basis.rawValue)
                .font(.rounded(.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(product.eligibility.tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var addToCartButton: some View {
        let inCart = appData.quantityInCart(product)
        let blocked = product.eligibility == .notEligible
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                appData.addToCart(product)
            } label: {
                Label(blocked ? "SNAP can't pay for this item"
                              : inCart > 0 ? "Add another (\(inCart) in your cart)" : "Add to trip cart",
                      systemImage: blocked ? "nosign" : inCart > 0 ? "plus.circle.fill" : "cart.badge.plus")
                    .font(.rounded(.body, .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Theme.green)
            .disabled(blocked)
            .sensoryFeedback(.success, trigger: inCart)

            if product.eligibility == .checkAtStore {
                Text("You can add it, but confirm it at the register.")
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var priceLadder: some View {
        let p = prices
        let stores = orderedStores(p)
        let lowest = lowestRealStore(p)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Prices near you").font(.rounded(.headline))
                Spacer()
                Text("Tap a store to add a shelf price")
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(stores.enumerated()), id: \.element.id) { index, s in
                    let report = p[s.name]
                    Button { storeForReport = s } label: {
                        PriceRow(store: s, report: report,
                                 isLoading: s.name == walmartStoreName && walmartState == .loading,
                                 isLowest: s.name == lowest,
                                 fraction: report.map { barFraction($0, in: p) } ?? 0)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let report, report.source == .shopperReported,
                           appData.latestPrices(for: product.id)[s.name]?.id == report.id {
                            Button(role: .destructive) { appData.deletePrice(report) } label: {
                                Label("Delete my price", systemImage: "trash")
                            }
                        }
                    }
                    if index < stores.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(websitePriceNote)
            Text("Prices marked ≈ are estimates, not real prices. They're based on this item's price at other stores or typical prices for similar items.")
            Text("A shelf price you enter replaces the website price or estimate for that store. Press and hold your price to delete it.")
            if let note = walmartNote { Text(note) }
        }
        .font(.rounded(.caption))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    @MainActor
    private func loadWalmartPrice(force: Bool = false) async {
        guard let barcode = product.barcode else {
            walmartState = .unavailable("This item has no barcode.")
            return
        }
        if !force, let existing = appData.latestPrices(for: product.id)[walmartStoreName], existing.source == .walmartAPI,
           Date().timeIntervalSince(existing.date) < 6 * 3600 {
            walmartState = .loaded
            return
        }

        walmartState = .loading
        do {
            guard let listing = try await WalmartService.shared.listing(forBarcode: barcode) else {
                walmartState = .notFound
                return
            }
            appData.addPrice(listing.price, store: walmartStoreName, productID: product.id, source: .walmartAPI)

            var updated = product
            if updated.name.hasPrefix("Unknown item") || updated.name.hasPrefix("Unnamed item"), !listing.name.isEmpty {
                updated.name = listing.name
            }
            // Use Walmart's own SNAP flag only if it explicitly sent one.
            if let flag = listing.snapEligible {
                updated.eligibility = flag ? .eligible : .notEligible
                updated.basis = .retailerFlag
                updated.reason = flag ? "Walmart lists this item as SNAP-eligible." : "Walmart lists this item as not SNAP-eligible."
                updated.alternative = nil
            }
            if updated != product {
                product = updated
                appData.update(updated)
            }
            walmartState = .loaded
        } catch let error as WalmartError {
            walmartState = .unavailable(error.localizedDescription)
        } catch {
            walmartState = .unavailable("Couldn't reach Walmart right now.")
        }
    }
}

struct PriceRow: View {
    let store: SNAPStore
    let report: PriceReport?
    let isLoading: Bool
    var isLowest = false
    var fraction: Double = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StoreAvatar(name: store.name, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.name)
                        .font(.rounded(.subheadline, .semibold))
                        .foregroundStyle(.primary)
                    if isLowest {
                        Text("Lowest")
                            .font(.rounded(.caption2, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.green, in: Capsule())
                    }
                    Spacer(minLength: 8)
                    priceText
                }
                detailText
                if let report {
                    PriceBar(fraction: fraction,
                             color: report.isEstimate ? Theme.orange.opacity(0.5) : (isLowest ? Theme.green : Theme.green.opacity(0.45)))
                        .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var priceText: some View {
        if isLoading {
            ProgressView()
        } else if let report {
            Text(report.priceText)
                .font(.rounded(.body, report.isEstimate ? .medium : .bold))
                .monospacedDigit()
                .foregroundStyle(report.isEstimate ? Theme.orange : Theme.deepGreen)
        } else {
            Label("Add", systemImage: "plus.circle")
                .font(.rounded(.subheadline, .semibold))
                .foregroundStyle(Theme.green)
        }
    }

    @ViewBuilder
    private var detailText: some View {
        if let report {
            if report.isEstimate {
                Text("Estimate. \(report.matchedName ?? "")")
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else if let matched = report.matchedName {
                Text(matched)
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(report.source.rawValue), \(report.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.rounded(.caption2))
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(report.source.rawValue), \(report.date.formatted(.relative(presentation: .named)))")
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No price yet")
                .font(.rounded(.caption))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Report a price

struct ReportPriceSheet: View {
    let product: SNAPProduct
    @EnvironmentObject private var appData: LocalStore
    @Environment(\.dismiss) private var dismiss
    @State private var storeName: String
    @State private var priceText = ""
    @FocusState private var priceFocused: Bool

    init(product: SNAPProduct, initialStore: SNAPStore) {
        self.product = product
        _storeName = State(initialValue: initialStore.name)
    }

    private var price: Double? {
        let cleaned = priceText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0, value < 1000 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    ProductThumbnail(url: product.imageURL, size: 48)
                    Text(product.name)
                        .font(.rounded(.headline))
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Store").font(.rounded(.subheadline, .semibold))
                    Menu {
                        Picker("Store", selection: $storeName) {
                            ForEach(nj12Stores) { Text($0.name).tag($0.name) }
                        }
                    } label: {
                        HStack {
                            StoreAvatar(name: storeName, size: 28)
                            Text(storeName).font(.rounded(.body)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
                        }
                        .surfaceCard(padding: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Price on the shelf tag").font(.rounded(.subheadline, .semibold))
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .focused($priceFocused)
                    }
                    .surfaceCard(padding: 14)
                    Text("Saved on this phone with today's date.")
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Add a shelf price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save price") {
                        if let price {
                            appData.addPrice(price, store: storeName, productID: product.id, source: .shopperReported)
                            dismiss()
                        }
                    }
                    .bold()
                    .disabled(price == nil)
                }
            }
            .onAppear { priceFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
