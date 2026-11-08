import XCTest
@testable import CIAKit

final class BatchTests: XCTestCase {
    func testMixedOutputFormatsSurviveRecoveryAndExportWithoutOverwriting() throws {
        try withDirectory { root in
            var batch = completedBatch(count: 2)
            batch.jobs[0].outputName = CIATitleKind.game.outputName(for: "Game.cia")
            batch.jobs[1].outputName = CIATitleKind.update.outputName(for: "Game update.cia")
            batch.jobs[1].status = .running
            let snapshot = root.appendingPathComponent("queue.json")
            try batch.save(to: snapshot)
            var restored = try ConversionBatch.load(from: snapshot)
            XCTAssertEqual(restored.jobs.map(\.outputName), ["Game.3ds", "Game update.decrypted.cia"])
            restored.recover { _ in true }
            XCTAssertEqual(restored.unexportedResults.count, 2)
            let folder = root.appendingPathComponent("export")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let files = try restored.unexportedResults.map { job in
                let url = root.appendingPathComponent(job.outputName)
                try Data(job.outputName.utf8).write(to: url)
                return ExportFile(source: url, name: job.outputName)
            }
            try BatchExporter.export(files, to: folder)
            for file in files {
                XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(file.name)), try Data(contentsOf: file.source))
            }
        }
    }

    func testStopPreservesProgressAndResumeKeepsItAcrossPersistence() throws {
        try withDirectory { root in
            var batch = completedBatch(count: 4)
            batch.jobs[0].status = .running
            batch.jobs[0].progress = 0.4
            batch.jobs[1].status = .queued
            batch.jobs[1].progress = 0
            batch.jobs[3].status = .failed
            batch.pauseAll()
            XCTAssertEqual(batch.jobs.map(\.status), [.paused, .paused, .completed, .failed])
            XCTAssertEqual(batch.inProgressJobs.count, 2)
            XCTAssertEqual(batch.finishedJobs.count, 2)
            let snapshot = root.appendingPathComponent("stopped.json")
            try batch.save(to: snapshot)
            var restored = try ConversionBatch.load(from: snapshot)
            restored.recover { $0.status == .completed }
            XCTAssertEqual(restored.jobs[0].progress, 0.4)
            XCTAssertTrue(restored.resume(restored.jobs[0].id))
            XCTAssertEqual(restored.jobs[0].status, .queued)
            XCTAssertEqual(restored.jobs[0].progress, 0.4)
            XCTAssertEqual(restored.jobs[1].status, .paused)
            XCTAssertFalse(restored.resume(restored.jobs[2].id))
        }
    }

    func testClearRemovesFinishedEntriesWithoutChangingRunningQueuedOrPausedJobs() {
        var batch = completedBatch(count: 7)
        batch.jobs[0].status = .running
        batch.jobs[0].progress = 0.3
        batch.jobs[1].status = .queued
        batch.jobs[2].status = .paused
        batch.jobs[4].status = .failed
        batch.jobs[5].status = .cancelled
        batch.markExported([batch.jobs[6].id], destination: .files)
        XCTAssertEqual(batch.clearFinished().count, 4)
        XCTAssertEqual(batch.jobs.map(\.status), [.running, .queued, .paused])
        XCTAssertEqual(batch.jobs[0].progress, 0.3)
    }

    func testDeleteMovesProgressToFinishedAndRedoStartsFresh() {
        var batch = completedBatch(count: 1)
        let id = batch.jobs[0].id
        batch.jobs[0].status = .paused
        batch.jobs[0].progress = 0.6
        XCTAssertTrue(batch.deleteProgress(id))
        XCTAssertTrue(batch.inProgressJobs.isEmpty)
        XCTAssertEqual(batch.finishedJobs.map(\.id), [id])
        XCTAssertEqual(batch.jobs[0].status, .cancelled)
        XCTAssertEqual(batch.jobs[0].progress, 0)
        XCTAssertTrue(batch.clearFinished(excluding: [id]).isEmpty)
        XCTAssertTrue(batch.requeue(id))
        XCTAssertEqual(batch.inProgressJobs.map(\.id), [id])
        XCTAssertTrue(batch.finishedJobs.isEmpty)
        XCTAssertFalse(batch.resume(id))
    }

    func testIndividualExportsMoveToHistoryWithoutClearingTheSession() {
        var batch = completedBatch(count: 2)
        let ids = batch.jobs.map(\.id)
        batch.markExported([ids[0]], destination: .files)
        XCTAssertTrue(batch.jobs[0].exported)
        XCTAssertEqual(batch.jobs[0].exportDestination, .files)
        XCTAssertFalse(batch.jobs[1].exported)
        XCTAssertEqual(batch.unexportedResults.map(\.id), [ids[1]])
        XCTAssertEqual(batch.activeJobs.map(\.id), [ids[1]])
        XCTAssertEqual(batch.savedResults.map(\.id), [ids[0]])
        XCTAssertEqual(batch.jobs.count, 2)

        batch.markExported([ids[1]], destination: .files)
        XCTAssertTrue(batch.activeJobs.isEmpty)
        XCTAssertEqual(Set(batch.savedResults.map(\.id)), Set(ids))
        XCTAssertEqual(batch.jobs.count, 2)
        XCTAssertTrue(batch.isIdle)
        batch.resetIdleSession()
        XCTAssertTrue(batch.jobs.isEmpty)
    }

    func testUnfinishedOrUnsavedWorkPreservesHistoryOnRelaunch() {
        for status in [JobStatus.queued, .running, .paused, .completed, .interrupted, .storagePaused] {
            var batch = completedBatch(count: 2)
            batch.jobs[1].status = status
            batch.markExported([batch.jobs[0].id], destination: .files)
            XCTAssertTrue(batch.jobs[0].exported)
            XCTAssertFalse(batch.jobs[1].exported)
            XCTAssertFalse(batch.isIdle)
            batch.resetIdleSession()
            XCTAssertEqual(batch.jobs.count, 2)
        }
    }

    func testCancelledJobsDoNotKeepAnOtherwiseExportedBatchOpen() {
        var batch = completedBatch(count: 2)
        batch.jobs[1].status = .cancelled
        batch.markExported([batch.jobs[0].id], destination: .files)
        XCTAssertTrue(batch.isIdle)
        batch.resetIdleSession()
        XCTAssertTrue(batch.jobs.isEmpty)
    }

    func testSharingDoesNotClaimAFileWasSavedAndSavedStateSurvivesRecovery() throws {
        try withDirectory { root in
            var batch = completedBatch(count: 2)
            let id = batch.jobs[0].id
            batch.markExported([id], destination: .share)
            XCTAssertEqual(batch.jobs[0].exportDestination, .share)
            batch.markExported([id], destination: .files)
            batch.markExported([id], destination: .share)
            XCTAssertEqual(batch.jobs[0].exportDestination, .files)
            let snapshot = root.appendingPathComponent("batch.json")
            try batch.save(to: snapshot)
            var restored = try ConversionBatch.load(from: snapshot)
            restored.recover { $0.id != id }
            XCTAssertEqual(restored.jobs[0].status, .completed)
            XCTAssertTrue(restored.jobs[0].exported)
            XCTAssertEqual(restored.jobs[0].exportDestination, .files)
            XCTAssertFalse(restored.jobs[1].exported)
            XCTAssertFalse(restored.isIdle)
        }
    }

    func testNoSuccessfulExportDoesNotClearResults() {
        var batch = completedBatch(count: 1)
        batch.markExported([UUID()], destination: .files)
        XCTAssertFalse(batch.jobs[0].exported)
        XCTAssertNil(batch.jobs[0].exportDestination)
        XCTAssertTrue(batch.savedResults.isEmpty)
        XCTAssertEqual(batch.activeJobs.count, 1)
        XCTAssertEqual(batch.jobs.count, 1)
        for status in [JobStatus.queued, .running, .paused, .failed, .interrupted, .storagePaused, .cancelled] {
            batch.jobs[0].status = status
            batch.markExported([batch.jobs[0].id], destination: .files)
            XCTAssertFalse(batch.jobs[0].exported)
            XCTAssertTrue(batch.savedResults.isEmpty)
        }
    }

    func testMixingIndividualAndBulkExportsKeepsAllSavedHistory() {
        var batch = completedBatch(count: 3)
        batch.markExported([batch.jobs[0].id], destination: .files)
        let remaining = Set(batch.unexportedResults.map(\.id))
        XCTAssertEqual(remaining.count, 2)
        batch.markExported(remaining, destination: .files)
        XCTAssertTrue(batch.activeJobs.isEmpty)
        XCTAssertEqual(batch.savedResults.count, 3)
        XCTAssertTrue(batch.isIdle)
    }

    func testRedoMovesSavedHistoryBackToTheQueueAndResetsOutputState() throws {
        try withDirectory { root in
            var batch = completedBatch(count: 2)
            let job = batch.jobs[0]
            batch.jobs[0].outputBytes = 200
            batch.markExported([job.id], destination: .share)
            XCTAssertTrue(batch.requeue(job.id))
            XCTAssertEqual(batch.jobs[0].id, job.id)
            XCTAssertEqual(batch.jobs[0].sourceBookmark, job.sourceBookmark)
            XCTAssertEqual(batch.jobs[0].inputName, job.inputName)
            XCTAssertEqual(batch.jobs[0].status, .queued)
            XCTAssertEqual(batch.jobs[0].progress, 0)
            XCTAssertFalse(batch.jobs[0].exported)
            XCTAssertNil(batch.jobs[0].exportDestination)
            XCTAssertNil(batch.jobs[0].outputBytes)
            XCTAssertTrue(batch.savedResults.isEmpty)
            XCTAssertFalse(batch.requeue(job.id))
            XCTAssertFalse(batch.requeue(batch.jobs[1].id))
            let snapshot = root.appendingPathComponent("queue.json")
            try batch.save(to: snapshot)
            let restored = try ConversionBatch.load(from: snapshot)
            XCTAssertEqual(restored.jobs[0].status, .queued)
            XCTAssertEqual(restored.activeJobs.count, 2)
        }
    }

    func testHistoryDoesNotCountTowardNewConversionProgress() {
        var batch = completedBatch(count: 2)
        batch.markExported(Set(batch.jobs.map(\.id)), destination: .files)
        XCTAssertEqual(batch.fraction, 1)
        XCTAssertTrue(batch.requeue(batch.jobs[0].id))
        XCTAssertEqual(batch.fraction, 0)
        batch.jobs[0].status = .running
        batch.jobs[0].progress = 0.25
        XCTAssertEqual(batch.fraction, 0.25)
    }

    func testBatchExportReportsOnlyFilesSuccessfullyWrittenBeforeFailure() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source.3ds")
            try Data([4, 5, 6]).write(to: source)
            var exported: [String] = []
            let files = [ExportFile(source: source, name: "Saved.3ds"), ExportFile(source: root.appendingPathComponent("missing.3ds"), name: "Missing.3ds")]
            XCTAssertThrowsError(try BatchExporter.export(files, to: root, onFileExported: { file in
                exported.append(file.name)
                do { try FileManager.default.removeItem(at: file.source) }
                catch { XCTFail("Could not remove the exported working copy: \(error)") }
            }))
            XCTAssertEqual(exported, ["Saved.3ds"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Saved.3ds")), Data([4, 5, 6]))
            let control = ConversionControl()
            control.cancel()
            exported.removeAll()
            XCTAssertThrowsError(try BatchExporter.export([files[0]], to: root, control: control, onFileExported: { exported.append($0.name) }))
            XCTAssertTrue(exported.isEmpty)
        }
    }

    private func completedBatch(count: Int) -> ConversionBatch {
        var batch = ConversionBatch()
        batch.jobs = (0..<count).map { index in
            var job = ConversionJob(inputName: "Game \(index).cia", sourceBookmark: Data(), inputBytes: 100)
            job.status = .completed
            job.progress = 1
            return job
        }
        return batch
    }

    func testRecoveryPreservesCompletedResultsAndQueuedWork() throws {
        try withDirectory { root in
            var batch = ConversionBatch()
            var complete = ConversionJob(inputName: "Ready.cia", sourceBookmark: Data(), inputBytes: 20)
            complete.status = .completed
            complete.progress = 1
            var running = ConversionJob(inputName: "Running.cia", sourceBookmark: Data(), inputBytes: 40)
            running.status = .running
            running.progress = 0.5
            let queued = ConversionJob(inputName: "Next.cia", sourceBookmark: Data(), inputBytes: 10)
            batch.jobs = [complete, running, queued]
            let snapshot = root.appendingPathComponent("batch.json")
            try batch.save(to: snapshot)
            var restored = try ConversionBatch.load(from: snapshot)
            restored.recover { $0.id == complete.id }
            XCTAssertEqual(restored.jobs.map(\.status), [.completed, .interrupted, .queued])
            XCTAssertEqual(restored.jobs[1].progress, 0.5)
            XCTAssertTrue(restored.hasUnexportedResults)
            XCTAssertTrue(restored.hasQueuedWork)
            restored.recover { _ in false }
            XCTAssertEqual(restored.jobs[0].status, .failed)
        }
    }

    func testRecoveryAtTheOutputCommitBoundaryKeepsTheFinishedResult() {
        var batch = ConversionBatch()
        var job = ConversionJob(inputName: "Finished.cia", sourceBookmark: Data(), inputBytes: 100)
        job.status = .running
        batch.jobs = [job]
        batch.recover { _ in true }
        XCTAssertEqual(batch.jobs[0].status, .completed)
        XCTAssertEqual(batch.jobs[0].progress, 1)
        XCTAssertTrue(batch.hasUnexportedResults)
        var interrupted = ConversionJob(inputName: "Partial.cia", sourceBookmark: Data(), inputBytes: 100)
        interrupted.status = .running
        batch.jobs.append(interrupted)
        batch.recover(partialSize: { $0.id == interrupted.id ? 0x4000 + 40 : 0 }) { $0.id == job.id }
        XCTAssertEqual(batch.jobs[1].status, .interrupted)
        XCTAssertEqual(batch.jobs[1].progress, 0.4)
        XCTAssertEqual(batch.unexportedResults.map(\.id), [job.id])
        for status in [JobStatus.queued, .running, .paused, .interrupted, .storagePaused] {
            batch.jobs[1].status = status
            batch.recover { _ in true }
            XCTAssertEqual(batch.jobs[1].status, .completed)
            XCTAssertEqual(batch.jobs[1].progress, 1)
        }
        batch.jobs[1].status = .cancelled
        batch.recover { _ in true }
        XCTAssertEqual(batch.jobs[1].status, .cancelled)
    }

    func testExportPreservesOriginalsAndNeverOverwrites() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source.3ds")
            let folder = root.appendingPathComponent("Exports")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let original = Data(repeating: 7, count: 1024)
            try original.write(to: source)
            try Data([1, 2, 3]).write(to: folder.appendingPathComponent("Game.3ds"))
            try BatchExporter.export([ExportFile(source: source, name: "Game.3ds")], to: folder)
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Game.3ds")), Data([1, 2, 3]))
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Game (2).3ds")), original)
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }

    func testFailedAndCanceledExportsKeepSourceOutputs() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source.3ds")
            try Data(repeating: 8, count: 64).write(to: source)
            let files = [ExportFile(source: source, name: "Game.3ds"), ExportFile(source: root.appendingPathComponent("missing.3ds"), name: "Missing.3ds")]
            XCTAssertThrowsError(try BatchExporter.export(files, to: root))
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            let control = ConversionControl()
            control.cancel()
            XCTAssertThrowsError(try BatchExporter.export([files[0]], to: root, control: control))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".partial") }, [])
        }
    }
}
