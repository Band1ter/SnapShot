import Foundation
import Security

// MARK: - Walmart Affiliate API credentials
//
// Free at https://walmart.io. Follow walmart.io's key tutorial to make an RSA key pair with openssl,
// upload the PUBLIC key in the dashboard, then copy the Consumer ID and key version here and paste the
// PRIVATE key below. Without these, the app still works; Walmart prices just won't load.
//
// For the App Challenge demo the key lives inside the app. Don't put real values in a public GitHub repo.

enum WalmartConfig {
    static let consumerID = ""          // "Consumer ID" from the walmart.io dashboard
    static let keyVersion = "1"         // key version shown next to your uploaded public key
    // Paste the whole private key, including the -----BEGIN ... KEY----- and -----END ... KEY----- lines.
    // Keep each pasted line indented at least as far as the closing """.
    static let privateKeyPEM = """
    """

    static var isConfigured: Bool {
        !consumerID.isEmpty && !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Service

struct WalmartListing {
    let price: Double
    let name: String
    let url: URL?
    /// Only set when Walmart's response explicitly includes a SNAP/EBT flag. Otherwise the app uses the SNAP rules.
    let snapEligible: Bool?
}

enum WalmartError: LocalizedError {
    case notConfigured, invalidKey, signingFailed, unsupportedBarcode, http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Live Walmart prices are off. Add API keys in WalmartService.swift."
        case .invalidKey: return "The Walmart private key couldn't be read. Check that it was pasted completely."
        case .signingFailed: return "Couldn't sign the Walmart request."
        case .unsupportedBarcode: return "Walmart lookups need a 12-digit UPC barcode."
        case .http(let code): return "Walmart returned an error (\(code))."
        }
    }
}

final class WalmartService {
    static let shared = WalmartService()

    private let endpoint = "https://developer.api.walmart.com/api-proxy/service/affil/product/v2/items"
    private lazy var privateKey: SecKey? = Self.makePrivateKey(pem: WalmartConfig.privateKeyPEM)

    /// Looks up the walmart.com price for a barcode. Returns nil if Walmart doesn't sell the item.
    func listing(forBarcode barcode: String) async throws -> WalmartListing? {
        guard WalmartConfig.isConfigured else { throw WalmartError.notConfigured }
        guard let upc = Self.upcA(from: barcode) else { throw WalmartError.unsupportedBarcode }
        guard let key = privateKey else { throw WalmartError.invalidKey }

        var components = URLComponents(string: endpoint)!
        components.queryItems = [URLQueryItem(name: "upc", value: upc)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        // Walmart's signature: consumerId \n timestamp(ms) \n keyVersion \n, signed with RSA-SHA256, base64.
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let toSign = "\(WalmartConfig.consumerID)\n\(timestamp)\n\(WalmartConfig.keyVersion)\n"
        guard let signature = Self.sign(toSign, with: key) else { throw WalmartError.signingFailed }

        request.setValue(WalmartConfig.consumerID, forHTTPHeaderField: "WM_CONSUMER.ID")
        request.setValue(timestamp, forHTTPHeaderField: "WM_CONSUMER.INTIMESTAMP")
        request.setValue(WalmartConfig.keyVersion, forHTTPHeaderField: "WM_SEC.KEY_VERSION")
        request.setValue(signature, forHTTPHeaderField: "WM_SEC.AUTH_SIGNATURE")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw WalmartError.http(status) }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let item = items.first,
              let price = Self.number(item["salePrice"]) else { return nil }

        let urlString = (item["productUrl"] as? String) ?? (item["productTrackingUrl"] as? String)
        return WalmartListing(
            price: price,
            name: (item["name"] as? String) ?? "",
            url: urlString.flatMap(URL.init(string:)),
            snapEligible: Self.snapFlag(in: item))
    }

    // MARK: Helpers

    /// Open Food Facts often stores US barcodes as 13 digits with a leading 0. Walmart wants the 12-digit UPC-A.
    static func upcA(from code: String) -> String? {
        guard !code.isEmpty, code.allSatisfy(\.isNumber) else { return nil }
        switch code.count {
        case 12: return code
        case 13 where code.hasPrefix("0"): return String(code.dropFirst())
        case 14 where code.hasPrefix("00"): return String(code.dropFirst(2))
        default: return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// Uses a SNAP/EBT flag only if Walmart's response explicitly contains one (e.g. a key like "snapEligible").
    private static func snapFlag(in item: [String: Any]) -> Bool? {
        for (key, value) in item {
            let k = key.lowercased()
            guard k.contains("snap") || k.contains("ebt") else { continue }
            if let b = value as? Bool { return b }
            if let s = value as? String { return ["true", "yes", "y"].contains(s.lowercased()) }
        }
        return nil
    }

    private static func sign(_ message: String, with key: SecKey) -> String? {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256, Data(message.utf8) as CFData, &error) as Data? else {
            return nil
        }
        return signature.base64EncodedString()
    }

    /// Accepts "BEGIN RSA PRIVATE KEY" (PKCS#1) or "BEGIN PRIVATE KEY" (PKCS#8). Encrypted keys aren't supported.
    private static func makePrivateKey(pem: String) -> SecKey? {
        let base64 = pem
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: base64) else { return nil }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        if let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil) {
            return key
        }
        if let inner = pkcs1(fromPKCS8: der) {
            return SecKeyCreateWithData(inner as CFData, attributes as CFDictionary, nil)
        }
        return nil
    }

    /// Unwraps a PKCS#8 container: SEQUENCE { INTEGER version, SEQUENCE algorithm, OCTET STRING pkcs1Key }.
    private static func pkcs1(fromPKCS8 der: Data) -> Data? {
        let bytes = [UInt8](der)
        var i = 0

        func readLength() -> Int? {
            guard i < bytes.count else { return nil }
            let first = bytes[i]; i += 1
            if first < 0x80 { return Int(first) }
            let count = Int(first & 0x7F)
            guard count > 0, count <= 4, i + count <= bytes.count else { return nil }
            var length = 0
            for _ in 0..<count { length = (length << 8) | Int(bytes[i]); i += 1 }
            return length
        }
        func expect(_ tag: UInt8) -> Bool {
            guard i < bytes.count, bytes[i] == tag else { return false }
            i += 1
            return true
        }

        guard expect(0x30), readLength() != nil else { return nil }           // outer SEQUENCE
        guard expect(0x02), let versionLength = readLength() else { return nil } // version
        i += versionLength
        guard expect(0x30), let algorithmLength = readLength() else { return nil } // algorithm
        i += algorithmLength
        guard expect(0x04), let keyLength = readLength(), i + keyLength <= bytes.count else { return nil }
        return Data(bytes[i..<(i + keyLength)])
    }
}
