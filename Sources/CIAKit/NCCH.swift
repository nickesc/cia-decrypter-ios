import Foundation
import CryptoKit

struct CryptoRegion {
    let start: UInt64
    let size: UInt64
    let origin: UInt64
    let counter: Data
    let key: Data
}

struct HashRegion {
    let name: String
    let start: UInt64
    let size: UInt64
    let expected: Data
    var hasher = SHA256()

    mutating func update(_ data: Data, offset: UInt64) {
        let first = max(start, offset)
        let last = min(start + size, offset + UInt64(data.count))
        if first < last { hasher.update(data: data.subdata(in: Int(first - offset)..<Int(last - offset))) }
    }

    func verify() throws {
        guard Data(hasher.finalize()) == expected else { throw ConversionError.integrity("The decrypted \(name) hash does not match.") }
    }
}

struct NCCHPlan {
    let originalHeader: Data
    let size: UInt64
    let partitionID: UInt64
    let programID: UInt64
    var regions: [CryptoRegion] = []
    var hashes: [HashRegion] = []

    init(source: ContentSource, keys: KeyMaterial) throws {
        let h = try source.read(0, 0x200)
        guard try h.bytes(0x100, 4) == Data("NCCH".utf8) else { throw ConversionError.integrity("The content is not a readable NCCH container.") }
        originalHeader = h
        size = try h.number(0x104, 4) * 0x200
        partitionID = try h.number(0x108, 8)
        programID = try h.number(0x118, 8)
        let version = try h.number(0x112, 2)
        guard version == 0 || version == 2 else { throw ConversionError.unsupported("This NCCH version is not supported.") }
        guard size >= 0x200, size <= source.content.size, source.content.size - size < 0x200, h[0x18e] == 0 else {
            throw ConversionError.invalid("Invalid NCCH size or media unit.")
        }
        let flags = h[0x18f]
        let encrypted = flags & 4 == 0
        let method = h[0x18b]
        let extSize = try h.number(0x180, 4)
        guard extSize == 0 || extSize == 0x400 else { throw ConversionError.invalid("Invalid extended-header size.") }
        let exefs = try h.number(0x1a0, 4) * 0x200
        let exefsSize = try h.number(0x1a4, 4) * 0x200
        let romfs = try h.number(0x1b0, 4) * 0x200
        let romfsSize = try h.number(0x1b4, 4) * 0x200
        var occupied: [(UInt64, UInt64)] = [(0, 0x200)]
        func validate(_ start: UInt64, _ length: UInt64) throws {
            guard length == 0 || (start >= 0x200 && start <= size && length <= size - start) else {
                throw ConversionError.invalid("An NCCH section extends beyond its content.")
            }
        }
        for (start, length) in [(UInt64(0x200), extSize == 0 ? 0 : UInt64(0x800)), (exefs, exefsSize), (romfs, romfsSize), (try h.number(0x190, 4) * 0x200, try h.number(0x194, 4) * 0x200), (try h.number(0x198, 4) * 0x200, try h.number(0x19c, 4) * 0x200)] {
            try validate(start, length)
            if length > 0 {
                guard !occupied.contains(where: { start < $0.0 + $0.1 && $0.0 < start + length }) else {
                    throw ConversionError.invalid("Overlapping NCCH sections.")
                }
                occupied.append((start, length))
            }
        }
        var mainKey = Data(repeating: 0, count: 16)
        var extraKey = mainKey
        if encrypted {
            if flags & 1 != 0 {
                if programID & (0x10 << 32) != 0 {
                    guard let fixed = keys.keys["fixedsystemkey"] else { throw ConversionError.missingKey("fixedSystemKey in aes_keys.txt") }
                    mainKey = fixed
                }
                extraKey = mainKey
            } else {
                let y = try h.bytes(0, 16)
                mainKey = try keys.normalKey(slot: 0x2c, y: y)
                let slots: [UInt8: Int] = [0: 0x2c, 1: 0x25, 0x0a: 0x18, 0x0b: 0x1b]
                guard let slot = slots[method] else { throw ConversionError.unsupported("Unknown NCCH encryption method.") }
                var extraY = y
                if flags & 0x20 != 0 {
                    guard let seed = keys.seeds[programID] else { throw ConversionError.missingKey(String(format: "seed for title %016llX in seeddb.bin", programID)) }
                    let programBytes = try h.bytes(0x118, 8)
                    guard Crypto.sha256(seed + programBytes).prefix(4) == (try h.bytes(0x114, 4)) else { throw ConversionError.integrity("The title seed does not match.") }
                    extraY = Data(Crypto.sha256(y + seed).prefix(16))
                }
                extraKey = try keys.normalKey(slot: slot, y: extraY)
            }
        }
        func counter(_ section: UInt64) -> Data {
            var result = Data(repeating: 0, count: 16)
            result.put(partitionID, at: 0, width: 8, bigEndian: true)
            result[8] = UInt8(section)
            return result
        }
        func region(_ start: UInt64, _ length: UInt64, origin: UInt64, section: UInt64, key: Data) -> CryptoRegion {
            CryptoRegion(start: start, size: length, origin: origin, counter: counter(section), key: key)
        }
        if extSize > 0 {
            if encrypted { regions.append(region(0x200, 0x800, origin: 0x200, section: 1, key: mainKey)) }
            hashes.append(HashRegion(name: "extended header", start: 0x200, size: extSize, expected: try h.bytes(0x160, 32)))
        }
        if exefsSize > 0 {
            guard exefsSize >= 0x200 else { throw ConversionError.invalid("ExeFS is too short.") }
            let raw = try source.read(exefs, 0x200)
            let eh = encrypted ? try Crypto.ctr(raw, key: mainKey, counter: counter(2)) : raw
            let hashSize = try h.number(0x1a8, 4) * 0x200
            guard hashSize >= 0x200, hashSize <= exefsSize else { throw ConversionError.invalid("Invalid ExeFS hash region.") }
            hashes.append(HashRegion(name: "ExeFS header", start: exefs, size: hashSize, expected: try h.bytes(0x1c0, 32)))
            var entries: [(start: UInt64, size: UInt64, name: String)] = []
            for index in 0..<10 {
                let nameBytes = try eh.bytes(index * 16, 8)
                if nameBytes.allSatisfy({ $0 == 0 }) { continue }
                guard let name = String(data: Data(nameBytes.prefix(while: { $0 != 0 })), encoding: .ascii), !name.isEmpty else { throw ConversionError.integrity("The ExeFS directory could not be decrypted.") }
                let start = try eh.number(index * 16 + 8, 4) + 0x200
                let length = try eh.number(index * 16 + 12, 4)
                guard start >= 0x200, start <= exefsSize, length <= exefsSize - start,
                      !entries.contains(where: { start < $0.start + $0.size && $0.start < start + length }) else {
                    throw ConversionError.invalid("Invalid or overlapping ExeFS files.")
                }
                entries.append((start, length, name))
                hashes.append(HashRegion(name: "ExeFS \(name)", start: exefs + start, size: length, expected: try eh.bytes(0x1e0 - index * 32, 32)))
            }
            if encrypted {
                var cursor: UInt64 = 0
                for entry in entries.filter({ $0.name != "icon" && $0.name != "banner" && $0.size > 0 }).sorted(by: { $0.start < $1.start }) {
                    if cursor < entry.start { regions.append(region(exefs + cursor, entry.start - cursor, origin: exefs, section: 2, key: mainKey)) }
                    regions.append(region(exefs + entry.start, entry.size, origin: exefs, section: 2, key: extraKey))
                    cursor = entry.start + entry.size
                }
                if cursor < exefsSize { regions.append(region(exefs + cursor, exefsSize - cursor, origin: exefs, section: 2, key: mainKey)) }
            }
        }
        if romfsSize > 0 {
            let hashSize = try h.number(0x1b8, 4) * 0x200
            guard hashSize > 0, hashSize <= romfsSize else { throw ConversionError.invalid("Invalid RomFS hash region.") }
            hashes.append(HashRegion(name: "RomFS header", start: romfs, size: hashSize, expected: try h.bytes(0x1e0, 32)))
            if encrypted { regions.append(region(romfs, romfsSize, origin: romfs, section: 3, key: extraKey)) }
        }
    }

    func decrypt(_ data: Data, offset: UInt64) throws -> Data {
        var result = data
        for region in regions {
            let start = max(offset, region.start)
            let end = min(offset + UInt64(data.count), region.start + region.size)
            if start < end {
                let range = Int(start - offset)..<Int(end - offset)
                let decoded = try Crypto.ctr(data.subdata(in: range), key: region.key, counter: region.counter, offset: start - region.origin)
                result.replaceSubrange(range, with: decoded)
            }
        }
        return result
    }

    var decryptedHeader: Data {
        var header = originalHeader
        header[0x18b] = 0
        header[0x18f] = (header[0x18f] & ~0x21) | 4
        return header
    }

    func outputHeader(index: Int, baseID: UInt64) -> Data {
        var header = decryptedHeader
        if index > 0 {
            header.put((baseID & 0x0000ffffffffffff) | (UInt64(index + 4) << 48), at: 0x108, width: 8)
            header.put(baseID, at: 0x118, width: 8)
        }
        return header
    }
}
