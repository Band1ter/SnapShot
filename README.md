# SnapShot

**Scans grocery items and determines if it is covered by SNAP — then compare prices across nearby stores.**

SnapShot is an iOS app that helps SNAP (food stamps) recipients make informed shopping decisions at the grocery store. Point your camera at a barcode, and within seconds you'll see whether that item is SNAP-eligible under federal rules, why it is or isn't, and what it costs at stores nearby.

---

## Features

- **Barcode Scanner** — Uses VisionKit (iOS 16+) for real-time camera scanning. Typed entry works on the Simulator and devices without a supported camera.
- **SNAP Eligibility** — Applies the complete federal SNAP eligibility ruleset (alcohol, tobacco, hot foods, vitamins, pet food, and more) to every scanned product. Powered by Open Food Facts.
- **Eligibility Basis** — Shows *why* an item is eligible or not — whether it's marked by the retailer, determined by a federal rule, or flagged for an in-store check.
- **Price Comparison** — Compares prices across local stores so you can stretch your SNAP budget further.
- **Browse by Category** — Explore items across Produce, Meat & Seafood, Dairy, Bakery, Frozen Foods, Beverages, Snacks, and more.
- **Cart** — Save items as you shop and see your running total.

---

## Screenshots

> Add screenshots here — drag them into the `screenshots/` folder and update the paths below.

| Scanner | Result | Price Comparison |
|---|---|---|
| *(scanner.png)* | *(result.png)* | *(compare.png)* |

---

## Requirements

- iOS 16.0+
- Xcode 15+
- Swift 5.9+
- Camera permission (`NSCameraUsageDescription` in Info.plist)

---

## Getting Started

1. Clone the repo:
   ```bash
   git clone https://github.com/deepaksg/SnapShot.git
   cd SnapShot
   ```
2. Open `SnapShot.xcodeproj` in Xcode.
3. Select your target device or simulator and press **Run** (⌘R).

No external dependencies or package manager setup required — the project builds out of the box.

---

## Data Sources

- **[Open Food Facts](https://world.openfoodfacts.org/)** — Product catalog, category tags, and nutrition data (open database, CC BY-SA).
- **SNAP eligibility rules** — Based on [USDA FNS guidelines](https://www.fns.usda.gov/snap/eligible-food-items).
- **Store prices** — Walmart pricing via WalmartService; local store price database bundled in `store_prices.json`.

---

## Project Structure

```
SnapShot/
├── SnapShotApp.swift          # App entry point
├── Models.swift               # Data models, SNAP eligibility types, food categories
├── EligibilityEngine.swift    # Federal SNAP rule classifier
├── ScannerView.swift          # Camera barcode scanner (VisionKit)
├── ComparePricesView.swift    # Store price comparison
├── BrowseViews.swift          # Category browsing
├── CartAndInfoViews.swift     # Shopping cart and product info
├── ProductServices.swift      # Open Food Facts API integration
├── WalmartService.swift       # Walmart pricing integration
├── StorePriceDatabase.swift   # Local price lookup
├── PriceEstimator.swift       # Price estimation logic
├── LocalStore.swift           # App state (EnvironmentObject)
├── DesignSystem.swift         # Shared colors, fonts, components
└── store_prices.json          # Bundled store price data
```

---

## Demo

> Add a link to a demo video here (e.g., a YouTube or Loom recording of the app in action).

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

*Built by [Deepak Giriraddi](https://github.com/deepaksg)*
