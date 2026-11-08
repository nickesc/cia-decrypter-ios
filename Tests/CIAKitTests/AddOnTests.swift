import XCTest
@testable import CIAKit

final class AddOnTests: XCTestCase {
    func testUpdatesAndSparseDLCBecomeInstallableDecryptedCIAs() throws {
        for kind in [CIATitleKind.update, .dlc] {
            for encrypted in [false, true] {
                let fixture = try AddOnFixture(kind: kind, encrypted: encrypted)
                try withDirectory { root in
                    let input = root.appendingPathComponent("source.cia")
                    let output = root.appendingPathComponent(kind.outputName(for: "source.cia"))
                    try fixture.cia.write(to: input)
                    XCTAssertEqual(try CIAConverter.titleKind(input: input), kind)
                    let result = try CIAConverter.convert(input: input, output: output, keys: fixture.keys)
                    let data = try Data(contentsOf: output)
                    XCTAssertEqual(result.titleID, fixture.title)
                    XCTAssertEqual(result.bytes, UInt64(fixture.cia.count))
                    XCTAssertEqual(data.count, fixture.cia.count)
                    XCTAssertEqual(try Data(contentsOf: input), fixture.cia)
                    try fixture.verify(data)
                    // The rebuilt metadata and unencrypted content must also parse without keys.
                    let parsed = try CIAArchive(file: BinaryFile(output), keys: .init())
                    XCTAssertNil(parsed.titleKey)
                    XCTAssertEqual(parsed.contents.map(\.index), fixture.indices)
                    // Decrypting the output again is idempotent.
                    let second = root.appendingPathComponent("second.cia")
                    _ = try CIAConverter.convert(input: output, output: second, keys: .init())
                    XCTAssertEqual(try Data(contentsOf: second), data)
                }
            }
        }
    }

    func testAddOnResumeVerifiesRetainedBytesAndRebuildsMetadata() throws {
        let fixture = try AddOnFixture(kind: .dlc, encrypted: true, romfsSize: 3 * 1024 * 1024)
        try withDirectory { root in
            let input = root.appendingPathComponent("source.cia")
            let output = root.appendingPathComponent("output.cia")
            let partial = output.appendingPathExtension("partial")
            try fixture.cia.write(to: input)
            let control = ConversionControl()
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: fixture.keys, control: control, resumable: true) { progress in
                if progress.fraction > 0 { control.pause() }
            }) { XCTAssertEqual($0 as? ConversionError, .paused) }
            var retained = try Data(contentsOf: partial)
            XCTAssertGreaterThan(retained.count, fixture.contentOffset)
            XCTAssertLessThan(retained.count, fixture.cia.count)
            // A process can stop while finalization rewrites metadata. These fields are rebuilt.
            retained[fixture.tmdOffset + 0x140 + 0xa4] ^= 1
            try retained.write(to: partial)
            _ = try CIAConverter.convert(input: input, output: output, keys: fixture.keys, resumable: true)
            let data = try Data(contentsOf: output)
            XCTAssertEqual(data[fixture.contentOffset..<retained.count], retained[fixture.contentOffset...])
            try fixture.verify(data)
            XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        }
    }

    func testAddOnDamageAndCancellationNeverPublishAnOutput() throws {
        let fixture = try AddOnFixture(kind: .update, encrypted: true, romfsSize: 2 * 1024 * 1024)
        try withDirectory { root in
            let input = root.appendingPathComponent("source.cia")
            let output = root.appendingPathComponent("output.cia")
            let partial = output.appendingPathExtension("partial")
            try fixture.cia.write(to: input)
            let pause = ConversionControl()
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: fixture.keys, control: pause, resumable: true) { progress in
                if progress.fraction > 0 { pause.pause() }
            })
            var damaged = try Data(contentsOf: partial)
            damaged[fixture.contentOffset + 0x250] ^= 1
            try damaged.write(to: partial)
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: fixture.keys, resumable: true)) {
                guard case ConversionError.integrity = $0 else { return XCTFail("Expected damaged checkpoint rejection") }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
            let cancel = ConversionControl()
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: fixture.keys, control: cancel, resumable: true) { progress in
                if progress.fraction > 0 { cancel.cancel() }
            }) { XCTAssertEqual($0 as? ConversionError, .cancelled) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
            damaged = fixture.cia
            damaged[fixture.contentOffset + 0x250] ^= 1
            try damaged.write(to: input)
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: fixture.keys))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        }
    }

    func testAddOnsRejectCardImageOutputAndKeepOriginalFiles() throws {
        let fixture = try AddOnFixture(kind: .update, encrypted: false)
        try withDirectory { root in
            let input = root.appendingPathComponent("source.cia")
            let output = root.appendingPathComponent("output.3ds")
            try fixture.cia.write(to: input)
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: output, keys: .init()))
            XCTAssertThrowsError(try CIAConverter.convert(input: input, output: input, keys: .init()))
            XCTAssertEqual(try Data(contentsOf: input), fixture.cia)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testPartialDLCInstallationPreservesAbsentContentMetadata() throws {
        let fixture = try AddOnFixture(kind: .dlc, encrypted: true)
        try withDirectory { root in
            var source = fixture.cia
            let missing = fixture.indices.last!
            source[0x20 + missing / 8] &= ~(0x80 >> (missing % 8))
            source.put(UInt64((fixture.indices.count - 1) * fixture.plain.count), at: 24, width: 8)
            let removedStart = fixture.contentOffset + (fixture.indices.count - 1) * fixture.plain.count
            source.removeSubrange(removedStart..<(removedStart + fixture.plain.count))
            let input = root.appendingPathComponent("partial-install.cia")
            let output = root.appendingPathComponent("decrypted.cia")
            try source.write(to: input)
            _ = try CIAConverter.convert(input: input, output: output, keys: fixture.keys)
            let result = try CIAArchive(file: BinaryFile(output), keys: .init())
            XCTAssertEqual(result.contents.map(\.index), Array(fixture.indices.dropLast()))
            let data = try Data(contentsOf: output)
            let absentRecord = fixture.tmdOffset + 0x140 + 0x9c4 + (fixture.indices.count - 1) * 0x30
            XCTAssertEqual(try data.bytes(absentRecord, 0x30), try source.bytes(absentRecord, 0x30))
            XCTAssertEqual(data.suffix(37), source.suffix(37))
        }
    }
}

