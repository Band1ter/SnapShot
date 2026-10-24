# Snapshot – setup

## 1. Add the files to Xcode
1. In the Xcode project, delete the old `ContentView.swift` (the single big file).
2. Drag in all 8 `.swift` files from this folder and check "Copy items if needed".
3. Keep the existing `...App.swift` file with `@main`. It should still show `ContentView()`.
4. Target → General → Minimum Deployments: **iOS 16.0** (needed for the barcode scanner).

## 2. Camera permission
Target → Info → add **Privacy - Camera Usage Description** with text like:
"Snapshot uses the camera to scan grocery barcodes."

## 3. Live Walmart prices (optional, free)
1. Make a developer account at https://walmart.io and follow its key tutorial
   (generate an RSA key pair with `openssl`).
2. Upload the **public** key in the walmart.io dashboard.
3. In `WalmartService.swift`, fill in `consumerID`, `keyVersion`, and paste the **private** key
   into `privateKeyPEM` (including the BEGIN/END lines).
4. Keep the project in a **private** repo once the key is in it.

Without keys, everything else works. Product pages just say Walmart prices are off.

## 4. Where data comes from
| What | Source |
|---|---|
| Product names, photos, categories | Open Food Facts (free, no key) |
| SNAP eligibility | Federal SNAP rules applied to each product's category; a retailer's own SNAP flag is used if Walmart's response includes one |
| Walmart price | walmart.com, live, by barcode |
| ShopRite, ALDI, Stop & Shop, BJ's, etc. | Entered by the user from the shelf tag, saved on the phone with the date |
| Cart, prices, benefit amount | One JSON file in the app's Documents folder |

## 5. Testing tips
- The Simulator has no camera. Type a barcode on the Scan tab instead
  (for example `0044000032029`, Oreo cookies).
- Try searching "root beer", "vitamin d milk", and "steak". These were misclassified before.
- Enter a few shelf prices at two stores, add the items to the cart, and check the Trip Cart totals.

## 6. Still to check before submitting
- Store addresses and that each store is inside the 12th District
  (USDA SNAP Retailer Locator).
- The code hasn't been compiled yet. Paste any Xcode errors back to Claude to fix.
