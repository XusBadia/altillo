import AltilloCore
import AppKit
import Foundation
import Observation
import os
import SwiftUI

/// In-app log for the phase 0 drag & drop spikes, so the test matrix can be checked without Console.app.
/// Every entry is mirrored to the unified log (subsystem `altillo`, category `spike`) so `log stream` works too.
@MainActor
@Observable
final class SpikeLog {
    static let shared = SpikeLog()

    /// Categories used by the drag & drop spikes (see docs/pruebas-drag-drop.md).
    enum Category {
        static let dragStart = "drag-start"
        static let dragEnd = "drag-end"
        static let drop = "drop"
        static let ingest = "ingest"
        static let promise = "promise"
        static let dragOut = "drag-out"
        static let quickLook = "quicklook"
        static let shelf = "shelf"
        static let app = "app"
        static let alerts = "alerts"
        static let assistant = "assistant"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let category: String
        let message: String
    }

    /// Oldest entries are dropped past this count so a long session never grows unbounded.
    static let capacity = 2_000

    private(set) var entries: [Entry] = []

    @ObservationIgnored private let logger = Logger(subsystem: "altillo", category: "spike")

    func record(_ category: String, _ message: String) {
        logger.log("[\(category, privacy: .public)] \(message, privacy: .public)")
        entries.append(Entry(category: category, message: message))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Records from any thread (file promise callbacks run on a background queue).
    nonisolated static func post(_ category: String, _ message: String) {
        Task { @MainActor in shared.record(category, message) }
    }

    /// Plain-text export, one line per entry.
    static func export(_ entries: [Entry]) -> String {
        entries.map { "\(timestamp($0.date)) [\($0.category)] \($0.message)" }.joined(separator: "\n")
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
            .secondFraction(.fractional(3)))
    }
}

struct SpikeLogView: View {
    static let windowID = "spike-log"
    let log: SpikeLog

    @State private var category: String?
    @State private var autoScroll = true

    private var categories: [String] {
        var seen: [String] = []
        for entry in log.entries where !seen.contains(entry.category) { seen.append(entry.category) }
        return seen
    }

    private var visible: [SpikeLog.Entry] {
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
                NSPasteboard.general.setString(SpikeLog.export(visible), forType: .string)
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
        let entry: SpikeLog.Entry

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SpikeLog.timestamp(entry.date))
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
            case SpikeLog.Category.dragStart, SpikeLog.Category.dragEnd: .blue
            case SpikeLog.Category.drop: .green
            case SpikeLog.Category.ingest: .orange
            case SpikeLog.Category.promise: .purple
            case SpikeLog.Category.dragOut: .pink
            case SpikeLog.Category.shelf: .yellow
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
            SpikeLog.shared.record(SpikeLog.Category.ingest, "FAILED creating the test file: \(error.localizedDescription)")
            return nil
        }
    }
}
