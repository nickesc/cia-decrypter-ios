import Foundation

public enum JobStatus: String, Codable, Sendable {
    case queued, running, paused, completed, failed, cancelled, interrupted, storagePaused

    public var label: String {
        switch self {
        case .queued: "Queued"
        case .running: "Converting"
        case .paused: "Paused"
        case .completed: "Ready"
        case .failed: "Needs attention"
        case .cancelled: "Deleted"
        case .interrupted: "Interrupted"
        case .storagePaused: "Storage full"
        }
    }

    public var canResume: Bool { self == .paused || self == .interrupted || self == .storagePaused }
    public var canRetry: Bool { self == .failed || self == .cancelled }
    public var isInProgress: Bool { self == .queued || self == .running || canResume }
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

    public var isSaved: Bool { status == .completed && exported }

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
    public var inProgressJobs: [ConversionJob] { jobs.filter { $0.status.isInProgress } }
    public var finishedJobs: [ConversionJob] { jobs.filter { !$0.status.isInProgress } }
    public var activeJobs: [ConversionJob] { jobs.filter { $0.status.isInProgress || ($0.status == .completed && !$0.exported) } }
    public var savedResults: [ConversionJob] { jobs.filter(\.isSaved) }
    public var unexportedResults: [ConversionJob] { completed.filter { !$0.exported } }
    public var hasUnexportedResults: Bool { !unexportedResults.isEmpty }
    public var hasQueuedWork: Bool { jobs.contains { $0.status == .queued } }
    public var isIdle: Bool { inProgressJobs.isEmpty && !hasUnexportedResults }

    @discardableResult
    public mutating func pause(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status == .queued || jobs[index].status == .running else { return false }
        jobs[index].status = .paused
        jobs[index].message = nil
        return true
    }

    public mutating func pauseAll() {
        for id in inProgressJobs.map(\.id) { pause(id) }
    }

    @discardableResult
    public mutating func resume(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status.canResume else { return false }
        jobs[index].status = .queued
        jobs[index].message = nil
        return true
    }

    @discardableResult
    public mutating func deleteProgress(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].isSaved, jobs[index].status != .cancelled else { return false }
        jobs[index].status = .cancelled
        jobs[index].progress = 0
        jobs[index].message = nil
        jobs[index].outputBytes = nil
        jobs[index].exported = false
        jobs[index].exportDestination = nil
        return true
    }

    public mutating func clearFinished(excluding ids: Set<UUID> = []) -> [ConversionJob] {
        let removed = finishedJobs.filter { !ids.contains($0.id) }
        let removedIDs = Set(removed.map(\.id))
        jobs.removeAll { removedIDs.contains($0.id) }
        return removed
    }

    public mutating func markExported(_ ids: Set<UUID>, destination: ExportDestination) {
        for index in jobs.indices where ids.contains(jobs[index].id) && jobs[index].status == .completed {
            jobs[index].exported = true
            if jobs[index].exportDestination != .files { jobs[index].exportDestination = destination }
        }
    }

    public mutating func requeue(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].isSaved || jobs[index].status.canRetry else { return false }
        jobs[index].status = .queued
        jobs[index].progress = 0
        jobs[index].message = nil
        jobs[index].exported = false
        jobs[index].exportDestination = nil
        jobs[index].outputBytes = nil
        return true
    }

    public mutating func resetIdleSession() {
        if isIdle { jobs.removeAll() }
    }
    public var fraction: Double {
        let active = activeJobs
        guard !active.isEmpty else { return savedResults.isEmpty ? 0 : 1 }
        let total = active.reduce(0.0) { $0 + Double(max($1.inputBytes, 1)) }
        return active.reduce(0.0) { value, job in
            let fraction = job.status.isInProgress ? job.progress : 1
            return value + Double(max(job.inputBytes, 1)) * fraction
        } / total
    }

    public mutating func recover(partialSize: (ConversionJob) -> UInt64 = { _ in 0 }, outputExists: (ConversionJob) -> Bool) {
        for index in jobs.indices {
            // Publishing a final output wins a pause race, but never overrides deletion.
            if jobs[index].status.isInProgress && outputExists(jobs[index]) {
                jobs[index].status = .completed
                jobs[index].progress = 1
                jobs[index].message = nil
            } else if jobs[index].status == .running {
                jobs[index].status = .interrupted
                jobs[index].message = ConversionError.interrupted.localizedDescription
            } else if jobs[index].status == .completed && !jobs[index].exported && !outputExists(jobs[index]) {
                jobs[index].status = .failed
                jobs[index].progress = 0
                jobs[index].message = "The saved output is missing. Retry to convert this file again."
            }
            if jobs[index].status.canResume {
                let bytes = partialSize(jobs[index])
                if bytes > 0x4000 {
                    jobs[index].progress = max(jobs[index].progress, min(0.99, Double(bytes - 0x4000) / Double(max(jobs[index].inputBytes, 1))))
                }
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
