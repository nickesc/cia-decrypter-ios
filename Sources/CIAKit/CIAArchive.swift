import Foundation

struct CIAContent {
    let record: Int
    let index: Int
    let offset: UInt64
    let size: UInt64
    let encrypted: Bool
    let hash: Data
}

struct CIAArchive {
    let titleID: UInt64
    let kind: CIATitleKind
    let saveSize: UInt64
    let contents: [CIAContent]
    let titleKey: Data?
    let tmdOffset: UInt64
    let tmdBody: Int
    let contentOffset: UInt64
    let contentEnd: UInt64
    let tmd: Data

    init(file: BinaryFile, keys: KeyMaterial) throws {
        let header = try file.read(0, 0x2020)
        guard try header.number(0, 4) == 0x2020 else { throw ConversionError.invalid("Not a CIA archive.") }
        let certSize = try header.number(8, 4)
        let ticketSize = try header.number(12, 4)
        let tmdSize = try header.number(16, 4)
        let metaSize = try header.number(20, 4)
        let contentSize = try header.number(24, 8)
        let ticketOffset = aligned(0x2020) + aligned(certSize)
        tmdOffset = ticketOffset + aligned(ticketSize)
        contentOffset = tmdOffset + aligned(tmdSize)
        guard contentOffset <= file.size, contentSize <= file.size - contentOffset,
              metaSize <= file.size - contentOffset - contentSize,
              contentOffset <= 8 * 1024 * 1024,
              tmdSize >= 0xa44, tmdSize <= 4 * 1024 * 1024, ticketSize <= 1024 * 1024 else {
            throw ConversionError.invalid("CIA sections are missing or extend beyond the file.")
        }
        tmd = try file.read(tmdOffset, Int(tmdSize))
        let body = try Self.signatureBody(tmd)
        tmdBody = body
        titleID = try tmd.number(body + 0x4c, 8, bigEndian: true)
        kind = try CIATitleKind(titleID: titleID)
        saveSize = try tmd.number(body + 0x5a, 4)
        let count = Int(try tmd.number(body + 0x9e, 2, bigEndian: true))
        guard count > 0, kind != .game || count <= 8 else { throw ConversionError.unsupported("This application has an unsupported content count.") }
        let chunksOffset = body + 0x9c4
        let chunkBytes = try tmd.bytes(chunksOffset, count * 0x30)
        let infoBytes = try tmd.bytes(body + 0xc4, 0x900)
        guard Crypto.sha256(infoBytes) == (try tmd.bytes(body + 0xa4, 32)) else {
            throw ConversionError.integrity("The title metadata hash does not match.")
        }
        var covered = Set<Int>()
        for offset in stride(from: 0, to: 0x900, by: 0x24) {
            let first = Int(try infoBytes.number(offset, 2, bigEndian: true))
            let amount = Int(try infoBytes.number(offset + 2, 2, bigEndian: true))
            if amount == 0 { continue }
            guard first <= count, amount <= count - first else { throw ConversionError.invalid("Invalid TMD content group.") }
            guard Crypto.sha256(try chunkBytes.bytes(first * 0x30, amount * 0x30)) == (try infoBytes.bytes(offset + 4, 32)) else {
                throw ConversionError.integrity("The content metadata hash does not match.")
            }
            for index in first..<(first + amount) {
                guard covered.insert(index).inserted else { throw ConversionError.invalid("Overlapping TMD content groups.") }
            }
        }
        guard covered.count == count else { throw ConversionError.invalid("The TMD does not describe every content.") }
        var active = Set<Int>()
        for index in 0..<65536 where header[0x20 + index / 8] & (0x80 >> (index % 8)) != 0 { active.insert(index) }
        var found = Set<Int>()
        var offset = contentOffset
        var records: [CIAContent] = []
        for record in 0..<count {
            let start = record * 0x30
            let index = Int(try chunkBytes.number(start + 4, 2, bigEndian: true))
            guard (kind != .game || index < 8), found.insert(index).inserted else { throw ConversionError.unsupported("This package has duplicate or unsupported content indices.") }
            if !active.contains(index) { continue }
            let size = try chunkBytes.number(start + 8, 8, bigEndian: true)
            let encrypted = try chunkBytes.number(start + 6, 2, bigEndian: true) & 1 != 0
            guard size >= 0x200, offset <= file.size, offset <= contentOffset + contentSize, size <= file.size - offset,
                  size <= contentOffset + contentSize - offset, !encrypted || size.isMultiple(of: 16) else {
                throw ConversionError.invalid("Invalid content size.")
            }
            records.append(CIAContent(record: record, index: index, offset: offset, size: size, encrypted: encrypted, hash: try chunkBytes.bytes(start + 16, 32)))
            offset += size
        }
        guard !records.isEmpty, (kind != .game || records.contains(where: { $0.index == 0 })), Set(records.map(\.index)) == active, offset == contentOffset + contentSize else {
            throw ConversionError.invalid("The CIA has missing content or an inconsistent content table.")
        }
        contentEnd = offset
        contents = records
        if contents.contains(where: \.encrypted) {
            let ticket = try file.read(ticketOffset, Int(ticketSize))
            let body = try Self.signatureBody(ticket)
            let ticketTitle = try ticket.number(body + 0x9c, 8, bigEndian: true)
            guard ticketTitle == titleID else { throw ConversionError.invalid("The ticket and title metadata identify different titles.") }
            let commonIndex = Int(try ticket.number(body + 0xb1, 1))
            guard commonIndex <= 5 else { throw ConversionError.invalid("Invalid common key index.") }
            var iv = Data(repeating: 0, count: 16)
            iv.put(titleID, at: 0, width: 8, bigEndian: true)
            titleKey = try Crypto.cbc(ticket.bytes(body + 0x7f, 16), key: keys.commonKey(index: commonIndex), iv: iv)
        } else {
            titleKey = nil
        }
    }

    static func signatureBody(_ data: Data) throws -> Int {
        switch try data.number(0, 4, bigEndian: true) {
        case 0x10000, 0x10003: return 0x240
        case 0x10001, 0x10004: return 0x140
        case 0x10002, 0x10005: return 0x80
        default: throw ConversionError.invalid("Unknown metadata signature format.")
        }
    }
}

struct ContentSource {
    let file: BinaryFile
    let content: CIAContent
    let titleKey: Data?

    func read(_ offset: UInt64, _ count: Int) throws -> Data {
        guard offset <= content.size, UInt64(count) <= content.size - offset else { throw ConversionError.invalid("Content range exceeds its size.") }
        guard content.encrypted else { return try file.read(content.offset + offset, count) }
        guard let titleKey else { throw ConversionError.missingKey("CIA title key") }
        let first = offset / 16 * 16
        let last = aligned(offset + UInt64(count), to: 16)
        var iv = Data(repeating: 0, count: 16)
        if first == 0 { iv.put(UInt64(content.index), at: 0, width: 2, bigEndian: true) }
        else { iv = try file.read(content.offset + first - 16, 16) }
        let encrypted = try file.read(content.offset + first, Int(last - first))
        return try Crypto.cbc(encrypted, key: titleKey, iv: iv).bytes(Int(offset - first), count)
    }
}