private struct AddOnFixture {
    let cia: Data
    let plain: Data
    let keys: KeyMaterial
    let title: UInt64
    let indices = [511, 3, 17, 9, 100, 5, 8192, 8, 65535]
    let tmdOffset: Int
    let contentOffset: Int

    init(kind: CIATitleKind, encrypted: Bool, romfsSize: Int = 0x800) throws {
        let fixture = try Fixture(encrypted: encrypted, seeded: encrypted, romfsSize: romfsSize)
        keys = fixture.keys
        plain = fixture.plain
        title = (kind == .update ? 0x0004000e00000000 : 0x0004008c00000000) | (Fixture.title & 0xffffffff)
        let ticketOffset = Int(aligned(0x2020))
        let oldTMD = ticketOffset + Int(aligned(0x350))
        let oldContent = oldTMD + Int(aligned(0x140 + 0x9c4 + 0x30))
        let titleKey = Data(repeating: 0xde, count: 16)
        let content = encrypted ? try Crypto.cbc(fixture.cia.bytes(oldContent, plain.count), key: titleKey, iv: Data(repeating: 0, count: 16)) : plain
        var ticket = try fixture.cia.bytes(ticketOffset, 0x350)
        ticket.put(title, at: 0x1dc, width: 8, bigEndian: true)
        var titleIV = Data(repeating: 0, count: 16)
        titleIV.put(title, at: 0, width: 8, bigEndian: true)
        ticket.replaceSubrange(0x1bf..<0x1cf, with: try Crypto.cbc(titleKey, key: keys.commonKey(index: 0), iv: titleIV, encrypt: true))
        var tmd = Data(repeating: 0, count: 0x140 + 0x9c4 + indices.count * 0x30)
        tmd.put(0x10004, at: 0, width: 4, bigEndian: true)
        tmd.put(title, at: 0x140 + 0x4c, width: 8, bigEndian: true)
        tmd.put(UInt64(indices.count), at: 0x140 + 0x9e, width: 2, bigEndian: true)
        var contents = Data()
        for (record, index) in indices.enumerated() {
            let cr = 0x140 + 0x9c4 + record * 0x30
            tmd.put(UInt64(0x12340000 + record), at: cr, width: 4, bigEndian: true)
            tmd.put(UInt64(index), at: cr + 4, width: 2, bigEndian: true)
            tmd.put(encrypted ? 0x4001 : 0x4000, at: cr + 6, width: 2, bigEndian: true)
            tmd.put(UInt64(content.count), at: cr + 8, width: 8, bigEndian: true)
            tmd.replaceSubrange((cr + 16)..<(cr + 48), with: Crypto.sha256(content))
            var iv = Data(repeating: 0, count: 16)
            iv.put(UInt64(index), at: 0, width: 2, bigEndian: true)
            contents.append(encrypted ? try Crypto.cbc(content, key: titleKey, iv: iv, encrypt: true) : content)
        }
        for (group, range) in [0..<2, 2..<indices.count].enumerated() {
            let ir = 0x140 + 0xc4 + group * 0x24
            tmd.put(UInt64(range.lowerBound), at: ir, width: 2, bigEndian: true)
            tmd.put(UInt64(range.count), at: ir + 2, width: 2, bigEndian: true)
            tmd.replaceSubrange((ir + 4)..<(ir + 36), with: Crypto.sha256(try tmd.bytes(0x140 + 0x9c4 + range.lowerBound * 0x30, range.count * 0x30)))
        }
        tmd.replaceSubrange(0x1e4..<0x204, with: Crypto.sha256(try tmd.bytes(0x204, 0x900)))
        tmdOffset = ticketOffset + Int(aligned(UInt64(ticket.count)))
        contentOffset = tmdOffset + Int(aligned(UInt64(tmd.count)))
        var cia = Data(repeating: 0, count: contentOffset)
        cia.put(0x2020, at: 0, width: 4)
        cia.put(UInt64(ticket.count), at: 12, width: 4)
        cia.put(UInt64(tmd.count), at: 16, width: 4)
        cia.put(37, at: 20, width: 4)
        cia.put(UInt64(contents.count), at: 24, width: 8)
        for index in indices { cia[0x20 + index / 8] |= 0x80 >> (index % 8) }
        cia.replaceSubrange(ticketOffset..<(ticketOffset + ticket.count), with: ticket)
        cia.replaceSubrange(tmdOffset..<(tmdOffset + tmd.count), with: tmd)
        cia.append(contents)
        cia.append(Data(repeating: 0xa7, count: 37))
        self.cia = cia
    }

