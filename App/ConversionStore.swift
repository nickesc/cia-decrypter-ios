import Foundation
import Observation
import BackgroundTasks
import CIAKit

@MainActor
@Observable
final class ConversionStore {
    private(set) var batch = ConversionBatch()
    private(set) var isRunning = false
    private(set) var isExporting = false
    private(set) var exportProgress = 0.0
    private(set) var hasStartedSession = false
    private(set) var workingJobID: UUID?
    var notice: String?
    var alert: String?
    let vault: KeyVault
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let snapshot: URL
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var control: ConversionControl?
    @ObservationIgnored private var exportControl: ConversionControl?
    @ObservationIgnored private var background: BGContinuedProcessingTask?
    @ObservationIgnored private var backgroundID: String?

    init() {
        directory = URL.applicationSupportDirectory.appendingPathComponent("ConversionWorkspace", isDirectory: true)
        snapshot = directory.appendingPathComponent("batch.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var url = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch { alert = "The working folder could not be opened. \(error.localizedDescription)" }
        vault = KeyVault(directory: directory)
        if FileManager.default.fileExists(atPath: snapshot.path) {
            do {
                batch = try ConversionBatch.load(from: snapshot)
                batch.recover(partialSize: { job in
                    let partial = directory.appendingPathComponent(job.id.uuidString).appendingPathComponent(job.outputName).appendingPathExtension("partial")
                    return (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.uint64Value ?? 0
                }) { job in
                    FileManager.default.fileExists(atPath: directory.appendingPathComponent(job.id.uuidString).appendingPathComponent(job.outputName).path)
                }
                let previous = batch
                batch.resetIdleSession()
                if persist() {
                    for job in previous.jobs where job.isSaved || job.status == .cancelled || batch.jobs.isEmpty { removeWorkspace(job) }
                } else { batch = previous }
                hasStartedSession = !batch.jobs.isEmpty
            } catch { alert = "The saved conversions could not be read. Existing working files have been kept. \(error.localizedDescription)" }
        }
    }

    var isPaused: Bool { !isRunning && batch.inProgressJobs.contains { $0.status.canResume } }
    var canExportAll: Bool { batch.hasUnexportedResults && !isRunning && !batch.hasQueuedWork && !isExporting }
    var stoppingJobID: UUID? {
        guard let id = workingJobID, batch.jobs.first(where: { $0.id == id })?.status != .running else { return nil }
        return id
    }
    var pendingCount: Int { batch.jobs.filter { $0.status == .queued || $0.status == .running }.count }
    var resultBytes: UInt64 { batch.unexportedResults.reduce(0) { $0 + ($1.outputBytes ?? 0) } }

    func outputURL(_ job: ConversionJob) -> URL {
        directory.appendingPathComponent(job.id.uuidString, isDirectory: true).appendingPathComponent(job.outputName)
    }

    func add(_ urls: [URL]) {
        guard !isExporting else { alert = "Finish the export before adding more files."; return }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                guard url.pathExtension.lowercased() == "cia" else { throw ConversionError.invalid("Choose a .cia file.") }
                let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let job = ConversionJob(inputName: url.lastPathComponent, sourceBookmark: bookmark, inputBytes: Int64(size))
                try FileManager.default.createDirectory(at: outputURL(job).deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                batch.jobs.append(job)
                hasStartedSession = true
            } catch { alert = error.localizedDescription }
        }
        guard persist() else { return }
        start()
    }

    func start() {
        guard !isRunning, !isExporting, batch.hasQueuedWork else { return }
        isRunning = true
        notice = nil
        requestBackground()
        worker = Task { await runQueue() }
    }

    func retry(_ id: UUID) {
        guard !isExporting, workingJobID != id, let job = batch.jobs.first(where: { $0.id == id }), job.isSaved || job.status.canRetry else { return }
        guard removeWorkspace(job) else { return }
        do {
            try FileManager.default.createDirectory(at: outputURL(job).deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        } catch { alert = "The working folder could not be opened. \(error.localizedDescription)"; return }
        let previous = batch
        guard batch.requeue(id) else { return }
        guard persist() else { batch = previous; return }
        start()
    }

    func resume(_ id: UUID? = nil) {
        guard !isExporting else { return }
        let previous = batch
        for job in batch.inProgressJobs where (id == nil || job.id == id) && job.id != workingJobID {
            batch.resume(job.id)
        }
        guard persist() else { batch = previous; return }
        start()
    }

    func pause(_ id: UUID) {
        guard !isExporting else { return }
        guard batch.pause(id) else { return }
        persist()
        if workingJobID == id { control?.pause() }
    }

    func pauseAll() {
        guard !isExporting else { return }
        batch.pauseAll()
        persist()
        control?.pause()
    }

    func deleteProgress(_ id: UUID) {
        guard !isExporting else { return }
        let previous = batch
        guard batch.deleteProgress(id) else { return }
        guard persist() else { batch = previous; return }
        if workingJobID == id { control?.cancel() }
        else if let job = batch.jobs.first(where: { $0.id == id }) { removeWorkspace(job) }
    }

    func clearFinished() {
        guard !isExporting else { return }
        let previous = batch
        let jobs = batch.clearFinished(excluding: Set([workingJobID].compactMap { $0 }))
        guard persist() else { batch = previous; return }
        for job in jobs { removeWorkspace(job) }
        if batch.isIdle { notice = nil }
    }

    func markExported(_ ids: Set<UUID>, destination: ExportDestination) {
        let previous = batch
        batch.markExported(ids, destination: destination)
        // Save the receipt before removing the only local working copy.
        guard persist() else { batch = previous; return }
        for job in batch.savedResults where ids.contains(job.id) { removeWorkspace(job) }
        if batch.isIdle { notice = nil }
    }

    func exportAll(to folder: URL) {
        guard canExportAll else { return }
        let jobs = batch.unexportedResults
        let files = jobs.map { ExportFile(source: outputURL($0), name: $0.outputName) }
        let jobIDsBySource = Dictionary(uniqueKeysWithValues: jobs.map { (outputURL($0), $0.id) })
        let control = ConversionControl()
        exportControl = control
        isExporting = true
        exportProgress = 0
        Task {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            let (savedIDs, outcome) = await Task.detached(priority: .userInitiated) {
                var savedIDs = Set<UUID>()
                let outcome = Result<Void, Error> {
                    let coordinator = NSFileCoordinator()
                    var coordinationError: NSError?
                    var result: Result<Void, Error>?
                    coordinator.coordinate(writingItemAt: folder, options: .forMerging, error: &coordinationError) { coordinated in
                        result = Result {
                            try BatchExporter.export(files, to: coordinated, control: control, onFileExported: { file in
                                guard let id = jobIDsBySource[file.source] else { return }
                                savedIDs.insert(id)
                                Task { @MainActor [weak self] in
                                    guard let self, self.exportControl === control else { return }
                                    self.markExported([id], destination: .files)
                                }
                            }) { progress in
                                Task { @MainActor [weak self] in
                                    guard let self, self.exportControl === control else { return }
                                    self.exportProgress = progress
                                }
                            }
                        }
                    }
                    if let coordinationError { throw coordinationError }
                    guard let result else { throw ConversionError.invalid("The export folder could not be opened. Choose it again in Files.") }
                    try result.get()
                }
                return (savedIDs, outcome)
            }.value
            // Apply receipts again after the worker finishes so late progress tasks cannot lose a saved state.
            markExported(savedIDs, destination: .files)
            if case .failure(let error) = outcome {
                alert = "Export stopped. Unsaved results are still in the app. Exported files are in Saved and remain in the chosen folder. \(error.localizedDescription)"
            }
            isExporting = false
            exportControl = nil
        }
    }

    func cancelExport() { exportControl?.cancel() }

    private func runQueue() async {
        while let index = batch.jobs.firstIndex(where: { $0.status == .queued }) {
            let job = batch.jobs[index]
            let destination = outputURL(job)
            let keys = vault.material
            let control = ConversionControl()
            self.control = control
            workingJobID = job.id
            batch.jobs[index].status = .running
            batch.jobs[index].exported = false
            batch.jobs[index].exportDestination = nil
            batch.jobs[index].message = "Checking contents"
            guard persist() else {
                batch.jobs[index].status = .storagePaused
                batch.jobs[index].message = "The queue could not be saved. Free storage, then resume."
                self.control = nil
                workingJobID = nil
                batch.pauseAll()
                break
            }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    var stale = false
                    let source = try URL(resolvingBookmarkData: job.sourceBookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
                    let access = source.startAccessingSecurityScopedResource()
                    defer { if access { source.stopAccessingSecurityScopedResource() } }
                    let coordinator = NSFileCoordinator()
                    var coordinationError: NSError?
                    var result: Result<ConversionResult, Error>?
                    coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { coordinated in
                        result = Result {
                            try CIAConverter.convert(input: coordinated, output: destination, keys: keys, control: control, resumable: true) { progress in
                                Task { @MainActor [weak self] in
                                    guard let self, self.control === control else { return }
                                    self.update(job.id, progress: progress)
                                }
                            }
                        }
                    }
                    if let coordinationError { throw coordinationError }
                    guard let result else { throw ConversionError.invalid("The source could not be opened. Select the CIA again in Files.") }
                    return try result.get()
                }.value
                if let current = batch.jobs.firstIndex(where: { $0.id == job.id }) {
                    if batch.jobs[current].status == .cancelled { removeWorkspace(batch.jobs[current]) }
                    else {
                        batch.jobs[current].status = .completed
                        batch.jobs[current].progress = 1
                        batch.jobs[current].message = nil
                        batch.jobs[current].outputBytes = result.bytes
                    }
                }
            } catch {
                if let current = batch.jobs.firstIndex(where: { $0.id == job.id }) {
                    let status: JobStatus
                    if batch.jobs[current].status == .cancelled || error as? ConversionError == .cancelled { status = .cancelled }
                    else if error as? ConversionError == .paused { status = .paused }
                    else if CIAConverter.isStorageError(error) { status = .storagePaused; batch.pauseAll() }
                    else if error as? ConversionError == .interrupted { status = .interrupted; batch.pauseAll() }
                    else { status = .failed }
                    batch.jobs[current].status = status
                    if !status.canResume { batch.jobs[current].progress = 0 }
                    batch.jobs[current].message = status == .cancelled ? nil : error.localizedDescription
                    if status == .cancelled { removeWorkspace(batch.jobs[current]) }
                }
            }
            self.control = nil
            workingJobID = nil
            guard persist() else { batch.pauseAll(); break }
            updateBackground()
        }
        isRunning = false
        worker = nil
        let success = !batch.inProgressJobs.contains { $0.status.canResume }
        background?.setTaskCompleted(success: success)
        background = nil
        if let id = backgroundID { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id) }
        backgroundID = nil
        if success { notice = nil }
    }

