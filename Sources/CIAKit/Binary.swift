import Foundation

public enum ConversionError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String)
    case unsupported(String)
    case missingKey(String)
    case integrity(String)
    case lowStorage
    case cancelled
    case interrupted

    public var errorDescription: String? {
        switch self {
        case .invalid(let detail): "Invalid file: \(detail)"
        case .unsupported(let detail): "\(detail) V1 converts base-game application CIAs."
        case .missingKey(let detail): "Missing \(detail). Import the required key file in Keys, then retry."
        case .integrity(let detail): "\(detail) Check the input and imported keys, then retry."
        case .lowStorage: "Not enough free space. Free storage or export and close this batch, then retry."
        case .cancelled: "Conversion canceled."
        case .interrupted: "Conversion interrupted. Retry to start this file again."
        }
    }
}

extension Data {
    func bytes(_ offset: Int, _ count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= self.count, count <= self.count - offset else {
            throw ConversionError.invalid("A section extends beyond the file.")
        }
        return subdata(in: offset..<(offset + count))
    }

    func number(_ offset: Int, _ width: Int, bigEndian: Bool = false) throws -> UInt64 {
        let part = try bytes(offset, width)
        return (bigEndian ? Array(part) : Array(part.reversed())).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func put(_ value: UInt64, at offset: Int, width: Int, bigEndian: Bool = false) {
        for i in 0..<width {
            self[offset + i] = UInt8(truncatingIfNeeded: value >> ((bigEndian ? width - i - 1 : i) * 8))
        }
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        guard hex.count.isMultiple(of: 2), hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        var result = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { return nil }
            result.append(byte)
            index = end
        }
        self = result
    }
}

func aligned(_ value: UInt64, to unit: UInt64 = 0x40) -> UInt64 { (value + unit - 1) / unit * unit }

final class BinaryFile {
    let handle: FileHandle
    let size: UInt64

    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        size = try handle.seekToEnd()
    }

    deinit { try? handle.close() }

    func read(_ offset: UInt64, _ count: Int) throws -> Data {
        guard count >= 0, offset <= size, UInt64(count) <= size - offset else {
            throw ConversionError.invalid("The input is truncated.")
        }
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw ConversionError.invalid("The input could not be read completely.")
        }
        return data
    }
}
