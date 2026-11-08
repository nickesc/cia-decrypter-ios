import XCTest
@testable import CIAKit

final class BatchTests: XCTestCase {
    func testIndividualExportsKeepSavedRowsThenClearAfterTheLastExport() {
        var batch = completedBatch(count: 2)
        let ids = batch.jobs.map(\.id)
        batch.markExported([ids[0]], destination: .files)
        XCTAssertTrue(batch.jobs[0].exported)
        XCTAssertEqual(batch.jobs[0].exportDestination, .files)
        XCTAssertFalse(batch.jobs[1].exported)
        XCTAssertEqual(batch.unexportedResults.map(\.id), [ids[1]])
        XCTAssertTrue(batch.clearIfFullyExported().isEmpty)
        XCTAssertEqual(batch.jobs.count, 2)

        batch.markExported([ids[1]], destination: .files)
        XCTAssertEqual(Set(batch.clearIfFullyExported().map(\.id)), Set(ids))
        XCTAssertTrue(batch.jobs.isEmpty)
        XCTAssertFalse(batch.isFullyExported)
    }

    func testPendingOrFailedConversionsPreventAutomaticClearing() {
        for status in [JobStatus.queued, .running, .failed, .interrupted, .storagePaused] {
            var batch = completedBatch(count: 2)
            batch.jobs[1].status = status
            batch.markExported(Set(batch.jobs.map(\.id)), destination: .files)
            XCTAssertTrue(batch.jobs[0].exported)
            XCTAssertFalse(batch.jobs[1].exported)
            XCTAssertFalse(batch.isFullyExported)
            XCTAssertTrue(batch.clearIfFullyExported().isEmpty)
            XCTAssertEqual(batch.jobs.count, 2)
        }
    }

    func testCancelledJobsDoNotKeepAnOtherwiseExportedBatchOpen() {
        var batch = completedBatch(count: 2)
        batch.jobs[1].status = .cancelled
        batch.markExported([batch.jobs[0].id], destination: .files)
        XCTAssertEqual(batch.clearIfFullyExported().count, 2)
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
            XCTAssertFalse(restored.isFullyExported)
        }
    }

    func testNoSuccessfulExportDoesNotClearResults() {
        var batch = completedBatch(count: 1)
        batch.markExported([UUID()], destination: .files)
        XCTAssertFalse(batch.jobs[0].exported)
        XCTAssertNil(batch.jobs[0].exportDestination)
        XCTAssertTrue(batch.clearIfFullyExported().isEmpty)
        XCTAssertEqual(batch.jobs.count, 1)
    }

    func testMixingIndividualAndBatchExportsClearsOnlyAfterRemainingResultsAreSaved() {
        var batch = completedBatch(count: 3)
        batch.markExported([batch.jobs[0].id], destination: .files)
        let remaining = Set(batch.unexportedResults.map(\.id))
        XCTAssertEqual(remaining.count, 2)
        batch.markExported(remaining, destination: .files)
        XCTAssertEqual(batch.clearIfFullyExported().count, 3)
        XCTAssertTrue(batch.jobs.isEmpty)
    }

    func testBatchExportReportsOnlyFilesSuccessfullyWrittenBeforeFailure() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source.3ds")
            try Data([4, 5, 6]).write(to: source)
            var exported: [String] = []
            let files = [ExportFile(source: source, name: "Saved.3ds"), ExportFile(source: root.appendingPathComponent("missing.3ds"), name: "Missing.3ds")]
            XCTAssertThrowsError(try BatchExporter.export(files, to: root, onFileExported: { exported.append($0.name) }))
            XCTAssertEqual(exported, ["Saved.3ds"])
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
            XCTAssertEqual(restored.jobs[1].progress, 0)
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
