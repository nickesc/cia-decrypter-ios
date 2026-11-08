import Foundation

public enum KeyFileKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case aes = "aes_keys.txt"
    case seeds = "seeddb.bin"
    case boot9 = "boot9.bin"
    public var id: String { rawValue }
}

public struct KeyMaterial: Codable, Sendable {
    var keys: [String: Data] = [:]
    var seeds: [UInt64: Data] = [:]

    public init() {}
    public var keyCount: Int { keys.count }
    public var seedCount: Int { seeds.count }

    public mutating func merge(_ other: KeyMaterial) {
        keys.merge(other.keys) { _, new in new }
        seeds.merge(other.seeds) { _, new in new }
    }

    public mutating func load(_ data: Data, kind: KeyFileKind) throws {
        switch kind {
        case .aes: try loadAES(data)
        case .seeds: try loadSeeds(data)
        case .boot9: try loadBoot9(data)
        }
    }

    mutating func loadAES(_ data: Data) throws {
        guard data.count <= 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw ConversionError.invalid("aes_keys.txt must be a UTF-8 text file smaller than 1 MB.")
        }
        var imported: [String: Data] = [:]
        var section: String? = nil
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix(":") { section = String(line.dropFirst()).uppercased(); continue }
            if let section, section != "AES" { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { throw ConversionError.invalid("Invalid key entry on line \(index + 1).") }
            let name = parts[0].lowercased()
            let supported = name == "generatorconstant" || name == "fixedsystemkey" || name.range(of: "^slot0x[0-9a-f]{2}key[xyn]$", options: .regularExpression) != nil || name.range(of: "^common[0-5]$", options: .regularExpression) != nil || name.range(of: "^common[0-5]normal$", options: .regularExpression) != nil
            if !supported { continue }
            guard let value = Data(hex: parts[1]), value.count == 16 else {
                throw ConversionError.invalid("Invalid 128-bit key on line \(index + 1). Key values are never logged.")
            }
            imported[name] = value
        }
        guard !imported.isEmpty else { throw ConversionError.invalid("No supported AES keys were found.") }
        keys.merge(imported) { _, new in new }
    }

    mutating func loadSeeds(_ data: Data) throws {
        guard data.count >= 16, data.count <= 16 * 1024 * 1024 else { throw ConversionError.invalid("Invalid seed database size.") }
        let count = Int(try data.number(0, 4))
        guard count > 0, data.count == 16 + count * 32 else { throw ConversionError.invalid("The seed database is truncated or has an invalid entry count.") }
        var imported: [UInt64: Data] = [:]
        for index in 0..<count {
            let offset = 16 + index * 32
            let title = try data.number(offset, 8)
            guard imported[title] == nil else { throw ConversionError.invalid("Duplicate title in seed database.") }
            imported[title] = try data.bytes(offset + 8, 16)
        }
        seeds.merge(imported) { _, new in new }
    }

    mutating func loadBoot9(_ data: Data) throws {
        let expected: [Int: String] = [
            0x10000: "2f88744feed717856386400a44bba4b9ca62e76a32c715d4f309c399bf28166f",
            0x8000: "7331f7edece3dd33f2ab4bd0b3a5d607229fd19212c10b734cedcaf78c1a7b98"
        ]
        guard let hash = expected[data.count], Crypto.sha256(data).hex == hash else {
            throw ConversionError.invalid("Boot9 must be a valid full or protected retail dump.")
        }
        let base = (data.count == 0x10000 ? 0x8000 : 0) + 0x5860
        for slot in 0x2c...0x3b {
            keys[String(format: "slot0x%02xkeyx", slot)] = try data.bytes(base + 0x170 + ((slot - 0x2c) / 4) * 16, 16)
        }
        for slot in 0x3c...0x3f {
            keys[String(format: "slot0x%02xkeyx", slot)] = try data.bytes(base + 0x1b0 + (slot - 0x3c) * 16, 16)
        }
    }

    func normalKey(slot: Int, y: Data) throws -> Data {
        let name = String(format: "slot0x%02xkeyx", slot)
        guard let x = keys[name] else { throw ConversionError.missingKey(String(format: "KeyX for slot 0x%02X in aes_keys.txt (or Boot9 where available)", slot)) }
        return try Crypto.scramble(x: x, y: y, constant: keys["generatorconstant"])
    }

    func commonKey(index: Int) throws -> Data {
        if let normal = keys["common\(index)normal"] { return normal }
        guard let y = keys["common\(index)"] else { throw ConversionError.missingKey("common\(index) in aes_keys.txt") }
        return try normalKey(slot: 0x3d, y: y)
    }
}
