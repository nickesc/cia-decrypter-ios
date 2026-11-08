import Foundation

public enum CIATitleKind: String, Sendable {
    case game, update, dlc

    init(titleID: UInt64) throws {
        switch titleID >> 32 {
        case 0x00040000: self = .game
        case 0x0004000e: self = .update
        case 0x0004008c: self = .dlc
        default: throw ConversionError.unsupported("This title type is not supported. Choose a base game, update, or DLC CIA.")
        }
    }

    public var outputExtension: String { self == .game ? "3ds" : "cia" }

    public func outputName(for inputName: String) -> String {
        let stem = (inputName as NSString).deletingPathExtension
        return (stem.isEmpty ? "Converted title" : stem) + (self == .game ? ".3ds" : ".decrypted.cia")
    }
}
