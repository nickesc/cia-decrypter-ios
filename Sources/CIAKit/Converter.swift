import Foundation
import CryptoKit

public final class ConversionControl: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: ConversionError?
    public init() {}
    public func cancel() { lock.withLock { reason = .cancelled } }
    public func pause() { lock.withLock { if reason != .cancelled { reason = .paused } } }
    public func interrupt() { lock.withLock { if reason == nil { reason = .interrupted } } }
    public func check() throws {
        if let reason = lock.withLock({ reason }) { throw reason }
    }
}

public struct ConversionProgress: Sendable {
    public let fraction: Double
    public let phase: String
}

public struct ConversionResult: Sendable {
    public let outputURL: URL
    public let titleID: UInt64
    public let bytes: UInt64
}

public enum CIAConverter {
    public static func titleKind(input: URL) throws -> CIATitleKind {
        let file = try BinaryFile(input)
        let header = try file.read(0, 0x20)
        guard try header.number(0, 4) == 0x2020 else { throw ConversionError.invalid("Not a CIA archive.") }
        let ticket = aligned(0x2020) + aligned(try header.number(8, 4))
        let tmd = ticket + aligned(try header.number(12, 4))
        let body = try CIAArchive.signatureBody(file.read(tmd, 4))
        guard try header.number(16, 4) >= UInt64(body + 0x54) else { throw ConversionError.invalid("The title metadata is truncated.") }
        return try CIATitleKind(titleID: file.read(tmd + UInt64(body + 0x4c), 8).number(0, 8, bigEndian: true))
    }

