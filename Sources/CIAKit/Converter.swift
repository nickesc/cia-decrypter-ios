import Foundation
import CryptoKit

public final class ConversionControl: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: ConversionError?
    public init() {}
    public func cancel() { lock.withLock { reason = .cancelled } }
    public func interrupt() { lock.withLock { reason = .interrupted } }
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
    public static func convert(input: URL, output: URL, keys: KeyMaterial, control: ConversionControl = .init(), progress: @Sendable (ConversionProgress) -> Void = { _ in }) throws -> ConversionResult {
        try control.check()
        guard input.standardizedFileURL != output.standardizedFileURL else { throw ConversionError.invalid("Input and output must be different files.") }
        let file = try BinaryFile(input)
        let archive = try CIAArchive(file: file, keys: keys)
        progress(.init(fraction: 0, phase: "Checking contents"))
        let contents = archive.contents.sorted { $0.index < $1.index }
        var plans: [(CIAContent, ContentSource, NCCHPlan, UInt64)] = []
        var end: UInt64 = 0x4000
        for content in contents {
            try control.check()
            let source = ContentSource(file: file, content: content, titleKey: archive.titleKey)
            let plan = try NCCHPlan(source: source, keys: keys)
            plans.append((content, source, plan, end))
            end += aligned(plan.size, to: 0x200)
        }
        try checkStorage(at: output.deletingLastPathComponent(), required: end)
        let fm = FileManager.default
        let partial = output.appendingPathExtension("partial")
        guard !fm.fileExists(atPath: output.path), !fm.fileExists(atPath: partial.path) else { throw ConversionError.invalid("An output with this name already exists.") }
        try Data().write(to: partial, options: .withoutOverwriting)
        var finished = false
        defer { if !finished { try? fm.removeItem(at: partial) } }
        let out = try FileHandle(forWritingTo: partial)
        defer { try? out.close() }
        let baseID = plans[0].2.partitionID
        var cci = Data(repeating: 0, count: 0x4000)
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
        try out.write(contentsOf: cci)
        let total = contents.reduce(UInt64(0)) { $0 + $1.size }
        var completed: UInt64 = 0
        var lastStorageCheck: UInt64 = 0
        var lastProgress = Date.distantPast
        for (content, source, plan, destination) in plans {
            var rawHash = SHA256()
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
                    if offset == 0 { decrypted.replaceSubrange(0..<0x200, with: plan.outputHeader(index: content.index, baseID: baseID)) }
                    if offset < plan.size {
                        let outputCount = min(count, Int(plan.size - offset))
                        try out.seek(toOffset: destination + offset)
                        try out.write(contentsOf: decrypted.prefix(outputCount))
                    }
                    offset += UInt64(count)
                    completed += UInt64(count)
                    if Date().timeIntervalSince(lastProgress) >= 0.1 {
                        progress(.init(fraction: Double(completed) / Double(total) * 0.99, phase: "Decrypting and verifying"))
                        lastProgress = Date()
                    }
                }
            }
            guard Data(rawHash.finalize()) == content.hash else { throw ConversionError.integrity("The CIA content hash does not match.") }
            for check in checks { try check.verify() }
        }
        try control.check()
        try out.synchronize()
        try out.close()
        let verification = try BinaryFile(partial)
        guard verification.size == end, try verification.read(0x100, 4) == Data("NCSD".utf8) else {
            throw ConversionError.integrity("The output card image is incomplete.")
        }
        try fm.moveItem(at: partial, to: output)
        finished = true
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
