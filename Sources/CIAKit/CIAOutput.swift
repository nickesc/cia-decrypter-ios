import Foundation

extension CIAArchive {
    func outputMetadata(hashes: [Int: Data]) throws -> Data {
        var result = tmd
        for content in contents {
            let record = tmdBody + 0x9c4 + content.record * 0x30
            let type = try result.number(record + 6, 2, bigEndian: true)
            result.put(type & ~1, at: record + 6, width: 2, bigEndian: true)
            guard let hash = hashes[content.record] else { throw ConversionError.integrity("Missing converted content hash.") }
            result.replaceSubrange((record + 16)..<(record + 48), with: hash)
        }
        for offset in stride(from: tmdBody + 0xc4, to: tmdBody + 0x9c4, by: 0x24) {
            let first = Int(try result.number(offset, 2, bigEndian: true))
            let amount = Int(try result.number(offset + 2, 2, bigEndian: true))
            if amount == 0 { continue }
            let chunks = try result.bytes(tmdBody + 0x9c4 + first * 0x30, amount * 0x30)
            result.replaceSubrange((offset + 4)..<(offset + 36), with: Crypto.sha256(chunks))
        }
        let infoHash = Crypto.sha256(try result.bytes(tmdBody + 0xc4, 0x900))
        result.replaceSubrange((tmdBody + 0xa4)..<(tmdBody + 0xc4), with: infoHash)
        return result
    }

    func validateCheckpoint(_ saved: Data, original: Data) throws {
        var normalized = saved
        let start = Int(tmdOffset)
        func restore(_ range: Range<Int>) {
            let absolute = (start + range.lowerBound)..<(start + range.upperBound)
            normalized.replaceSubrange(absolute, with: original[absolute])
        }
        // Finalization rewrites only these fields. Rebuild them from verified contents on resume.
        restore((tmdBody + 0xa4)..<(tmdBody + 0xc4))
        for offset in stride(from: tmdBody + 0xc4, to: tmdBody + 0x9c4, by: 0x24) {
            restore((offset + 4)..<(offset + 36))
        }
        for content in contents {
            let record = tmdBody + 0x9c4 + content.record * 0x30
            restore((record + 6)..<(record + 8))
            restore((record + 16)..<(record + 48))
        }
        guard normalized == original else { throw ConversionError.integrity("The saved conversion does not match this CIA. Redo the conversion.") }
    }
}