    public static func convert(input: URL, output: URL, keys: KeyMaterial, control: ConversionControl = .init(), resumable: Bool = false, progress: @Sendable (ConversionProgress) -> Void = { _ in }) throws -> ConversionResult {
        guard input.standardizedFileURL != output.standardizedFileURL else { throw ConversionError.invalid("Input and output must be different files.") }
        let fm = FileManager.default
        let partial = output.appendingPathExtension("partial")
        guard input.standardizedFileURL != partial.standardizedFileURL else { throw ConversionError.invalid("Input and partial output must be different files.") }
        guard !fm.fileExists(atPath: output.path), resumable || !fm.fileExists(atPath: partial.path) else { throw ConversionError.invalid("An output with this name already exists.") }
        do {
            return try process(input: input, output: output, keys: keys, control: control, resumable: resumable, progress: progress)
        } catch {
            let recoverable = error as? ConversionError == .paused || error as? ConversionError == .interrupted || isStorageError(error)
            let size = (try? fm.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.uint64Value ?? 0
            if !resumable || !recoverable || size < 0x2020 { try? fm.removeItem(at: partial) }
            throw error
        }
    }

    private static func process(input: URL, output: URL, keys: KeyMaterial, control: ConversionControl, resumable: Bool, progress: @Sendable (ConversionProgress) -> Void) throws -> ConversionResult {
        try control.check()
        let file = try BinaryFile(input)
        let archive = try CIAArchive(file: file, keys: keys)
        let isCIA = archive.kind != .game
        guard !isCIA || output.pathExtension.lowercased() == "cia" else {
            throw ConversionError.invalid("Updates and DLC must be exported as decrypted .cia files, not .3ds images.")
        }
        progress(.init(fraction: 0, phase: "Checking contents"))
        let contents = isCIA ? archive.contents : archive.contents.sorted { $0.index < $1.index }
        var plans: [(CIAContent, ContentSource, NCCHPlan, UInt64)] = []
        var end: UInt64 = isCIA ? file.size : 0x4000
        for content in contents where !isCIA {
            try control.check()
            let source = ContentSource(file: file, content: content, titleKey: archive.titleKey)
            let plan = try NCCHPlan(source: source, keys: keys)
            plans.append((content, source, plan, end))
            end += aligned(plan.size, to: 0x200)
        }
        let fm = FileManager.default
        let partial = output.appendingPathExtension("partial")
        let saved = resumable && fm.fileExists(atPath: partial.path) ? try BinaryFile(partial) : nil
        if saved == nil { try Data().write(to: partial, options: .withoutOverwriting) }
        let out = try FileHandle(forWritingTo: partial)
        defer {
            if resumable { try? out.synchronize() }
            try? out.close()
        }
        let baseID = plans.first?.2.partitionID ?? 0
        var cci = Data(repeating: 0, count: 0x4000)
        if isCIA {
            cci = try file.read(0, Int(archive.contentOffset))
        } else {
            cci.replaceSubrange(0..<0x100, with: Data(repeating: 0xff, count: 0x100))
            cci.replaceSubrange(0x100..<0x104, with: Data("NCSD".utf8))
            var mediaSize: UInt64 = 128 * 1024 * 1024
            while mediaSize < end + archive.saveSize && mediaSize < 8 * 1024 * 1024 * 1024 { mediaSize *= 2 }
            guard end + archive.saveSize <= mediaSize else { throw ConversionError.unsupported("The game exceeds the supported card-image size.") }
            cci.put(mediaSize / 0x200, at: 0x104, width: 4)
            cci.put(baseID, at: 0x108, width: 8)
            cci[0x18b] = 2
            cci[0x18c] = 1
            cci[0x18d] = archive.saveSize >= 1024 * 1024 ? 2 : 1
            cci.put(archive.saveSize >= 1024 * 1024 ? end / 0x200 : 0xffffffff, at: 0x200, width: 4)
            cci.put(end, at: 0x300, width: 8)
            for (content, _, plan, offset) in plans {
                let header = plan.outputHeader(index: content.index, baseID: baseID)
                cci.put(offset / 0x200, at: 0x120 + content.index * 8, width: 4)
                cci.put(plan.size / 0x200, at: 0x124 + content.index * 8, width: 4)
                cci.replaceSubrange((0x190 + content.index * 8)..<(0x198 + content.index * 8), with: try header.bytes(0x108, 8))
                if content.index == 0 { cci.replaceSubrange(0x1100..<0x1200, with: try header.bytes(0x100, 0x100)) }
            }
        }
        let headerSize = UInt64(cci.count)
        if let saved {
            guard saved.size >= headerSize, saved.size <= end else {
                throw ConversionError.integrity("The saved conversion does not match this CIA. Redo the conversion.")
            }
            let savedHeader = try saved.read(0, cci.count)
            if isCIA { try archive.validateCheckpoint(savedHeader, original: cci) }
            else if savedHeader != cci { throw ConversionError.integrity("The saved conversion does not match this CIA. Redo the conversion.") }
        } else { try out.write(contentsOf: cci) }
        try checkStorage(at: output.deletingLastPathComponent(), required: end - (saved?.size ?? headerSize))
        let total = contents.reduce(UInt64(0)) { $0 + $1.size }
        let savedBytes = min(total, (saved?.size ?? headerSize) - headerSize)
        func writeVerified(_ data: Data, at position: UInt64) throws {
            let savedLength = saved?.size ?? 0
            let retained = Int(min(UInt64(data.count), savedLength > position ? savedLength - position : 0))
            if let saved, retained > 0, try saved.read(position, retained) != data.prefix(retained) {
                throw ConversionError.integrity("The saved conversion is damaged. Redo the conversion.")
            }
            if retained < data.count {
                try out.seek(toOffset: position + UInt64(retained))
                try out.write(contentsOf: data[retained...])
            }
        }
        var outputHashes: [Int: Data] = [:]
        var completed: UInt64 = 0
        var lastStorageCheck: UInt64 = 0
        var lastProgress = Date.distantPast
        for (index, content) in contents.enumerated() {
            try control.check()
            // CIA packages can have thousands of contents; retain one NCCH plan at a time.
            let source = isCIA ? ContentSource(file: file, content: content, titleKey: archive.titleKey) : plans[index].1
            let plan = isCIA ? try NCCHPlan(source: source, keys: keys) : plans[index].2
            let destination = isCIA ? content.offset : plans[index].3
            var rawHash = SHA256()
            var outputHash = SHA256()
            var checks = plan.hashes
            var offset: UInt64 = 0
            while offset < content.size {
                // FileHandle returns Foundation temporaries; release each chunk on long-lived worker threads.
                try autoreleasepool {
                    try control.check()
                    let count = Int(min(1024 * 1024, content.size - offset))
                    if completed - lastStorageCheck >= 16 * 1024 * 1024 {
                        try checkStorage(at: output.deletingLastPathComponent(), required: UInt64(count))
                        lastStorageCheck = completed
                    }
                    let raw = try source.read(offset, count)
                    rawHash.update(data: raw)
                    var decrypted = try plan.decrypt(raw, offset: offset)
                    for index in checks.indices { checks[index].update(decrypted, offset: offset) }
                    if offset == 0 { decrypted.replaceSubrange(0..<0x200, with: isCIA ? plan.decryptedHeader : plan.outputHeader(index: content.index, baseID: baseID)) }
                    if isCIA { outputHash.update(data: decrypted) }
                    let outputSize = isCIA ? content.size : plan.size
                    if offset < outputSize {
                        let outputCount = min(count, Int(outputSize - offset))
                        let position = destination + offset
                        // Rebuild integrity hashes and verify retained bytes; only write the missing suffix.
                        try writeVerified(Data(decrypted.prefix(outputCount)), at: position)
                    }
                    offset += UInt64(count)
                    completed += UInt64(count)
                    if Date().timeIntervalSince(lastProgress) >= 0.1 {
                        progress(.init(fraction: Double(max(completed, savedBytes)) / Double(total) * 0.99, phase: completed < savedBytes ? "Checking saved progress" : "Decrypting and verifying"))
                        lastProgress = Date()
                    }
                }
            }
            guard Data(rawHash.finalize()) == content.hash else { throw ConversionError.integrity("The CIA content hash does not match.") }
            for check in checks { try check.verify() }
            if isCIA { outputHashes[content.record] = Data(outputHash.finalize()) }
        }
        if isCIA {
            var offset = archive.contentEnd
            while offset < file.size {
                try control.check()
                let count = Int(min(1024 * 1024, file.size - offset))
                try autoreleasepool { try writeVerified(file.read(offset, count), at: offset) }
                offset += UInt64(count)
            }
            try control.check()
            let metadata = try archive.outputMetadata(hashes: outputHashes)
            try out.seek(toOffset: archive.tmdOffset)
            try out.write(contentsOf: metadata)
        }
        try control.check()
        try out.synchronize()
        try out.close()
        let verification = try BinaryFile(partial)
        guard verification.size == end else { throw ConversionError.integrity("The converted file is incomplete.") }
        if isCIA {
            let result = try CIAArchive(file: verification, keys: .init())
            guard result.titleID == archive.titleID, result.contents.allSatisfy({ !$0.encrypted }) else {
                throw ConversionError.integrity("The output CIA is not fully decrypted.")
            }
        } else if try verification.read(0x100, 4) != Data("NCSD".utf8) {
            throw ConversionError.integrity("The output card image is incomplete.")
        }
        try control.check()
        try fm.moveItem(at: partial, to: output)
        progress(.init(fraction: 1, phase: "Ready to export"))
        return ConversionResult(outputURL: output, titleID: archive.titleID, bytes: end)
    }

    public static func checkStorage(at directory: URL, required: UInt64) throws {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        if let free = attributes[.systemFreeSize] as? NSNumber, free.uint64Value < required + 16 * 1024 * 1024 {
            throw ConversionError.lowStorage
        }
    }

    public static func isStorageError(_ error: Error) -> Bool {
        if error as? ConversionError == .lowStorage { return true }
        let error = error as NSError
        return (error.domain == NSPOSIXErrorDomain && error.code == 28) || (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError) || (error.userInfo[NSUnderlyingErrorKey] as? Error).map(isStorageError) == true
    }
}
