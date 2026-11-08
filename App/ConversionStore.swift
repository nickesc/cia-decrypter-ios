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
    private(set) var isPaused = false
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
    @ObservationIgnored private var cancelRequested = false

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
                batch.recover { job in
                    FileManager.default.fileExists(atPath: directory.appendingPathComponent(job.id.uuidString).appendingPathComponent(job.outputName).path)
                }
                for job in batch.jobs { try? FileManager.default.removeItem(at: outputURL(job).appendingPathExtension("partial")) }
                if !batch.jobs.isEmpty { notice = "Your batch is saved. Resume queued files or retry interrupted conversions." }
                persist()
            } catch { alert = "The saved batch could not be read. Existing working files have been kept. \(error.localizedDescription)" }
        }
    }

    var completed: [ConversionJob] { batch.completed }
    var canExportAll: Bool { !completed.isEmpty && !isRunning && (!batch.hasQueuedWork || isPaused) && !isExporting }
    var needsCancelConfirmation: Bool { batch.hasUnexportedResults }
    var pendingCount: Int { batch.jobs.filter { $0.status == .queued || $0.status == .running }.count }
    var resultBytes: UInt64 { completed.reduce(0) { $0 + ($1.outputBytes ?? 0) } }

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
            } catch { alert = error.localizedDescription }
        }
        guard persist() else { return }
        if !isPaused { start() }
    }

    func start() {
        guard !isRunning, !isExporting, batch.hasQueuedWork else { return }
        isPaused = false
        cancelRequested = false
        isRunning = true
        notice = nil
        requestBackground()
        worker = Task { await runQueue() }
    }

    func retry(_ id: UUID) {
        guard !isExporting, let index = batch.jobs.firstIndex(where: { $0.id == id }), batch.jobs[index].status.canRetry else { return }
        batch.jobs[index].status = .queued
        batch.jobs[index].progress = 0
        batch.jobs[index].message = nil
        guard persist() else { return }
        isPaused = false
        start()
    }

    func resume() {
        for index in batch.jobs.indices where batch.jobs[index].status == .storagePaused || batch.jobs[index].status == .interrupted {
            batch.jobs[index].status = .queued
            batch.jobs[index].message = nil
        }
        guard persist() else { return }
        start()
    }

    func cancel(_ id: UUID) {
        guard !isExporting, let index = batch.jobs.firstIndex(where: { $0.id == id }) else { return }
        if batch.jobs[index].status == .running { control?.cancel() }
        else if batch.jobs[index].status == .queued {
            batch.jobs[index].status = .cancelled
            batch.jobs[index].message = nil
            persist()
        }
    }

    func cancelBatch() {
        guard !isExporting else { return }
        cancelRequested = true
        isPaused = true
        control?.cancel()
        if !isRunning { clearBatch() }
    }

    func markExported(_ ids: Set<UUID>) {
        for index in batch.jobs.indices where ids.contains(batch.jobs[index].id) { batch.jobs[index].exported = true }
        persist()
    }

    func exportAll(to folder: URL) {
        guard canExportAll else { return }
        let jobs = completed
        let files = jobs.map { ExportFile(source: outputURL($0), name: $0.outputName) }
        let control = ConversionControl()
        exportControl = control
        isExporting = true
        exportProgress = 0
        Task {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            do {
                try await Task.detached(priority: .userInitiated) {
                    let coordinator = NSFileCoordinator()
                    var coordinationError: NSError?
                    var result: Result<Void, Error>?
                    coordinator.coordinate(writingItemAt: folder, options: .forMerging, error: &coordinationError) { coordinated in
                        result = Result {
                            try BatchExporter.export(files, to: coordinated, control: control) { progress in
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
                }.value
                let ids = Set(jobs.map(\.id))
                // Save the cleared state before removing files so a crash never restores deleted results as ready.
                let previous = batch
                batch.jobs.removeAll { ids.contains($0.id) }
                if persist() {
                    for job in jobs { removeWorkspace(job) }
                    notice = "Exported \(jobs.count) \(jobs.count == 1 ? "file" : "files"). Temporary results cleared."
                } else { batch = previous }
            } catch {
                alert = "Export stopped. Your results are still saved in the app; any files already copied remain in the chosen folder. \(error.localizedDescription)"
            }
            isExporting = false
            exportControl = nil
        }
    }

    func cancelExport() { exportControl?.cancel() }

    private func runQueue() async {
        while !isPaused, !cancelRequested, let index = batch.jobs.firstIndex(where: { $0.status == .queued }) {
            let job = batch.jobs[index]
            let destination = outputURL(job)
            let keys = vault.material
            let control = ConversionControl()
            self.control = control
            batch.jobs[index].status = .running
            batch.jobs[index].message = "Checking contents"
            guard persist() else {
                batch.jobs[index].status = .storagePaused
                batch.jobs[index].message = "The queue could not be saved. Free storage, then resume the batch."
                self.control = nil
                isPaused = true
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
                            try CIAConverter.convert(input: coordinated, output: destination, keys: keys, control: control) { progress in
                                Task { @MainActor [weak self] in self?.update(job.id, progress: progress) }
                            }
                        }
                    }
                    if let coordinationError { throw coordinationError }
                    guard let result else { throw ConversionError.invalid("The source could not be opened. Select the CIA again in Files.") }
                    return try result.get()
                }.value
                if let current = batch.jobs.firstIndex(where: { $0.id == job.id }) {
                    batch.jobs[current].status = .completed
                    batch.jobs[current].progress = 1
                    batch.jobs[current].message = nil
                    batch.jobs[current].outputBytes = result.bytes
                }
            } catch {
                if let current = batch.jobs.firstIndex(where: { $0.id == job.id }) {
                    let status: JobStatus
                    if CIAConverter.isStorageError(error) { status = .storagePaused; isPaused = true }
                    else if error as? ConversionError == .cancelled { status = .cancelled }
                    else if error as? ConversionError == .interrupted { status = .interrupted; isPaused = true }
                    else { status = .failed }
                    batch.jobs[current].status = status
                    batch.jobs[current].progress = 0
                    batch.jobs[current].message = error.localizedDescription
                }
            }
            self.control = nil
            guard persist() else { isPaused = true; break }
            updateBackground()
        }
        isRunning = false
        worker = nil
        let success = !isPaused && !cancelRequested
        background?.setTaskCompleted(success: success)
        background = nil
        if let id = backgroundID { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id) }
        backgroundID = nil
        if cancelRequested { clearBatch() }
    }

    private func update(_ id: UUID, progress: ConversionProgress) {
        guard let index = batch.jobs.firstIndex(where: { $0.id == id }), batch.jobs[index].status == .running else { return }
        batch.jobs[index].progress = progress.fraction
        batch.jobs[index].message = progress.phase
        updateBackground()
    }

    @discardableResult
    private func persist() -> Bool {
        do { try batch.save(to: snapshot); return true }
        catch { alert = "The queue could not be saved. Completed files have been kept. Free storage and try again. \(error.localizedDescription)"; return false }
    }

    private func clearBatch() {
        let jobs = batch.jobs
        batch = ConversionBatch()
        if persist() {
            for job in jobs { removeWorkspace(job) }
            notice = nil
            isPaused = false
            cancelRequested = false
        } else { batch.jobs = jobs }
    }

    private func removeWorkspace(_ job: ConversionJob) {
        do { try FileManager.default.removeItem(at: outputURL(job).deletingLastPathComponent()) }
        catch { alert = "The result was saved, but temporary files could not be removed. \(error.localizedDescription)" }
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
                        self.isPaused = true
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
        background?.updateTitle("Converting CIA files", subtitle: "\(completed.count) ready · \(pendingCount) remaining")
    }
}
