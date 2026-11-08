import Foundation
import CryptoKit
import CCrypto

enum Crypto {
    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    static func cbc(_ input: Data, key: Data, iv: Data, encrypt: Bool = false) throws -> Data {
        guard key.count == 16, iv.count == 16, input.count.isMultiple(of: 16) else {
            throw ConversionError.invalid("Invalid AES block or key size.")
        }
        if input.isEmpty { return input }
        var output = Data(count: input.count)
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { source in
                key.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        cia_aes_cbc(key.bindMemory(to: UInt8.self).baseAddress!, iv.bindMemory(to: UInt8.self).baseAddress!, source.bindMemory(to: UInt8.self).baseAddress!, input.count, out.bindMemory(to: UInt8.self).baseAddress!, encrypt ? 1 : 0)
                    }
                }
            }
        }
        guard status == 0 else { throw ConversionError.integrity("AES decryption failed.") }
        return output
    }

    static func ctr(_ input: Data, key: Data, counter: Data, offset: UInt64 = 0) throws -> Data {
        guard key.count == 16, counter.count == 16 else { throw ConversionError.invalid("Invalid AES key size.") }
        if input.isEmpty { return input }
        var counter = Array(counter)
        var blocks = offset / 16
        for i in stride(from: 15, through: 0, by: -1) {
            let sum = UInt64(counter[i]) + (blocks & 0xff)
            counter[i] = UInt8(truncatingIfNeeded: sum)
            blocks = (blocks >> 8) + (sum >> 8)
        }
        let skip = Int(offset % 16)
        let padded = Data(repeating: 0, count: skip) + input
        var output = Data(count: padded.count)
        let status = output.withUnsafeMutableBytes { out in
            padded.withUnsafeBytes { source in
                key.withUnsafeBytes { key in
                    counter.withUnsafeBufferPointer { counter in
                        cia_aes_ctr(key.bindMemory(to: UInt8.self).baseAddress!, counter.baseAddress!, source.bindMemory(to: UInt8.self).baseAddress!, padded.count, out.bindMemory(to: UInt8.self).baseAddress!)
                    }
                }
            }
        }
        guard status == 0 else { throw ConversionError.integrity("AES decryption failed.") }
        return Data(output.dropFirst(skip))
    }

    static func scramble(x: Data, y: Data, constant: Data? = nil) throws -> Data {
        guard x.count == 16, y.count == 16 else { throw ConversionError.invalid("Invalid key component.") }
        func rotate(_ bytes: [UInt8], by count: Int) -> [UInt8] {
            (0..<16).map { index in
                let first = (index + count / 8) % 16
                let shift = count % 8
                return shift == 0 ? bytes[first] : (bytes[first] << shift) | (bytes[(first + 1) % 16] >> (8 - shift))
            }
        }
        // The public hardware key-scrambler constant is an algorithm parameter, not a retail key.
        let addend = Array(constant ?? Data(hex: "1ff9e9aac5fe0408024591dc5d52768a")!)
        guard addend.count == 16 else { throw ConversionError.invalid("Invalid scrambler constant.") }
        var value = zip(rotate(Array(x), by: 2), y).map { $0 ^ $1 }
        var carry: UInt16 = 0
        for index in stride(from: 15, through: 0, by: -1) {
            let sum = UInt16(value[index]) + UInt16(addend[index]) + carry
            value[index] = UInt8(truncatingIfNeeded: sum)
            carry = sum >> 8
        }
        return Data(rotate(value, by: 87))
    }
}
