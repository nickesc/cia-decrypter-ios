import XCTest
@testable import CIAKit

final class ConversionTests: XCTestCase {
    func testNISTAESVectorsAndRandomAccess() throws {
        let key = Data(hex: "2b7e151628aed2a6abf7158809cf4f3c")!
        let plaintext = Data(hex: "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51")!
        let iv = Data(hex: "000102030405060708090a0b0c0d0e0f")!
        let cbc = Data(hex: "7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2")!
        XCTAssertEqual(try Crypto.cbc(cbc, key: key, iv: iv), plaintext)
        let counter = Data(hex: "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")!
        let ctr = Data(hex: "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff")!
        XCTAssertEqual(try Crypto.ctr(ctr, key: key, counter: counter), plaintext)
        XCTAssertEqual(try Crypto.ctr(ctr.bytes(7, 23), key: key, counter: counter, offset: 7), try plaintext.bytes(7, 23))
    }

    func testDecryptedConversionAndOriginalPreservation() throws {
        try checkFixture(encrypted: false, seeded: false)
    }

    func testBothEncryptionLayersAndMixedExeFSKeys() throws {
        try checkFixture(encrypted: true, seeded: false)
    }

    func testSeededEncryption() throws {
        try checkFixture(encrypted: true, seeded: true)
    }

    func testWrongKeyAndCorruptionNeverLeaveAnOutput() throws {
        let fixture = try Fixture(encrypted: true, seeded: true)
        try withDirectory { root in
            let input = root.appendingPathComponent("input.cia")
            let output = root.appendingPathComponent("output.3ds")
            try fixture.cia.write(to: input)
            var wrong = fixture.keys
            wrong.keys["slot0x18keyx"] = Data(repeating: 0xf1, count: 16)
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: wrong))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathExtension("partial").path))
            var corrupt = fixture.cia
            corrupt[corrupt.count - 1] ^= 0x80
            try corrupt.write(to: input)
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: fixture.keys))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testMissingKeysCancellationAndTruncation() throws {
        let fixture = try Fixture(encrypted: true, seeded: false)
        try withDirectory { root in
            let input = root.appendingPathComponent("input.cia")
            let output = root.appendingPathComponent("output.3ds")
            try fixture.cia.write(to: input)
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: .init())) {
                guard case ConversionError.missingKey = $0 else { return XCTFail("Expected missing key") }
            }
            let control = ConversionControl()
            control.cancel()
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: fixture.keys, control: control)) {
                XCTAssertEqual($0 as? ConversionError, .cancelled)
            }
            try fixture.cia.prefix(100).write(to: input)
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: fixture.keys))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testKeyImportsValidateWithoutLeakingValues() throws {
        var keys = KeyMaterial()
        try keys.load(Data(":AES\nslot0x2CKeyX=00112233445566778899aabbccddeeff\ncommon0=ffeeddccbbaa99887766554433221100\n:OTHER\nignored=bad\n".utf8), kind: .aes)
        XCTAssertEqual(keys.keyCount, 2)
        XCTAssertThrowsError(try keys.load(Data("slot0x2CKeyX=not-a-key".utf8), kind: .aes))
        XCTAssertEqual(keys.keyCount, 2)
        XCTAssertThrowsError(try keys.load(Data(repeating: 0, count: 0x10000), kind: .boot9))
        var db = Data(repeating: 0, count: 48)
        db.put(1, at: 0, width: 4)
        db.put(Fixture.title, at: 16, width: 8)
        db.replaceSubrange(24..<40, with: Data(repeating: 0xab, count: 16))
        try keys.load(db, kind: .seeds)
        XCTAssertEqual(keys.seedCount, 1)
        XCTAssertThrowsError(try keys.load(db.prefix(47), kind: .seeds))
    }

    func testLateCancellationAndMissingSeedKeepNoPartialOutput() throws {
        let fixture = try Fixture(encrypted: true, seeded: true)
        try withDirectory { root in
            let input = root.appendingPathComponent("input.cia")
            let output = root.appendingPathComponent("output.3ds")
            try fixture.cia.write(to: input)
            var missingSeed = fixture.keys
            missingSeed.seeds.removeAll()
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: missingSeed)) {
                guard case ConversionError.missingKey = $0 else { return XCTFail("Expected missing seed") }
            }
            let control = ConversionControl()
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: fixture.keys, control: control) { progress in
                if progress.fraction > 0 { control.cancel() }
            }) { XCTAssertEqual($0 as? ConversionError, .cancelled) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathExtension("partial").path))
        }
    }

    func testUnsupportedTitleAndStoragePreflight() throws {
        let fixture = try Fixture(encrypted: false, seeded: false)
        try withDirectory { root in
            var cia = fixture.cia
            let ticketOffset = aligned(0x2020)
            let tmdOffset = ticketOffset + aligned(0x350)
            cia.put(0x0004000e01234500, at: Int(tmdOffset) + 0x140 + 0x4c, width: 8, bigEndian: true)
            let input = root.appendingPathComponent("update.cia")
            try cia.write(to: input)
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: root.appendingPathComponent("output.3ds"), keys: fixture.keys)) {
                guard case ConversionError.unsupported = $0 else { return XCTFail("Expected unsupported title") }
            }
            XCTAssertThrowsError(try CIAConverter.checkStorage(at: root, required: UInt64(Int64.max))) {
                XCTAssertEqual($0 as? ConversionError, .lowStorage)
            }
        }
    }

    private func checkFixture(encrypted: Bool, seeded: Bool) throws {
        let fixture = try Fixture(encrypted: encrypted, seeded: seeded)
        try withDirectory { root in
            let input = root.appendingPathComponent("input.cia")
            let output = root.appendingPathComponent("output.3ds")
            try fixture.cia.write(to: input)
            let result = try CIAConverter.convert(input: input, output: output, keys: fixture.keys)
            let data = try Data(contentsOf: output)
            XCTAssertEqual(result.titleID, Fixture.title)
            XCTAssertEqual(try data.bytes(0x100, 4), Data("NCSD".utf8))
            XCTAssertEqual(try data.number(0x120, 4), 0x20)
            XCTAssertEqual(data[0x4000 + 0x18f] & 0x25, 4)
            XCTAssertEqual(data[0x4000 + 0x18b], 0)
            XCTAssertEqual(try data.bytes(0x4200, fixture.plain.count - 0x200), try fixture.plain.bytes(0x200, fixture.plain.count - 0x200))
            XCTAssertEqual(try Data(contentsOf: input), fixture.cia)
        }
    }
}

