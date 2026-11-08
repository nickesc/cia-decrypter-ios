import SwiftUI
import CIAKit

private struct ExportRequest: Identifiable {
    enum Kind { case save(ConversionJob), share([ConversionJob]), folder }
    let id = UUID()
    let kind: Kind
}

struct ContentView: View {
    @Bindable var store: ConversionStore
    @State private var importing = false
    @State private var showingKeys = false
    @State private var confirmingClear = false
    @State private var deletingJob: ConversionJob?
    @State private var export: ExportRequest?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !store.hasStartedSession {
                        emptyState
                    } else {
                        if sizeClass == .regular {
                            HStack(alignment: .top, spacing: 24) {
                                overview.frame(width: 250)
                                queue.frame(maxWidth: .infinity)
                            }
                        } else {
                            overview
                            queue
                        }
                    }
                    if let notice = store.notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Conversions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Keys", systemImage: "key") { showingKeys = true }
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.ciaArchive], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): store.add(urls)
                case .failure(let error): store.alert = "Files could not be opened. \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $showingKeys) { KeysView(vault: store.vault) }
            .sheet(item: $export) { request in
                switch request.kind {
                case .save(let job):
                    DocumentPicker(mode: .save([store.outputURL(job)])) { urls in
                        if !urls.isEmpty { store.markExported([job.id], destination: .files) }
                        export = nil
                    } onCancel: { export = nil }
                case .share(let jobs):
                    SharePicker(urls: jobs.map { store.outputURL($0) }) { completed in
                        if completed { store.markExported(Set(jobs.map(\.id)), destination: .share) }
                        export = nil
                    }
                    .presentationDetents([.medium, .large])
                case .folder:
                    DocumentPicker(mode: .folder) { urls in
                        export = nil
                        if let folder = urls.first { store.exportAll(to: folder) }
                    } onCancel: { export = nil }
                }
            }
            .onChange(of: store.batch.finishedJobs.map(\.id)) {
                confirmingClear = false
            }
            .onChange(of: scenePhase) {
                if scenePhase != .active { confirmingClear = false }
            }
            .confirmationDialog("Delete converted file?", isPresented: Binding(get: { deletingJob != nil }, set: { if !$0 { deletingJob = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let job = deletingJob { store.deleteProgress(job.id) }
                    deletingJob = nil
                }
                Button("Keep file", role: .cancel) { deletingJob = nil }
            } message: {
                Text("This removes the converted file from the app. You can redo it from the original CIA.")
            }
            .alert("Needs attention", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
                Button("OK") { store.alert = nil }
            } message: { Text(store.alert ?? "") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            HStack(spacing: 18) {
                formatCard("CIA", symbol: "lock.fill", accent: false)
                Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.tertiary)
                formatCard("3DS", symbol: "lock.open.fill", accent: true)
            }
            .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Ready to decrypt.")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Convert games to 3DS. Decrypt updates and DLC to CIA.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Label("Choose one or more files", systemImage: "square.stack")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 48)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
    }

    private func formatCard(_ name: String, symbol: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            Image(systemName: symbol).font(.title3)
            Text(name).font(.title3.weight(.bold)).fontDesign(.monospaced)
        }
        .foregroundStyle(accent ? Color.white : Color.primary)
        .padding(18)
        .frame(width: 100, alignment: .leading)
        .background(accent ? Color.conversionAccent : Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(store.isRunning ? "Converting" : store.batch.activeJobs.isEmpty ? "Conversion finished" : store.isPaused ? "Conversion paused" : store.batch.hasQueuedWork ? "Ready to resume" : "Conversion finished")
                    .font(.headline)
                Spacer(minLength: 0)
                if store.isRunning { ProgressView().controlSize(.small).accessibilityLabel("Converting") }
            }
            ProgressView(value: store.batch.fraction)
                .accessibilityLabel("Conversion progress")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(store.batch.unexportedResults.count)").font(.largeTitle.weight(.bold)).monospacedDigit()
                Text("of \(store.batch.activeJobs.count) ready").foregroundStyle(.secondary)
            }
            if !store.batch.savedResults.isEmpty {
                Label("\(store.batch.savedResults.count) saved", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if store.resultBytes > 0 {
                Label(ByteCountFormatter.string(fromByteCount: Int64(store.resultBytes), countStyle: .file) + " in results", systemImage: "internaldrive")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if store.isRunning {
                Button("Pause All", systemImage: "pause.fill") { store.pauseAll() }
                    .buttonStyle(.glass)
                    .disabled(store.isExporting || !store.batch.jobs.contains { $0.status == .queued || $0.status == .running })
            } else if !store.batch.inProgressJobs.isEmpty {
                Button("Resume All", systemImage: "play.fill") { store.resume() }
                    .buttonStyle(.glass)
                    .disabled(store.isExporting)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 12) {
            jobSection("IN PROGRESS", jobs: store.batch.inProgressJobs)
            if store.batch.inProgressJobs.isEmpty {
                Text("No files waiting")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            }
            if !store.batch.finishedJobs.isEmpty {
                jobSection("FINISHED", jobs: store.batch.finishedJobs, showsClear: true).padding(.top, 12)
            }
        }
    }

    private func jobSection(_ title: String, jobs: [ConversionJob], showsClear: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
                Spacer()
                if showsClear {
                    Button {
                        if confirmingClear {
                            confirmingClear = false
                            store.clearFinished()
                        } else { confirmingClear = true }
                    } label: {
                        Text(confirmingClear ? "Confirm?" : "Clear")
                            .frame(minWidth: 60)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .foregroundStyle(confirmingClear ? Color.red : Color.secondary)
                    .frame(minHeight: 44)
                    .accessibilityHint(confirmingClear ? "Clears finished entries and their working files." : "Tap again to confirm clearing finished entries.")
                    .disabled(store.isExporting)
                }
            }
            LazyVStack(spacing: 12) {
                ForEach(jobs) { job in
                    JobRow(job: job, busy: store.isExporting || store.stoppingJobID == job.id, stopping: store.stoppingJobID == job.id) {
                        export = ExportRequest(kind: .save(job))
                    } share: {
                        export = ExportRequest(kind: .share([job]))
                    } retry: {
                        store.retry(job.id)
                    } pause: {
                        store.pause(job.id)
                    } resume: {
                        store.resume(job.id)
                    } delete: {
                        if job.status == .completed && !job.exported { deletingJob = job }
                        else { store.deleteProgress(job.id) }
                    }
                }
            }
        }
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if store.isExporting {
                    ProgressView("Exporting \(store.exportProgress.formatted(.percent.precision(.fractionLength(0))))", value: store.exportProgress)
                        .padding(16)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    Button("Cancel export", role: .cancel) { store.cancelExport() }
                        .buttonStyle(.glass)
                } else {
                    if store.hasStartedSession {
                        HStack(spacing: 12) {
                            Button { export = ExportRequest(kind: .folder) } label: {
                                Label("Save All", systemImage: "folder")
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            Button { export = ExportRequest(kind: .share(store.batch.unexportedResults)) } label: {
                                Label("Share All", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                        }
                        .buttonStyle(.glass)
                        .tint(.primary)
                        .disabled(!store.canExportAll)
                    }
                    Button { importing = true } label: {
                        Label("Add CIA files", systemImage: "plus")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
    }
}

private struct JobRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let job: ConversionJob
    let busy: Bool
    let stopping: Bool
    let save: () -> Void
    let share: () -> Void
    let retry: () -> Void
    let pause: () -> Void
    let resume: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 40, height: 44)
                    .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayName).font(.subheadline.weight(.semibold)).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .foregroundStyle(isRetired ? .secondary : .primary)
                    HStack(spacing: 7) {
                        Text(job.exportLabel ?? job.status.label).foregroundStyle(statusColor)
                        Text("·").foregroundStyle(.tertiary)
                        Text(ByteCountFormatter.string(fromByteCount: job.inputBytes, countStyle: .file)).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
                if job.status == .queued || job.status == .running {
                    Button("Pause \(job.inputName)", systemImage: "pause.fill", action: pause)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(busy)
                } else if job.status.canResume {
                    Button("Resume \(job.inputName)", systemImage: "play.fill", action: resume)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(busy)
                }
                if !job.isSaved && job.status != .cancelled {
                    Button("Delete progress for \(displayName)", systemImage: "xmark", action: delete)
                        .labelStyle(.iconOnly)
                        .fontWeight(.bold)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(busy)
                }
            }
            if stopping {
                ProgressView(job.status == .cancelled ? "Deleting progress…" : "Pausing…")
                    .font(.footnote)
            } else if job.status.isInProgress {
                ProgressView(value: job.progress)
                    .accessibilityLabel("\(job.inputName) progress")
                HStack {
                    Text(job.message ?? job.status.label)
                    Spacer()
                    Text(job.progress.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if let message = job.message, job.status != .cancelled {
                Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if job.status == .completed && !job.exported {
                resultLayout {
                    Button("Save to Files", systemImage: "folder", action: save)
                    Button("Share", systemImage: "square.and.arrow.up", action: share)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(busy)
            } else if job.isSaved || job.status.canRetry {
                Button("Redo", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.glass)
                    .accessibilityLabel("Redo \(displayName)")
                    .disabled(busy)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(isRetired ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 20))
    }

    private var resultLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }

    private var symbol: String {
        if job.isSaved { return "checkmark.circle.fill" }
        return switch job.status {
        case .queued: "clock"
        case .running: "arrow.trianglehead.2.clockwise.rotate.90"
        case .completed: "checkmark.circle.fill"
        case .failed, .storagePaused: "exclamationmark.triangle.fill"
        case .paused, .interrupted: "pause.circle"
        case .cancelled: "xmark.circle"
        }
    }

    private var statusColor: Color {
        if isRetired { return .secondary }
        return switch job.status {
        case .completed: .green
        case .running: .conversionAccent
        case .failed, .storagePaused: .orange
        default: .secondary
        }
    }

    private var displayName: String { job.status == .completed ? job.outputName : job.inputName }

    private var isRetired: Bool { job.isSaved || job.status == .cancelled }
}
