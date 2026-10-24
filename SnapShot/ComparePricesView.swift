import SwiftUI

/// Compare what common SNAP staples cost at each nearby store, using the prices collected from
/// the stores' online stores (store_prices.json).
struct StaplePricesView: View {
    @State private var query = ""
    private let database = StorePriceDatabase.shared

    private var shownTerms: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let translated = SpanishTranslator.translate(q).lowercased()
        guard !q.isEmpty else { return database.terms }
        return database.terms.filter { $0.contains(q) || $0.contains(translated) }
    }

    var body: some View {
        List {
            if !database.isLoaded {
                Text("Store prices haven't been added to the app yet.")
                    .font(.rounded(.body))
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    Text("Pick a staple to see what it costs at each store, cheapest first.")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                }
                Section {
                    ForEach(shownTerms, id: \.self) { term in
                        NavigationLink {
                            StapleDetailView(term: term)
                        } label: {
                            StapleRow(term: term)
                        }
                    }
                } footer: {
                    if let date = database.collectedAt {
                        Text("Prices from each store's online store for ZIP \(database.postalCode), collected \(date.formatted(date: .abbreviated, time: .omitted)). Online prices can be higher than shelf prices.")
                            .font(.rounded(.caption))
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .paperBackground()
        .navigationTitle("Compare Prices")
        .searchable(text: $query, prompt: "Find a staple (eggs, arroz, bread…)")
    }
}

private struct StapleRow: View {
    let term: String
    private let database = StorePriceDatabase.shared

    var body: some View {
        let stores = database.items(forTerm: term)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(term.capitalized).font(.rounded(.body, .semibold))
                Text("Sold at \(stores.count) store\(stores.count == 1 ? "" : "s")")
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let best = stores.first, let item = best.items.first {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(StorePriceDatabase.priceText(item))
                        .font(.rounded(.body, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.deepGreen)
                    Text("at \(best.store)")
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                StoreAvatar(name: best.store, size: 30)
            }
        }
    }
}

struct StapleDetailView: View {
    let term: String
    private let database = StorePriceDatabase.shared

    var body: some View {
        List {
            ForEach(Array(database.items(forTerm: term).enumerated()), id: \.element.store) { index, entry in
                Section {
                    ForEach(entry.items, id: \.self) { item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.n).font(.rounded(.subheadline))
                                if !item.s.isEmpty {
                                    Text(item.s).font(.rounded(.caption)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(StorePriceDatabase.priceText(item))
                                    .font(.rounded(.subheadline, .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.deepGreen)
                                if let regular = item.r, regular > item.p {
                                    Text(regular, format: .currency(code: "USD"))
                                        .font(.rounded(.caption))
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        StoreAvatar(name: entry.store, size: 26)
                        Text(entry.store)
                            .font(.rounded(.headline))
                            .foregroundStyle(.primary)
                        if index == 0 {
                            Text("Lowest price")
                                .font(.rounded(.caption2, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.green, in: Capsule())
                        }
                    }
                    .textCase(nil)
                }
                .listRowBackground(Theme.surface)
            }
            Section {
                EmptyView()
            } footer: {
                Text("Items found on each store's online store for “\(term)”, cheapest first. Package sizes differ, so compare sizes as well as prices. Prices marked / lb are per pound.")
            }
        }
        .listStyle(.insetGrouped)
        .paperBackground()
        .navigationTitle(term.capitalized)
        .navigationBarTitleDisplayMode(.inline)
    }
}
