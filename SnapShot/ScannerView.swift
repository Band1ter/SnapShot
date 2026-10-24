import SwiftUI
import VisionKit

/// Real barcode scanning with the camera (VisionKit, iOS 16+), plus typed entry for the Simulator
/// or devices without a supported camera.
/// Requires "Privacy - Camera Usage Description" (NSCameraUsageDescription) in Info.plist.
struct ScannerView: View {
    @EnvironmentObject private var appData: LocalStore
    @State private var scannedProduct: SNAPProduct?
    @State private var isLookingUp = false
    @State private var message: String?
    @State private var typedCode = ""

    private let service = OpenFoodFactsService()

    private var cameraAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if cameraAvailable {
                    BarcodeScanner(isActive: scannedProduct == nil && !isLookingUp) { code in
                        Task { await lookUp(code) }
                    }
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Theme.green, lineWidth: 3)
                    )
                    .padding(.horizontal)

                    Text("Point the camera at a barcode in the aisle.")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.green)
                        Text("Camera scanning isn't available here. Type the numbers under the barcode instead.")
                            .font(.rounded(.subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal, 20)
                    .background(Theme.mint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal)
                }

                HStack {
                    TextField("Or type the barcode number", text: $typedCode)
                        .keyboardType(.numberPad)
                        .font(.rounded(.body))
                        .monospacedDigit()
                        .padding(12)
                        .background(Theme.surface, in: Capsule())
                    Button("Look up") { Task { await lookUp(typedCode) } }
                        .font(.rounded(.body, .semibold))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.green)
                        .disabled(typedCode.filter(\.isNumber).count < 8 || isLookingUp)
                }
                .padding(.horizontal)

                if isLookingUp {
                    ProgressView("Looking up item…").font(.rounded(.subheadline))
                }
                if let message {
                    Text(message)
                        .font(.rounded(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Scan a Barcode")
            .sheet(item: $scannedProduct) { product in
                NavigationStack {
                    ProductDetailView(product: product)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { scannedProduct = nil }
                            }
                        }
                }
                .environmentObject(appData)
            }
        }
    }

    @MainActor
    private func lookUp(_ raw: String) async {
        let code = raw.filter(\.isNumber)
        guard code.count >= 8, !isLookingUp else { return }
        isLookingUp = true
        message = nil
        defer { isLookingUp = false }

        do {
            if let product = try await service.product(barcode: code) {
                scannedProduct = product
            } else {
                // Not in the database yet: still show the item so Walmart and shopper prices can be added.
                scannedProduct = OpenFoodFactsService.unknownProduct(barcode: code)
            }
            typedCode = ""
        } catch {
            message = "Couldn't look up that barcode. Check your connection and try again."
        }
    }
}

// MARK: - VisionKit wrapper

struct BarcodeScanner: UIViewControllerRepresentable {
    var isActive: Bool
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if isActive && !controller.isScanning {
            try? controller.startScanning()
        } else if !isActive && controller.isScanning {
            controller.stopScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        private var lastCode = ""
        private var lastScan = Date.distantPast

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let code = barcode.payloadStringValue else { continue }
                // Ignore the same barcode seen again within 3 seconds.
                if code == lastCode && Date().timeIntervalSince(lastScan) < 3 { continue }
                lastCode = code
                lastScan = Date()
                onScan(code)
                return
            }
        }
    }
}
