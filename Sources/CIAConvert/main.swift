import Foundation
import CIAKit

@main
struct ConvertCommand {
    static func main() {
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            guard args.count >= 2 else {
                print("Usage: cia-convert INPUT.cia OUTPUT.3ds [--aes PATH] [--seeds PATH] [--boot9 PATH]")
                return
            }
            let input = URL(fileURLWithPath: args.removeFirst())
            let output = URL(fileURLWithPath: args.removeFirst())
            var keys = KeyMaterial()
            while !args.isEmpty {
                let flag = args.removeFirst()
                guard !args.isEmpty, let kind = ["--aes": KeyFileKind.aes, "--seeds": .seeds, "--boot9": .boot9][flag] else {
                    throw ConversionError.invalid("Unknown option or missing key-file path.")
                }
                let path = args.removeFirst()
                try keys.load(Data(contentsOf: URL(fileURLWithPath: path)), kind: kind)
            }
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let result = try CIAConverter.convert(input: input, output: output, keys: keys)
            print("Converted title \(String(format: "%016llX", result.titleID)); \(result.bytes) bytes written.")
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
