import Foundation
import Observation

// Phase 13: answers worth keeping. Conversations stay in memory only; an answer the user saves on purpose is the
// one thing Ask writes down, in a small private JSON file in Application Support, never anywhere else.

/// An answer the user chose to keep.
struct AssistantSavedAnswer: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// The exchange it came from, so the answer's Save button knows it's saved.
    var exchangeID: UUID
    var question: String
    /// As the model wrote it (Markdown).
    var answer: String
    var savedAt: Date
    /// What was attached when it was asked, if anything (only the name is kept).
    var attachmentName: String?
}

/// The saved answers, newest first. Loaded on first use and written after every change.
@MainActor
@Observable
final class AssistantSavedStore {
    /// Plenty for a notch; the oldest go first beyond this.
    static let limit = 200

    private(set) var answers: [AssistantSavedAnswer] = []
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isLoaded = false

    static let defaultURL = URL.applicationSupportDirectory
        .appending(path: "Altillo/Ask/Saved answers.json", directoryHint: .notDirectory)

    /// Loads right away, so the list is there after a relaunch before anything asks for it.
    init(fileURL: URL = AssistantSavedStore.defaultURL, now: Date = .now) {
        self.fileURL = fileURL
        load(now: now)
    }

    /// Reads the file once. One that can't be read is moved aside (`Saved answers (unreadable <date>).json`),
    /// never overwritten by the next save.
    func load(now: Date = .now) {
        guard !isLoaded else { return }
        isLoaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            answers = try decoder.decode([AssistantSavedAnswer].self, from: data)
        } catch {
            let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
                .timeSeparator(.omitted))
            let aside = fileURL.deletingLastPathComponent()
                .appending(path: "Saved answers (unreadable \(stamp)).json", directoryHint: .notDirectory)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            SpikeLog.shared.record(SpikeLog.Category.assistant, "saved answers unreadable, moved aside: \(error)")
        }
    }

    func isSaved(_ exchangeID: UUID) -> Bool {
        load()
        return answers.contains { $0.exchangeID == exchangeID }
    }

    /// Saves an answer (once: saving it again does nothing).
    @discardableResult
    func save(question: String, answer: String, exchangeID: UUID, attachmentName: String? = nil,
              now: Date = .now) -> AssistantSavedAnswer? {
        load()
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !answers.contains(where: { $0.exchangeID == exchangeID })
        else { return nil }
        let saved = AssistantSavedAnswer(
            id: UUID(), exchangeID: exchangeID, question: question, answer: answer, savedAt: now,
            attachmentName: attachmentName
        )
        answers.insert(saved, at: 0)
        if answers.count > Self.limit { answers.removeLast(answers.count - Self.limit) }
        persist()
        return saved
    }

    func remove(_ id: UUID) {
        load()
        answers.removeAll { $0.id == id }
        persist()
    }

    /// Unsaves the answer of an exchange (the Save button pressed again).
    func remove(exchangeID: UUID) {
        load()
        answers.removeAll { $0.exchangeID == exchangeID }
        persist()
    }

    /// Written atomically, readable only by the user (0600, folder 0700). An empty list removes the file.
    private func persist() {
        let manager = FileManager.default
        do {
            guard !answers.isEmpty else {
                try? manager.removeItem(at: fileURL)
                return
            }
            let folder = fileURL.deletingLastPathComponent()
            try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(answers).write(to: fileURL, options: [.atomic])
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path(percentEncoded: false))
        } catch {
            SpikeLog.shared.record(SpikeLog.Category.assistant, "saving answers FAILED: \(error.localizedDescription)")
        }
    }
}
