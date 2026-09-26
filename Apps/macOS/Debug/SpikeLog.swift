#if DEBUG
import AltilloCore
import AppKit
import Foundation
import SwiftUI

struct SpikeLogView: View {
    static let windowID = "spike-log"
    let log: DiagnosticLog

    @State private var category: String?
    @State private var autoScroll = true

    private var categories: [String] {
        var seen: [String] = []
        for entry in log.entries where !seen.contains(entry.category) { seen.append(entry.category) }
        return seen
    }

    private var visible: [DiagnosticLog.Entry] {
        guard let category else { return log.entries }
        return log.entries.filter { $0.category == category }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            entryList
            Divider()
            SpikeToolsView()
        }
        .frame(minWidth: 520, minHeight: 320)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Category", selection: $category) {
                Text("All").tag(String?.none)
                ForEach(categories, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .frame(maxWidth: 220)
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
            Spacer()
            Text("\(visible.count) entries")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Copy all") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(DiagnosticLog.export(visible), forType: .string)
            }
            .disabled(visible.isEmpty)
            Button("Clear") { log.clear() }
                .disabled(log.entries.isEmpty)
        }
        .padding(10)
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(visible) { entry in
                        EntryRow(entry: entry).id(entry.id)
                    }
                }
                .padding(10)
                .textSelection(.enabled)
            }
            .onChange(of: visible.last?.id) { _, last in
                guard autoScroll, let last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }

    private struct EntryRow: View {
        let entry: DiagnosticLog.Entry

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DiagnosticLog.timestamp(entry.date))
                    .foregroundStyle(.secondary)
                Text(entry.category)
                    .foregroundStyle(color)
                    .frame(width: 80, alignment: .leading)
                Text(entry.message)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.caption, design: .monospaced))
        }

        private var color: Color {
            switch entry.category {
            case DiagnosticLog.Category.dragStart, DiagnosticLog.Category.dragEnd: .blue
            case DiagnosticLog.Category.drop: .green
            case DiagnosticLog.Category.ingest: .orange
            case DiagnosticLog.Category.promise: .purple
            case DiagnosticLog.Category.dragOut: .pink
            case DiagnosticLog.Category.shelf: .yellow
            default: .secondary
            }
        }
    }
}

/// Test helpers for the manual matrix: they work before the shelf UI exists.
private struct SpikeToolsView: View {
    @State private var sampleItems: [ShelfItem] = []

    var body: some View {
        HStack(spacing: 12) {
            Text("Tools").foregroundStyle(.secondary)
            Button("Test Quick Look") {
                if let url = Self.makeSampleFile(named: "Quick Look test.txt") {
                    QuickLookPresenter.show([url])
                }
            }
            Label("Test file", systemImage: "doc")
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: .capsule)
                .help("Drag it out to test drag out (a new file is created in the Inbox)")
                .shelfDraggable(items: { ensureSample() }, onEnded: { _, _ in })
            Button("Open Inbox") {
                let inbox = FileIngest.standard.inboxRoot
                try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                NSWorkspace.shared.open(inbox)
            }
            Spacer()
        }
        .padding(10)
    }

    /// Evaluated when a drag starts: recreates the owned sample file if a previous drag moved it away.
    private func ensureSample() -> [ShelfItem] {
        if let current = sampleItems.first?.fileURL, FileManager.default.fileExists(atPath: current.path) { return sampleItems }
        guard let url = Self.makeSampleFile(named: "Test file.txt") else { return [] }
        sampleItems = [ShelfItem(kind: .file(url, isOwnedCopy: true), displayName: url.lastPathComponent)]
        return sampleItems
    }

    private static func makeSampleFile(named name: String) -> URL? {
        do {
            let url = try FileIngest.standard.makeSlot(forName: name)
            try Data("Altillo test file — \(Date.now.formatted())\n".utf8).write(to: url)
            return url
        } catch {
            DiagnosticLog.shared.record(DiagnosticLog.Category.ingest, "FAILED creating the test file: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
