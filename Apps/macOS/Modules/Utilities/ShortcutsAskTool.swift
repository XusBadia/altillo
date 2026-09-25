import Foundation
import FoundationModels

// MARK: - Ask: running a shortcut

/// Ask's `runShortcut` tool. An action, so it's fenced three times: the question must say explicitly to run a
/// shortcut (`ShortcutsAskIntent`, which routes it to `AssistantRoute.shortcut`, the only route with this tool);
/// the name must match one of the user's shortcuts without ambiguity (`ShortcutsCLI.match`); and the same shortcut
/// is never run twice in a row by Ask within `ShortcutsAsk.repeatWindow` (the store retries a failed answer in a
/// fresh session, and the small model sometimes calls a tool twice).
struct RunShortcutTool: Tool {
    let name = "runShortcut"
    let description = "Runs one of the user's Shortcuts by name. Only for a shortcut the user asked to run."

    @Generable
    struct Arguments {
        @Guide(description: "The shortcut's name, as the user wrote it.")
        var name: String
    }

    var perform: @MainActor @Sendable (String) async -> String = { await ShortcutsAsk.liveRun($0) }
    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.shortcuts)
        let answer = await perform(arguments.name)
        await SpikeLog.shared.record(SpikeLog.Category.assistant, "tool runShortcut → \(answer.count) chars")
        return answer
    }
}

/// Recognises an explicit request to run a shortcut: a verb like "run" / "ejecuta" / "executa" and the word
/// "shortcut" / "atajo" / "drecera" with a name next to them ("run my Coffee shortcut", "ejecuta el atajo Café").
/// Questions about shortcuts ("how do I run a shortcut?") aren't requests.
enum ShortcutsAskIntent {
    static let verbs: Set<String> = [
        "run", "launch", "start", "trigger", "execute", "fire",
        "ejecuta", "ejecutar", "ejecutame", "ejecute", "lanza", "lanzar", "lanzame", "corre", "arranca", "activa",
        "executa", "executar", "executa'm", "llanca", "engega",
        "lance", "lancer", "demarre", "starte", "fuhre", "avvia", "esegui",
    ]

    static let nouns: Set<String> = [
        "shortcut", "shortcuts", "atajo", "atajos", "drecera", "dreceres", "raccourci", "raccourcis",
        "kurzbefehl", "kurzbefehle", "atalho", "atalhos", "scorciatoia",
    ]

    /// Words that don't make a name ("run **my** shortcut **please**").
    static let fillers: Set<String> = [
        "my", "the", "a", "an", "this", "that", "please", "now", "for", "me", "again", "called", "named",
        "mi", "mis", "el", "la", "los", "las", "un", "una", "ese", "este", "esta", "por", "favor", "ahora", "llamado",
        "que", "se", "llama", "meu", "meva", "ara", "si", "us", "plau", "de", "del", "mon", "ma", "le", "les", "du",
        "mein", "meinen", "den", "die", "das", "il", "mio", "lo",
    ]

    /// Openings of a question about shortcuts rather than a request to run one (folded).
    static let questionOpenings = [
        "how ", "how'", "what ", "what'", "whats ", "why ", "which ", "when ", "where ", "is there", "are there",
        "como ", "que ", "por que", "cual", "cuando", "donde", "hay ",
        "com ", "quin", "per que", "quan ", "on ", "comment", "pourquoi", "quel", "wie ", "was ", "warum",
    ]

    static func isExplicitRun(_ question: String) -> Bool {
        let folded = AssistantHTML.fold(question)
        let start = folded.drop { !$0.isLetter }
        if questionOpenings.contains(where: { start.hasPrefix($0) }) { return false }
        let words = folded.split { $0.isWhitespace || ($0.isPunctuation && $0 != "'") }.map(String.init)
        guard let verb = words.firstIndex(where: verbs.contains),
              let noun = words[(verb + 1)...].firstIndex(where: nouns.contains),
              noun - verb <= 7 else { return false }
        let between = words[(verb + 1)..<noun].filter { !fillers.contains($0) }
        let after = words[(noun + 1)...].prefix(6).filter { !fillers.contains($0) }
        return !between.isEmpty || !after.isEmpty
    }
}

