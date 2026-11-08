import Foundation

public enum JobStatus: String, Codable, Sendable {
    case queued, running, completed, failed, cancelled, interrupted, storagePaused

    public var label: String {
        switch self {
        case .queued: "Queued"
        case .running: "Converting"
        case .completed: "Ready"
        case .failed: "Needs attention"
        case .cancelled: "Canceled"
        case .interrupted: "Interrupted"
        case .storagePaused: "Storage full"
        }
    }

    public var canRetry: Bool { self == .failed || self == .interrupted || self == .storagePaused || self == .cancelled }
}

public enum ExportDestination: String, Codable, Sendable {
    case files, share
}

public struct ConversionJob: Identifiable, Codable, Sendable {
    public let id: UUID
    public let inputName: String
    public let sourceBookmark: Data
    public let inputBytes: Int64
    public let outputName: String
    public var status: JobStatus = .queued
    public var progress: Double = 0
    public var message: String?
    public var exported = false
    public var exportDestination: ExportDestination?
    public var outputBytes: UInt64?

    public var exportLabel: String? {
        guard status == .completed, exported else { return nil }
        switch exportDestination {
        case .files: return "Saved to Files"
        case .share: return "Shared"
        case nil: return "Exported"
        }
    }

    public init(id: UUID = UUID(), inputName: String, sourceBookmark: Data, inputBytes: Int64) {
        self.id = id
        self.inputName = inputName
        self.sourceBookmark = sourceBookmark
        self.inputBytes = inputBytes
        let stem = (inputName as NSString).deletingPathExtension
        self.outputName = (stem.isEmpty ? "Converted game" : stem) + ".3ds"
    }
}

public struct ConversionBatch: Codable, Sendable {
    public var jobs: [ConversionJob] = []
    public init() {}
    public var completed: [ConversionJob] { jobs.filter { $0.status == .completed } }
    public var unexportedResults: [ConversionJob] { completed.filter { !$0.exported } }
    public var hasUnexportedResults: Bool { !unexportedResults.isEmpty }
    public var hasQueuedWork: Bool { jobs.contains { $0.status == .queued } }
    public var isFullyExported: Bool {
        !completed.isEmpty && jobs.allSatisfy { $0.status == .cancelled || ($0.status == .completed && $0.exported) }
    }

    public mutating func markExported(_ ids: Set<UUID>, destination: ExportDestination) {
        for index in jobs.indices where ids.contains(jobs[index].id) && jobs[index].status == .completed {
            jobs[index].exported = true
            if jobs[index].exportDestination != .files { jobs[index].exportDestination = destination }
        }
    }

    public mutating func clearIfFullyExported() -> [ConversionJob] {
        guard isFullyExported else { return [] }
        let finished = jobs
        jobs.removeAll()
        return finished
    }
    public var fraction: Double {
        guard !jobs.isEmpty else { return 0 }
        let total = jobs.reduce(0.0) { $0 + Double(max($1.inputBytes, 1)) }
        return jobs.reduce(0.0) { value, job in
            let fraction = job.status == .queued ? 0 : job.status == .running ? job.progress : 1
            return value + Double(max(job.inputBytes, 1)) * fraction
        } / total
    }

    public mutating func recover(outputExists: (ConversionJob) -> Bool) {
        for index in jobs.indices {
            if jobs[index].status == .running {
                // A final .3ds is published only after all conversion checks succeed.
                let finished = outputExists(jobs[index])
                jobs[index].status = finished ? .completed : .interrupted
                jobs[index].progress = finished ? 1 : 0
                jobs[index].message = finished ? nil : ConversionError.interrupted.localizedDescription
            } else if jobs[index].status == .completed && !jobs[index].exported && !outputExists(jobs[index]) {
                jobs[index].status = .failed
                jobs[index].progress = 0
                jobs[index].message = "The saved output is missing. Retry to convert this file again."
            }
        }
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

public struct ExportFile: Sendable {
    public let source: URL
    public let name: String
    public init(source: URL, name: String) { self.source = source; self.name = name }
}

public enum BatchExporter {
    public static func export(_ files: [ExportFile], to folder: URL, control: ConversionControl = .init(), onFileExported: (ExportFile) -> Void = { _ in }, progress: @Sendable (Double) -> Void = { _ in }) throws {
        guard !files.isEmpty else { throw ConversionError.invalid("There are no completed files to export.") }
        let fm = FileManager.default
        for (index, file) in files.enumerated() {
            try control.check()
            guard (file.name as NSString).lastPathComponent == file.name, !file.name.isEmpty else { throw ConversionError.invalid("Invalid export filename.") }
            let input = try BinaryFile(file.source)
            try CIAConverter.checkStorage(at: folder, required: input.size)
            var name = file.name
            var suffix = 2
            while fm.fileExists(atPath: folder.appendingPathComponent(name).path) {
                name = "\((file.name as NSString).deletingPathExtension) (\(suffix)).\((file.name as NSString).pathExtension)"
                suffix += 1
            }
            let destination = folder.appendingPathComponent(name)
            let partial = folder.appendingPathComponent(".\(name).\(UUID().uuidString).partial")
            var done = false
            defer { if !done { try? fm.removeItem(at: partial) } }
            try Data().write(to: partial, options: .withoutOverwriting)
            let output = try FileHandle(forWritingTo: partial)
            defer { try? output.close() }
            var offset: UInt64 = 0
            var lastProgress = Date.distantPast
            while offset < input.size {
                try autoreleasepool {
                    try control.check()
                    let count = Int(min(1024 * 1024, input.size - offset))
                    try output.write(contentsOf: input.read(offset, count))
                    offset += UInt64(count)
                    if Date().timeIntervalSince(lastProgress) >= 0.1 {
                        progress((Double(index) + Double(offset) / Double(max(input.size, 1))) / Double(files.count))
                        lastProgress = Date()
                    }
                }
            }
            try output.synchronize()
            try output.close()
            try control.check()
            try fm.moveItem(at: partial, to: destination)
            done = true
            onFileExported(file)
        }
        progress(1)
    }
}
