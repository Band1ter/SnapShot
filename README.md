# SnapShot

SnapShot is an iOS app that helps SNAP (food stamps) recipients make informed shopping decisions at the grocery store.

---

## Features

- **Barcode Scanner** — Uses VisionKit (iOS 16+) for real-time camera scanning. Typed entry works on the Simulator and devices without a supported camera.
- **SNAP Eligibility** — Applies the complete federal SNAP eligibility ruleset (alcohol, tobacco, hot foods, vitamins, pet food, and more) to every scanned product. Powered by Open Food Facts.
- **Eligibility Basis** — Shows *why* an item is eligible or not — whether it's marked by the retailer, determined by a federal rule, or flagged for an in-store check.
- **Price Comparison** — Compares prices across local stores so you can stretch your SNAP budget further.
- **Browse by Category** — Explore items across Produce, Meat & Seafood, Dairy, Bakery, Frozen Foods, Beverages, Snacks, and more.
- **Cart** — Save items as you shop and see your running total.


## Data Sources

- **[Open Food Facts](https://world.openfoodfacts.org/)** — Product catalog, category tags, and nutrition data (open database, CC BY-SA).
- **SNAP eligibility rules** — Based on [USDA FNS guidelines](https://www.fns.usda.gov/snap/eligible-food-items).
- **Store prices** — Walmart pricing via WalmartService; local store price database bundled in `store_prices.json`.