    func verify(_ data: Data) throws {
        XCTAssertEqual(data.prefix(tmdOffset), cia.prefix(tmdOffset))
        XCTAssertEqual(data.suffix(37), cia.suffix(37))
        let body = tmdOffset + 0x140
        XCTAssertEqual(try data.number(body + 0x4c, 8, bigEndian: true), title)
        var expected = plain
        expected[0x18b] = 0
        expected[0x18f] = (expected[0x18f] & ~0x21) | 4
        for (record, index) in indices.enumerated() {
            let cr = body + 0x9c4 + record * 0x30
            XCTAssertEqual(try data.number(cr, 4, bigEndian: true), UInt64(0x12340000 + record))
            XCTAssertEqual(try data.number(cr + 4, 2, bigEndian: true), UInt64(index))
            XCTAssertEqual(try data.number(cr + 6, 2, bigEndian: true), 0x4000)
            XCTAssertEqual(try data.bytes(cr + 16, 32), Crypto.sha256(expected))
            XCTAssertEqual(try data.bytes(contentOffset + record * plain.count, plain.count), expected)
        }
        for (group, range) in [0..<2, 2..<indices.count].enumerated() {
            let ir = body + 0xc4 + group * 0x24
            XCTAssertEqual(try data.bytes(ir + 4, 32), Crypto.sha256(try data.bytes(body + 0x9c4 + range.lowerBound * 0x30, range.count * 0x30)))
        }
        XCTAssertEqual(try data.bytes(body + 0xa4, 32), Crypto.sha256(try data.bytes(body + 0xc4, 0x900)))
    }
}
