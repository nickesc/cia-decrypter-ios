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
    @State private var confirmingCancel = false
    @State private var export: ExportRequest?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if store.batch.jobs.isEmpty {
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
                if !store.batch.jobs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear", role: .destructive) {
                            if store.needsCancelConfirmation { confirmingCancel = true }
                            else { store.cancelBatch() }
                        }
                        .disabled(store.isExporting)
                    }
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
            .confirmationDialog("Clear conversions?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { store.cancelBatch() }
                Button("Keep conversions", role: .cancel) {}
            } message: {
                Text("This stops conversions and removes completed results that you haven’t exported. Original CIA files stay untouched.")
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
                Text("Convert CIA to 3DS.")
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
        .background(accent ? Color.conversionAccent : Color(uiColor: .tertiarySystemGroupedBackground), in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 5))
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(store.isRunning ? "Converting" : store.isPaused ? "Conversion paused" : store.batch.hasQueuedWork ? "Ready to resume" : "Conversion finished")
                    .font(.headline)
                Spacer(minLength: 0)
                if store.isRunning { ProgressView().controlSize(.small).accessibilityLabel("Converting") }
            }
            ProgressView(value: store.batch.fraction)
                .accessibilityLabel("Conversion progress")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(store.completed.count)").font(.largeTitle.weight(.bold)).monospacedDigit()
                Text("of \(store.batch.jobs.count) ready").foregroundStyle(.secondary)
            }
            if store.resultBytes > 0 {
                Label(ByteCountFormatter.string(fromByteCount: Int64(store.resultBytes), countStyle: .file) + " in results", systemImage: "internaldrive")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !store.isRunning && (store.isPaused || store.batch.hasQueuedWork || store.batch.jobs.contains(where: { $0.status == .interrupted })) {
                Button("Resume", systemImage: "play.fill") { store.resume() }
                    .buttonStyle(.bordered)
                    .disabled(store.isExporting)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FILES")
                .font(.caption.weight(.semibold)).tracking(1.3)
                .foregroundStyle(.secondary)
            LazyVStack(spacing: 12) {
                ForEach(store.batch.jobs) { job in
                    JobRow(job: job, busy: store.isExporting) {
                        export = ExportRequest(kind: .save(job))
                    } share: {
                        export = ExportRequest(kind: .share([job]))
                    } retry: {
                        store.retry(job.id)
                    } cancel: {
                        store.cancel(job.id)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if store.isExporting {
                ProgressView("Exporting \(store.exportProgress.formatted(.percent.precision(.fractionLength(0))))", value: store.exportProgress)
                Button("Cancel export", role: .cancel) { store.cancelExport() }
            } else {
                if !store.batch.jobs.isEmpty {
                    Button { export = ExportRequest(kind: .folder) } label: {
                        Label(exportTitle("Save"), systemImage: "folder")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canExportAll)
                    Button { export = ExportRequest(kind: .share(store.batch.unexportedResults)) } label: {
                        Label(exportTitle("Share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canExportAll)
                }
                Button { importing = true } label: {
                    Label("Add CIA files", systemImage: "plus")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func exportTitle(_ action: String) -> String {
        if store.completed.contains(where: \.exported) { return "\(action) Unsaved" }
        return store.batch.unexportedResults.count > 1 ? "\(action) All" : action
    }
}

private struct JobRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let job: ConversionJob
    let busy: Bool
    let save: () -> Void
    let share: () -> Void
    let retry: () -> Void
    let cancel: () -> Void

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
                    Text(job.inputName).font(.subheadline.weight(.semibold)).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    HStack(spacing: 7) {
                        Text(job.exportLabel ?? job.status.label).foregroundStyle(statusColor)
                        Text("·").foregroundStyle(.tertiary)
                        Text(ByteCountFormatter.string(fromByteCount: job.inputBytes, countStyle: .file)).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
                if job.status == .queued || job.status == .running {
                    Button("Cancel file", systemImage: "xmark", action: cancel)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(busy)
                }
            }
            if job.status == .running {
                ProgressView(value: job.progress)
                    .accessibilityLabel("\(job.inputName) progress")
                HStack {
                    Text(job.message ?? "Converting")
                    Spacer()
                    Text(job.progress.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if let message = job.message, job.status != .cancelled {
                Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if job.status == .completed {
                resultLayout {
                    Button(job.exportDestination == .files ? "Save again" : "Save to Files", systemImage: "folder", action: save)
                    Button("Share", systemImage: "square.and.arrow.up", action: share)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(busy)
            } else if job.status.canRetry {
                Button("Retry", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.bordered)
                    .disabled(busy)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    if isExported { RoundedRectangle(cornerRadius: 20).fill(Color.teal.opacity(0.08)) }
                }
        }
        .overlay {
            if isExported { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.teal.opacity(0.4), lineWidth: 1) }
        }
    }

    private var resultLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }

    private var symbol: String {
        if isExported { return "checkmark.seal.fill" }
        return switch job.status {
        case .queued: "clock"
        case .running: "arrow.trianglehead.2.clockwise.rotate.90"
        case .completed: "checkmark.circle.fill"
        case .failed, .storagePaused: "exclamationmark.triangle.fill"
        case .interrupted: "pause.circle"
        case .cancelled: "xmark.circle"
        }
    }

    private var statusColor: Color {
        if isExported { return .teal }
        return switch job.status {
        case .completed: .green
        case .running: .conversionAccent
        case .failed, .storagePaused: .orange
        default: .secondary
        }
    }

    private var isExported: Bool { job.status == .completed && job.exported }
}
