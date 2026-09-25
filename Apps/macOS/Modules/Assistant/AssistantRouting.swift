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
    ]

    static func route(_ question: String, followsContext: Bool = false, now: Date = .now) -> AssistantRoute {
        let folded = AssistantHTML.fold(question)
        let words = folded.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)
        if words.contains(where: contextWords.contains) || contextPhrases.contains(where: folded.contains) {
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
