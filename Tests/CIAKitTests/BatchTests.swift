import XCTest
@testable import CIAKit

final class BatchTests: XCTestCase {
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
