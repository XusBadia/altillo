import Foundation

// MARK: - Routes

/// What kind of question it is, decided before the model sees it. The on-device model reaches for every tool it's
/// given (a haiku request read the shelf, the calendar and the clipboard, then apologised), so each question only
/// gets the tools it needs: none for general knowledge and writing, Altillo's own context for questions about the
/// user's things, and web results already in the prompt for questions about something live.
enum AssistantRoute: String, Equatable, Sendable {
    /// Knowledge, writing, translation, explanations, ideas: answered from the model alone.
    case chat
    /// The user's shelf, calendar, music, clipboard or AI usage: the local tools.
    case context
    /// News, scores, weather, prices: looked up first (when the web is allowed), then answered from the results.
    case live
    /// "Run my Coffee shortcut", "ejecuta el atajo Café": an explicit request to run one of the user's Shortcuts
    /// (`ShortcutsAskIntent`). The only route with the `runShortcut` tool.
    case shortcut
    /// "Remind me to call Ana tomorrow at 10", «recuérdame comprar pan a las 7» (phase 13): a reminder in the
    /// Reminders app. The only route with the `reminders` tool.
    case reminder
    /// "Tell Claude to run the tests", «dile a Codex que siga» (phase 13): the words go to a waiting agent as
    /// typed (`AgentReplyIntent`, `AssistantAgentReply`). No model and no tools: Altillo does it and says so.
    case agentReply

    /// Routes that do something rather than answer: no web lookups, no retries once done, no attachment detour.
    var acts: Bool { self == .reminder || self == .shortcut || self == .agentReply }
}

enum AssistantRouter {
    /// Words that point at the user's own things (folded: lowercase, no accents).
    static let contextWords: Set<String> = [
        // Shelf
        "shelf", "estanteria", "prestatge", "prestatgeria", "altillo", "file", "files", "archivo", "archivos",
        "fitxer", "fitxers", "document", "documents", "documento", "documentos", "pdf", "note", "notes", "nota",
        "notas", "summarize", "summarise", "resume", "resumen", "resumeix",
        // Calendar
        "calendar", "calendario", "calendari", "agenda", "meeting", "meetings", "reunion", "reuniones", "reunio",
        "reunions", "event", "events", "evento", "eventos", "esdeveniment", "esdeveniments", "appointment",
        "appointments", "cita", "citas", "schedule", "busy", "ocupado", "ocupada", "ocupat",
        // Music
        "playing", "song", "songs", "cancion", "canco", "music", "musica", "spotify", "sonando", "sona",
        "escuchando", "listening", "album", "artist", "artista",
        // Clipboard
        "clipboard", "portapapeles", "porta-retalls", "copied", "copy", "copiado", "copiada", "copie", "copiat",
        "pasted",
        // AI usage
        "usage", "uso", "consumo", "quota", "cuota", "limit", "limits", "limite", "limites",
        // Coding agents (plural: "what is an agent?" is a general question)
        "agents", "agentes",
        // Timer and note (phase 12): the first things Ask does rather than reads
        "timer", "timers", "temporizador", "temporizadores", "temporitzador", "temporitzadors", "pomodoro",
        "apunta", "apuntame", "apuntalo", "anota", "anotame", "anotalo", "jot",
    ]

    /// Ways of asking about one's own day ("what do I have", "¿qué tengo?").
    static let contextPhrases = [
        "do i have", "have i got", "am i free", "my day", "tengo hoy", "tengo manana", "que tengo", "estoy libre",
        "mi dia", "tinc avui", "tinc dema", "que tinc", "el meu dia",
        // What's left of an AI plan ("¿cuánto me queda de Claude?", "how much Codex is left?")
        "me queda", "nos queda", "em queda", "have left", "is left", "left of my", "remaining", "refill", "resets", "session reset", "limit reset",
        "se reinicia", "se renueva", "es renova", "como voy de", "como vamos de", "com vaig de", "how am i doing on",
        // What an agent is up to ("¿qué está haciendo Codex?", "what's Claude doing?", "is Codex done?"), always with
        // its name: "¿qué tiempo está haciendo?" is about the weather.
        "claude doing", "codex doing", "claude up to", "codex up to", "claude done", "codex done", "claude finished",
        "codex finished", "claude working", "codex working", "claude waiting", "codex waiting", "hace claude",
        "hace codex", "haciendo claude", "haciendo codex", "claude termin", "codex termin", "claude acab",
        "codex acab", "terminado claude", "terminado codex", "acabado claude", "acabado codex", "fa claude", "fa codex", "fent claude", "fent codex", "my agent", "mi agente", "el meu agent",
        // Writing something down ("write down that …"; "note" and «nota» are words above)
        "write down", "write this down", "write that down",
    ]

    /// Verbs that, with a duration ("pon 10 min", "avísame en media hora", "start 25 minutes"), ask for a timer.
    static let timerVerbs: Set<String> = [
        "pon", "ponme", "poner", "set", "start", "remind", "avisame", "avisa", "posa", "posam", "avisam",
        "countdown",
    ]

