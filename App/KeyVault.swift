import Foundation
import Observation
import Security
import CIAKit

struct KeyImport: Codable {
    let material: KeyMaterial
    let date: Date
}

@MainActor
@Observable
final class KeyVault {
    private(set) var imports: [KeyFileKind: KeyImport] = [:]
    private(set) var error: String?
    private let seedURL: URL
    private let service = (Bundle.main.bundleIdentifier ?? "xyz.batcomputer.ciadecrypter") + ".keys"

    init(directory: URL) {
        seedURL = directory.appendingPathComponent("seeds.json")
        reload()
    }

    var material: KeyMaterial {
        var material = KeyMaterial()
        for kind in [KeyFileKind.boot9, .aes, .seeds] {
            if let imported = imports[kind] { material.merge(imported.material) }
        }
        return material
    }

    func importFile(_ url: URL, kind: KeyFileKind) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 16 * 1024 * 1024 else { throw ConversionError.invalid("This key file is empty or too large.") }
        let data = try Data(contentsOf: url)
        var material = KeyMaterial()
        try material.load(data, kind: kind)
        let imported = KeyImport(material: material, date: Date())
        let encoded = try JSONEncoder().encode(imported)
        if kind == .seeds {
            try encoded.write(to: seedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var local = seedURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try local.setResourceValues(values)
        } else {
            let query = query(kind)
            let update = [kSecValueData: encoded, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary
            var status = SecItemUpdate(query as CFDictionary, update)
            if status == errSecItemNotFound {
                var add = query
                add[kSecValueData] = encoded
                add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(add as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw vaultError(status) }
        }
        imports[kind] = imported
        error = nil
    }

    func remove(_ kind: KeyFileKind) throws {
        if kind == .seeds {
            if FileManager.default.fileExists(atPath: seedURL.path) { try FileManager.default.removeItem(at: seedURL) }
        } else {
            let status = SecItemDelete(query(kind) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw vaultError(status) }
        }
        imports.removeValue(forKey: kind)
    }

    private func reload() {
        do {
            for kind in KeyFileKind.allCases {
                if kind == .seeds {
                    if FileManager.default.fileExists(atPath: seedURL.path) {
                        imports[kind] = try JSONDecoder().decode(KeyImport.self, from: Data(contentsOf: seedURL))
                    }
                } else {
                    var request = query(kind)
                    request[kSecReturnData] = true
                    request[kSecMatchLimit] = kSecMatchLimitOne
                    var result: CFTypeRef?
                    let status = SecItemCopyMatching(request as CFDictionary, &result)
                    if status == errSecItemNotFound { continue }
                    guard status == errSecSuccess, let data = result as? Data else { throw vaultError(status) }
                    imports[kind] = try JSONDecoder().decode(KeyImport.self, from: data)
                }
            }
        } catch { self.error = "Saved keys could not be read. \(error.localizedDescription)" }
    }

    private func query(_ kind: KeyFileKind) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: kind.rawValue]
    }

    private func vaultError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain could not save or read the imported keys (\(status)). Try importing again after unlocking the device."])
    }
}