func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CIAKitTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

struct Fixture {
    static let title: UInt64 = 0x0004000001234500
    let cia: Data
    let plain: Data
    let keys: KeyMaterial

    init(encrypted: Bool, seeded: Bool) throws {
        var keys = KeyMaterial()
        keys.keys["slot0x2ckeyx"] = Data(repeating: 0x12, count: 16)
        keys.keys["slot0x18keyx"] = Data(repeating: 0x34, count: 16)
        keys.keys["slot0x3dkeyx"] = Data(repeating: 0x56, count: 16)
        keys.keys["common0"] = Data(repeating: 0x78, count: 16)
        let seed = Data(repeating: 0x9a, count: 16)
        keys.seeds[Self.title] = seed
        var ncch = Data(repeating: 0, count: 0x1800)
        ncch.replaceSubrange(0..<16, with: Data(repeating: 0xbc, count: 16))
        ncch.replaceSubrange(0x100..<0x104, with: Data("NCCH".utf8))
        ncch.put(UInt64(ncch.count / 0x200), at: 0x104, width: 4)
        ncch.put(Self.title, at: 0x108, width: 8)
        ncch.put(2, at: 0x112, width: 2)
        ncch.put(Self.title, at: 0x118, width: 8)
        ncch.put(0x400, at: 0x180, width: 4)
        ncch[0x18b] = encrypted ? 0x0a : 0
        ncch[0x18d] = 2
        ncch[0x18f] = encrypted ? (seeded ? 0x20 : 0) : 4
        ncch.put(5, at: 0x1a0, width: 4)
        ncch.put(3, at: 0x1a4, width: 4)
        ncch.put(1, at: 0x1a8, width: 4)
        ncch.put(8, at: 0x1b0, width: 4)
        ncch.put(4, at: 0x1b4, width: 4)
        ncch.put(1, at: 0x1b8, width: 4)
        for index in 0x200..<0xa00 { ncch[index] = UInt8(truncatingIfNeeded: index * 7) }
        var exefs = Data(repeating: 0, count: 0x600)
        exefs.replaceSubrange(0..<5, with: Data(".code".utf8))
        exefs.put(257, at: 12, width: 4)
        exefs.replaceSubrange(16..<20, with: Data("icon".utf8))
        exefs.put(0x200, at: 24, width: 4)
        exefs.put(100, at: 28, width: 4)
        for index in 0x200..<0x301 { exefs[index] = UInt8(truncatingIfNeeded: index * 11) }
        for index in 0x400..<0x464 { exefs[index] = UInt8(truncatingIfNeeded: index * 13) }
        exefs.replaceSubrange(0x1e0..<0x200, with: Crypto.sha256(try exefs.bytes(0x200, 257)))
        exefs.replaceSubrange(0x1c0..<0x1e0, with: Crypto.sha256(try exefs.bytes(0x400, 100)))
        ncch.replaceSubrange(0xa00..<0x1000, with: exefs)
        for index in 0x1000..<0x1800 { ncch[index] = UInt8(truncatingIfNeeded: index * 17) }
        ncch.replaceSubrange(0x160..<0x180, with: Crypto.sha256(try ncch.bytes(0x200, 0x400)))
        ncch.replaceSubrange(0x1c0..<0x1e0, with: Crypto.sha256(try exefs.bytes(0, 0x200)))
        ncch.replaceSubrange(0x1e0..<0x200, with: Crypto.sha256(try ncch.bytes(0x1000, 0x200)))
        if seeded { ncch.replaceSubrange(0x114..<0x118, with: Crypto.sha256(seed + (try ncch.bytes(0x118, 8))).prefix(4)) }
        plain = ncch
        if encrypted {
            let y = try ncch.bytes(0, 16)
            let main = try keys.normalKey(slot: 0x2c, y: y)
            let extra = try keys.normalKey(slot: 0x18, y: seeded ? Data(Crypto.sha256(y + seed).prefix(16)) : y)
            func counter(_ section: UInt8) -> Data {
                var iv = Data(repeating: 0, count: 16)
                iv.put(Self.title, at: 0, width: 8, bigEndian: true)
                iv[8] = section
                return iv
            }
            ncch.replaceSubrange(0x200..<0xa00, with: try Crypto.ctr(ncch.bytes(0x200, 0x800), key: main, counter: counter(1)))
            var encExe = try Crypto.ctr(exefs, key: main, counter: counter(2))
            encExe.replaceSubrange(0x200..<0x301, with: try Crypto.ctr(exefs.bytes(0x200, 257), key: extra, counter: counter(2), offset: 0x200))
            ncch.replaceSubrange(0xa00..<0x1000, with: encExe)
            ncch.replaceSubrange(0x1000..<0x1800, with: try Crypto.ctr(ncch.bytes(0x1000, 0x800), key: extra, counter: counter(3)))
        }
        let contentHash = Crypto.sha256(ncch)
        let titleKey = Data(repeating: 0xde, count: 16)
        var ticket = Data(repeating: 0, count: 0x350)
        ticket.put(0x10004, at: 0, width: 4, bigEndian: true)
        ticket.put(Self.title, at: 0x1dc, width: 8, bigEndian: true)
        var titleIV = Data(repeating: 0, count: 16)
        titleIV.put(Self.title, at: 0, width: 8, bigEndian: true)
        ticket.replaceSubrange(0x1bf..<0x1cf, with: try Crypto.cbc(titleKey, key: keys.commonKey(index: 0), iv: titleIV, encrypt: true))
        if encrypted { ncch = try Crypto.cbc(ncch, key: titleKey, iv: Data(repeating: 0, count: 16), encrypt: true) }
        var tmd = Data(repeating: 0, count: 0x140 + 0x9c4 + 0x30)
        tmd.put(0x10004, at: 0, width: 4, bigEndian: true)
        tmd.put(Self.title, at: 0x140 + 0x4c, width: 8, bigEndian: true)
        tmd.put(1, at: 0x140 + 0x9e, width: 2, bigEndian: true)
        let cr = 0x140 + 0x9c4
        tmd.put(encrypted ? 1 : 0, at: cr + 6, width: 2, bigEndian: true)
        tmd.put(UInt64(ncch.count), at: cr + 8, width: 8, bigEndian: true)
        tmd.replaceSubrange((cr + 16)..<(cr + 48), with: contentHash)
        let ir = 0x140 + 0xc4
        tmd.put(1, at: ir + 2, width: 2, bigEndian: true)
        tmd.replaceSubrange((ir + 4)..<(ir + 36), with: Crypto.sha256(try tmd.bytes(cr, 0x30)))
        tmd.replaceSubrange((0x140 + 0xa4)..<(0x140 + 0xc4), with: Crypto.sha256(try tmd.bytes(ir, 0x900)))
        let ticketOffset = Int(aligned(0x2020))
        let tmdOffset = ticketOffset + Int(aligned(UInt64(ticket.count)))
        let contentOffset = tmdOffset + Int(aligned(UInt64(tmd.count)))
        var cia = Data(repeating: 0, count: contentOffset + ncch.count)
        cia.put(0x2020, at: 0, width: 4)
        cia.put(UInt64(ticket.count), at: 12, width: 4)
        cia.put(UInt64(tmd.count), at: 16, width: 4)
        cia.put(UInt64(ncch.count), at: 24, width: 8)
        cia[0x20] = 0x80
        cia.replaceSubrange(ticketOffset..<(ticketOffset + ticket.count), with: ticket)
        cia.replaceSubrange(tmdOffset..<(tmdOffset + tmd.count), with: tmd)
        cia.replaceSubrange(contentOffset..<cia.count, with: ncch)
        self.cia = cia
        self.keys = keys
    }
}