/// What the `runShortcut` tool does and says, in plain English for the model.
enum ShortcutsAsk {
    /// Ask never runs the same shortcut again this soon after it last ran it.
    static let repeatWindow: TimeInterval = 20
    /// How long Ask waits for a result before saying it's still running.
    static let patience: Duration = .seconds(25)

    /// Shortcuts Ask ran lately, by id: when, and what it said then.
    @MainActor static var recentRuns: [ShortcutInfo.ID: (at: Date, answer: String)] = [:]

    @MainActor
    static func liveRun(_ requested: String) async -> String {
        guard let model = AssistantAgents.live else { return "Altillo can't run shortcuts right now. Nothing was run." }
        return await run(requested, store: model.shortcuts, isEnabled: model.settings.isEnabled(.shortcuts))
    }

    @MainActor
    static func run(_ requested: String, store: ShortcutsStore, isEnabled: Bool, now: Date = .now,
                    patience: Duration = patience) async -> String {
        guard isEnabled else {
            return "Altillo's Shortcuts section is off, so it doesn't run shortcuts. Nothing was run. Tell the user they can turn it on in Settings › Sections."
        }
        await store.loadIfNeeded()
        switch store.phase {
        case .missing:
            return "This Mac has no Shortcuts command, so nothing was run."
        case let .failed(message) where store.shortcuts.isEmpty:
            return "Altillo couldn't list the user's shortcuts (\(message)). Nothing was run."
        default:
            break
        }
        switch ShortcutsCLI.match(requested, in: store.shortcuts) {
        case .none:
            let names = store.shortcuts.prefix(15).map { "\"\($0.name)\"" }.joined(separator: ", ")
            let list = names.isEmpty ? "The user has no shortcuts." : "Their shortcuts include: \(names)."
            return "The user has no shortcut called \"\(requested)\". Nothing was run. \(list)"
        case let .ambiguous(candidates):
            let names = candidates.prefix(6).map { "\"\($0.name)\"" }.joined(separator: ", ")
            return "More than one shortcut matches \"\(requested)\": \(names). Nothing was run; ask the user which one."
        case let .found(shortcut):
            if let recent = recentRuns[shortcut.id], now.timeIntervalSince(recent.at) < repeatWindow {
                return recent.answer + " (It was run just now; it wasn't run again.)"
            }
            if store.runs[shortcut.id] == .running {
                return "The shortcut \"\(shortcut.name)\" is already running; it wasn't started again."
            }
            recentRuns[shortcut.id] = (now, "The shortcut \"\(shortcut.name)\" is running.")
            let started = Date.now
            let running = Task { @MainActor in await store.run(shortcut) }
            let state = await withTaskGroup(of: ShortcutsStore.RunState?.self) { group in
                group.addTask { await running.value }
                group.addTask {
                    try? await Task.sleep(for: patience)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            let answer = sentence(for: shortcut, state: state)
            // The window counts from when it finished.
            recentRuns[shortcut.id] = (now.addingTimeInterval(Date.now.timeIntervalSince(started)), answer)
            return answer
        }
    }

    /// One or two sentences for the model about how the run went.
    static func sentence(for shortcut: ShortcutInfo, state: ShortcutsStore.RunState?) -> String {
        switch state {
        case nil, .running?:
            return "Started the shortcut \"\(shortcut.name)\". It's still running; the Shortcuts section shows when it's done."
        case let .succeeded(output)?:
            var text = "Ran the shortcut \"\(shortcut.name)\". It finished successfully."
            if let output, !output.isEmpty {
                let excerpt = output.count > 400 ? String(output.prefix(399)) + "…" : output
                text += " Its output: \"\(excerpt)\""
            }
            return text
        case let .failed(message)?:
            return "Ran the shortcut \"\(shortcut.name)\", but it failed: \(message)"
        }
    }
}