    private func update(_ id: UUID, progress: ConversionProgress) {
        guard let index = batch.jobs.firstIndex(where: { $0.id == id }), batch.jobs[index].status == .running else { return }
        batch.jobs[index].progress = max(batch.jobs[index].progress, progress.fraction)
        batch.jobs[index].message = progress.phase
        updateBackground()
    }

    @discardableResult
    private func persist() -> Bool {
        do { try batch.save(to: snapshot); return true }
        catch { alert = "The queue could not be saved. Completed files have been kept. Free storage and try again. \(error.localizedDescription)"; return false }
    }

    @discardableResult
    private func removeWorkspace(_ job: ConversionJob) -> Bool {
        let folder = outputURL(job).deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.path) else { return true }
        do { try FileManager.default.removeItem(at: folder); return true }
        catch { alert = "Temporary conversion files could not be removed. \(error.localizedDescription)"; return false }
    }

    private func requestBackground() {
        let prefix = (Bundle.main.bundleIdentifier ?? "com.nickesc.ciadecrypter") + ".conversion."
        let id = prefix + UUID().uuidString
        backgroundID = id
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in
                guard let self, self.isRunning, self.backgroundID == id else { task.setTaskCompleted(success: true); return }
                self.background = task
                task.progress.totalUnitCount = 1_000_000
                task.expirationHandler = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.backgroundID == id else { return }
                        self.batch.pauseAll()
                        self.persist()
                        self.control?.interrupt()
                        self.notice = "iOS stopped background processing. Completed files are safe; resume to continue."
                    }
                }
                self.updateBackground()
            }
        }
        guard registered else { notice = "Background processing is unavailable. Keep the app open while converting."; return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Converting CIA files", subtitle: "\(pendingCount) remaining")
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) }
        catch { notice = "Background processing is unavailable right now. Keep the app open while converting." }
    }

    private func updateBackground() {
        background?.progress.completedUnitCount = Int64(batch.fraction * 1_000_000)
        background?.updateTitle("Converting CIA files", subtitle: "\(batch.unexportedResults.count) ready · \(pendingCount) remaining")
    }
}