    /// "pon 10 min": a timer verb and a duration, without the word "timer".
    static func asksForTimer(_ question: String) -> Bool {
        let folded = AssistantHTML.fold(question).replacingOccurrences(of: "'", with: "")
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard words.contains(where: timerVerbs.contains) else { return false }
        return TimerDurationParser.seconds(in: question, bareNumbersAreMinutes: false) != nil
    }

    /// A reminder named as such ("create a reminder", «pon un recordatorio»), folded prefixes.
    static let reminderNouns = ["reminder", "recordatorio", "recordatori"]
    /// Imperatives that make one, when they start the sentence.
    static let reminderMakingWords: Set<String> = [
        "create", "add", "set", "make", "crea", "crear", "creame", "anade", "anademe", "anadir", "pon", "ponme",
        "poner", "haz", "hazme", "fes", "fes-me", "afegeix", "afegir", "posa", "posa'm", "new", "nuevo", "nou",
    ]
    /// Words a question starts with (folded). "Can you remind me…" is a request, so modal verbs aren't here.
    static let questionWords: Set<String> = [
        "how", "what", "what's", "whats", "which", "where", "when", "why", "who", "is", "are", "do", "does", "did",
        "como", "que", "cual", "cuales", "donde", "cuando", "quien", "com", "quin", "quina", "quan",
    ]
    /// Polite openers skipped before the first word.
    private static let openers: Set<String> = ["please", "hey", "porfa", "porfavor", "si", "siusplau", "ok", "vale"]
    /// Accented question words that may follow «recuérdame» ("recuérdame qué es un monad" is a question).
    private static let accentedQuestionWords: Set<String> = [
        "qué", "cómo", "cuál", "cuándo", "dónde", "quién", "què", "com", "quan", "on", "quin", "quina",
    ]
    private static let clitics = ["mela", "melo", "sela", "selo", "les", "los", "las", "nos", "me", "te", "se", "le",
                                  "la", "lo"]

    /// The sentence's words, lowercased with their accents (`raw`) and folded (`folded`), openers skipped.
    private static func words(_ question: String) -> (raw: [String], folded: [String]) {
        let raw = question.lowercased().replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "-" }.map(String.init)
        var index = 0
        while index < raw.count, openers.contains(AssistantHTML.fold(raw[index])) { index += 1 }
        if index < raw.count - 1, raw[index] == "por", raw[index + 1] == "favor" { index += 2 }
        let kept = Array(raw[index...])
        return (kept, kept.map(AssistantHTML.fold))
    }

    /// An infinitive, maybe with pronouns on the end: «llamar», «llamarla», «comprárselo», «trucar».
    private static func isInfinitive(_ folded: String) -> Bool {
        var word = folded
        for _ in 0..<2 {
            if let clitic = clitics.first(where: { word.count > $0.count + 2 && word.hasSuffix($0) }),
               !["ar", "er", "ir", "re"].contains(where: { word.hasSuffix($0) }) {
                word = String(word.dropLast(clitic.count))
            }
        }
        return ["ar", "er", "ir", "re"].contains { word.hasSuffix($0) } && word.count >= 3
    }

    /// An explicit request for a reminder, never a question about them:
    /// - "remind me to <task>"; "remind me about/of/that …" only with a date or time;
    /// - «recuérdame» / «recorda'm» followed by an infinitive or «que», or with a date or time;
    /// - "create / add / set a reminder…", «pon un recordatorio…» starting the sentence.
    /// A timer asked in the same breath ("remind me in 10 minutes") stays a timer.
    static func asksForReminder(_ question: String, now: Date = .now) -> Bool {
        let (raw, folded) = words(question)
        guard let first = folded.first, !questionWords.contains(first) else { return false }
        let hasDate = { ReminderDateParser.parse(question, now: now) != nil }

        // "create a reminder…", «pon un recordatorio…»
        if reminderMakingWords.contains(first),
           folded.prefix(5).contains(where: { word in reminderNouns.contains { word.hasPrefix($0) } }) {
            return true
        }
        for (index, word) in folded.enumerated() {
            let next = index + 1 < raw.count ? raw[index + 1] : nil
            let nextFolded = next.map(AssistantHTML.fold)
            // English: "remind me to …"
            if word == "remind", index + 2 < folded.count, folded[index + 1] == "me" {
                let joiner = folded[index + 2]
                if joiner == "to" { return index + 3 < folded.count && !asksForTimer(question) }
                if ["about", "of", "that"].contains(joiner) { return hasDate() && !asksForTimer(question) }
                continue
            }
            // Spanish and Catalan
            if ["recuerdame", "recordarme", "recuerdamelo", "recorda'm", "recordam", "recorda-me", "recordeu-me"]
                .contains(word) {
                guard let next, let nextFolded else { return false }
                if accentedQuestionWords.contains(next) { return false }
                if next == "que" || isInfinitive(nextFolded) { return true }
                return hasDate() && !asksForTimer(question)
            }
        }
        return false
    }

    /// "Write down …", «apunta …»: the note, which runs even with something attached.
    static func asksForNote(_ question: String) -> Bool {
        let folded = AssistantHTML.fold(question)
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let verbs: Set<String> = ["apunta", "apuntame", "apuntalo", "anota", "anotame", "anotalo", "jot"]
        return words.contains(where: verbs.contains)
            || ["write down", "write this down", "write that down", "add to my note", "add to the note", "note that"]
                .contains(where: folded.contains)
    }

    static func route(_ question: String, followsContext: Bool = false, now: Date = .now) -> AssistantRoute {
        // Before anything else: "run my clipboard shortcut" is a request to run, not a question about the clipboard.
        if ShortcutsAskIntent.isExplicitRun(question) { return .shortcut }
        if AgentReplyIntent.parse(question) != nil { return .agentReply }
        if asksForReminder(question) { return .reminder }
        let folded = AssistantHTML.fold(question)
        let words = folded.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)
        if words.contains(where: contextWords.contains) || contextPhrases.contains(where: folded.contains)
            || asksForTimer(question) {
            return .context
        }
        // "And tomorrow?" right after a calendar answer is still about the calendar.
        if followsContext && words.count <= 6 { return .context }
        if AssistantLiveness.questionLooksLive(question, now: now) { return .live }
        return .chat
    }
}

// MARK: - Does this need the web?

/// Cheap guesses, no model involved: does a question ask about something live, and does an answer admit it
/// couldn't know? Together they decide whether to offer a web search under the answer.
enum AssistantLiveness {
    /// Words that point at something happening now or recently (English, Spanish, Catalan, French, German,
    /// Italian, Portuguese), folded.
    static let liveWords: Set<String> = [
        "today", "tonight", "yesterday", "now", "currently", "latest", "recent", "recently", "score", "scores",
        "result", "results", "won", "winner", "weather", "forecast", "price", "prices", "stock",
        "stocks", "news", "headlines", "election", "standings",
        "hoy", "ahora", "actualmente", "ultimo", "ultima", "ultimos", "ultimas", "ayer", "resultado", "resultados",
        "marcador", "quedo", "gano", "ganador", "partido", "clima", "pronostico", "precio", "precios", "cotizacion",
        "bolsa", "noticias", "elecciones", "clasificacion", "horario", "horarios", "abierto", "opening",
        "avui", "ara", "ahir", "darrer", "darrera", "resultat", "guanyat", "partit", "preu", "noticies",
        "aujourd", "maintenant", "hier", "dernier", "derniere", "meteo", "prix", "actualites",
        "heute", "jetzt", "gestern", "letzte", "ergebnis", "wetter", "preis", "nachrichten",
        "oggi", "ieri", "risultato", "partita", "prezzo", "notizie", "hoje", "ontem", "jogo", "preco",
    ]

    /// Phrases a model uses when it can't know (folded).
    static let admissions = [
        "real-time", "real time", "tiempo real", "temps real", "temps reel", "echtzeit", "tempo reale", "tempo real",
        "internet", "browse", "navegar", "up-to-date", "up to date", "knowledge cutoff", "my training",
        "mi entrenamiento", "don't have access", "do not have access", "no access to", "don't have live",
        "no tengo acceso", "no puedo acceder", "no tinc acces", "can't access", "cannot access", "unable to access",
        "can't check", "cannot check", "can't look up", "no puedo consultar", "no puedo verificar", "no puedo comprobar",
        "no puedo buscar", "live data", "datos en vivo", "current information", "latest information",
        "informacion actualizada", "informacion en tiempo", "can't provide current", "cannot provide current",
        "can't see live", "no puedo ver", "check a reliable", "official website", "sitio web oficial",
        "fuente fiable", "fuente confiable", "recomiendo consultar", "te recomiendo que consultes",
        "i'm not sure", "i am not sure", "i don't know", "no estoy seguro", "no estoy segura", "no lo se",
        "no ho se", "no n'estic segur",
    ]

    static func questionLooksLive(_ question: String, now: Date = .now) -> Bool {
        let words = AssistantHTML.fold(question).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: liveWords.contains) { return true }
        // A year this recent is past what the model knows.
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        return words.contains { Int($0).map { $0 >= year - 1 && $0 <= year + 1 } ?? false }
    }

    static func answerAdmitsNotKnowing(_ answer: String) -> Bool {
        let folded = AssistantHTML.fold(answer).replacingOccurrences(of: "’", with: "'")
        return admissions.contains { folded.contains($0) }
    }

    /// Offer a web search under this answer? Only when web lookups are off (otherwise the model had the tool), and
    /// either the answer admits it couldn't know, or the question is about something live and the answer didn't
    /// come from the user's own things.
    static func shouldOffer(question: String, answer: String, usedLocalTools: Bool, now: Date = .now) -> Bool {
        answerAdmitsNotKnowing(answer) || (!usedLocalTools && questionLooksLive(question, now: now))
    }
}
