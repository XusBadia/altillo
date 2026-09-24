import AltilloCore
import Foundation

/// Every sentence the usage section says, in one place and free of views so tests can read them: the pace, when a
/// limit refills, balances ("$7.50 left"), what went wrong (one clear sentence each, PLAN §4) and the status
/// Settings shows per provider.
enum UsageText {
    // MARK: Windows

    /// "the session", "the week", "the Sonnet week": what a sentence says a limit is.
    static func phrase(for window: UsageWindow) -> String {
        switch window.kind {
        case .session: String(localized: "the session")
        case .weekly: String(localized: "the week")
        case .monthly: String(localized: "the month")
        case .modelWeekly, .other: window.label
        }
    }

    /// "Session", "Week", "Sonnet week": a limit's name at the start of a sentence or a row.
    static func name(for window: UsageWindow) -> String {
        switch window.kind {
        case .session: String(localized: "Session")
        case .weekly: String(localized: "Week")
        case .monthly: String(localized: "Month")
        case .modelWeekly, .other: window.label
        }
    }

    /// The window's length, short: "5 h", "7 d". Nil when unknown.
    static func length(of window: UsageWindow) -> String? {
        guard let duration = window.duration, duration > 0 else { return nil }
        let hours = Int((duration / 3600).rounded())
        if hours < 24 { return String(localized: "\(hours) h") }
        return String(localized: "\(Int((duration / 86_400).rounded())) d")
    }

    /// A moment, as short as it can be said: "16:10" today, "Fri 09:00" later this week, "3 Oct" beyond.
    static func moment(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if date.timeIntervalSince(now) < 6 * 86_400 {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "refills in 1 h 12 min", or, before the window has started (Claude's session before the first message),
    /// "starts with your next message". A longer limit without a date says so.
    static func refillsIn(_ window: UsageWindow, now: Date = .now) -> String {
        guard let resetsAt = window.resetsAt else {
            return window.kind == .session
                ? String(localized: "starts with your next message")
                : String(localized: "no refill date")
        }
        if resetsAt <= now { return String(localized: "refilling now") }
        return String(localized: "refills in \(NotchFormat.countdown(to: resetsAt, now: now))")
    }

    /// "refills 16:10", for the alert's figure.
    static func refillsAt(_ window: UsageWindow, now: Date = .now) -> String? {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        return String(localized: "refills \(moment(resetsAt, now: now))")
    }

    // MARK: Balances

    /// An amount in its unit, as short as it reads well: "$7.50" for a currency, "1,250" or "12.5K" otherwise (the
    /// unit's word goes in the caption, see `unitWord`).
    static func number(_ value: Double, unit: String) -> String {
        if let code = currencyCode(unit) {
            let whole = value.rounded() == value && abs(value) >= 100
            return value.formatted(.currency(code: code).precision(.fractionLength(whole ? 0 : 2)))
        }
        if abs(value) >= 10_000 {
            return value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// The amount with its unit: "$7.50", "340 credits".
    static func amount(_ value: Double, unit: String) -> String {
        guard let word = unitWord(unit) else { return number(value, unit: unit) }
        return "\(number(value, unit: unit)) \(word)"
    }

    /// The word after a number ("credits", "requests"); nil for a currency, whose symbol goes with the number.
    static func unitWord(_ unit: String) -> String? {
        let trimmed = unit.trimmingCharacters(in: .whitespaces)
        guard currencyCode(trimmed) == nil, !trimmed.isEmpty else { return nil }
        // The collectors' units are English identifiers; the ones they use get a word in the user's language.
        switch trimmed.lowercased() {
        case "credits": return String(localized: "credits")
        case "resets": return String(localized: "limit resets")
        case "requests": return String(localized: "requests")
        default: return trimmed
        }
    }

    /// "USD", "usd", "$" → "USD"; nil for anything that isn't money.
    static func currencyCode(_ unit: String) -> String? {
        let upper = unit.trimmingCharacters(in: .whitespaces).uppercased()
        if upper == "$" { return "USD" }
        if upper == "€" { return "EUR" }
        guard upper.count == 3 else { return nil }
        return Locale.Currency.isoCurrencies.contains { $0.identifier == upper } ? upper : nil
    }

    /// A balance's figure and the few words after it: ("$7.50", "left"), ("340", "credits left"),
    /// ("$12.50", "of $20"), ("1,200", "requests used"). Nil when the provider gave no amount at all.
    static func figure(for balance: UsageBalance) -> (value: String, caption: String)? {
        let word = unitWord(balance.unit)
        if let remaining = balance.remaining {
            let caption = word.map { String(localized: "\($0) left") } ?? String(localized: "left")
            return (number(remaining, unit: balance.unit), caption)
        }
        if let used = balance.used, let limit = balance.limit, limit > 0 {
            return (number(used, unit: balance.unit), String(localized: "of \(amount(limit, unit: balance.unit))"))
        }
        if let used = balance.used {
            let caption = word.map { String(localized: "\($0) used") } ?? String(localized: "used")
            return (number(used, unit: balance.unit), caption)
        }
        return nil
    }

    /// The balance in one short phrase for a row: "$7.50 left", "120 of 300 requests", "1,200 requests used".
    static func summary(of balance: UsageBalance) -> String {
        if let remaining = balance.remaining {
            return String(localized: "\(amount(remaining, unit: balance.unit)) left")
        }
        if let used = balance.used, let limit = balance.limit, limit > 0 {
            return String(localized: "\(number(used, unit: balance.unit)) of \(amount(limit, unit: balance.unit))")
        }
        if let used = balance.used { return String(localized: "\(amount(used, unit: balance.unit)) used") }
        return balance.label
    }

    /// How much of a balance with a known limit is spent, 0…1 (more when over). Nil without a limit.
    static func spentFraction(of balance: UsageBalance) -> Double? {
        guard let limit = balance.limit, limit > 0 else { return nil }
        if let used = balance.used { return max(used / limit, 0) }
        if let remaining = balance.remaining { return max(1 - remaining / limit, 0) }
        return nil
    }

    // MARK: Pace

    enum Tone: Equatable, Sendable { case calm, good, warning, critical }

    /// The pace in a few words ("Plenty left", "On track", "Runs out at 16:40", "Limit reached"), or nil when it's
    /// too early to tell.
    static func pace(for window: UsageWindow, now: Date = .now) -> (text: String, tone: Tone)? {
        if window.used >= 1 { return (String(localized: "Limit reached"), .critical) }
        switch UsagePace.evaluate(window, now: now) {
        case .ahead:
            return (String(localized: "Plenty left"), .good)
        case .onTrack:
            return (String(localized: "On track"), .calm)
        case let .behind(runsOutAt?):
            return (String(localized: "Runs out at \(moment(runsOutAt, now: now))"),
                    window.used >= 0.95 ? .critical : .warning)
        case .behind(nil):
            return (String(localized: "Running fast"), .warning)
        case .unknown:
            return nil
        }
    }

    // MARK: Problems

    /// The command-line tool whose sign-in Altillo reads, to tell the user what to open.
    static func toolName(for id: UsageProviderID, displayName: String) -> String {
        switch id {
        case .claude: "Claude Code"
        case .codex: "Codex"
        default: displayName
        }
    }

    /// One clear sentence about what went wrong, for the card and the tooltip.
    static func sentence(for problem: UsageProblem, provider id: UsageProviderID, displayName: String,
                         now: Date = .now) -> String {
        let tool = toolName(for: id, displayName: displayName)
        switch problem {
        case .notSignedIn:
            return String(localized: "Sign in to \(tool) on this Mac and it shows up here.")
        case .sessionExpired:
            return String(localized: "The sign-in expired. Open \(tool) once and it's back.")
        case let .rateLimited(retryAfter):
            if let retryAfter, retryAfter > now {
                return String(localized: "\(displayName) asked to slow down. Trying again at \(moment(retryAfter, now: now)).")
            }
            return String(localized: "\(displayName) asked to slow down. Trying again in a few minutes.")
        case .unreachable:
            return String(localized: "Couldn't reach \(displayName). Showing the last numbers.")
        case .unexpectedResponse:
            return String(localized: "\(displayName) answered in a way Altillo doesn't understand yet.")
        case .accessDenied:
            return String(localized: "Altillo wasn't allowed to read the \(tool) sign-in. Allow it when macOS asks.")
        }
    }

    /// A few words for tight places (the status line under the ring, Settings' row).
    static func shortStatus(for problem: UsageProblem) -> String {
        switch problem {
        case .notSignedIn: String(localized: "Not signed in")
        case .sessionExpired: String(localized: "Sign-in expired")
        case .rateLimited: String(localized: "Rate limited")
        case .unreachable: String(localized: "Unreachable")
        case .unexpectedResponse: String(localized: "Can't read it")
        case .accessDenied: String(localized: "Not allowed")
        }
    }

    /// Whether "Try again" can help (a rate limit has its own time; signing in happens elsewhere).
    static func canRetry(_ problem: UsageProblem) -> Bool {
        switch problem {
        case .rateLimited, .notSignedIn: false
        case .sessionExpired, .unreachable, .unexpectedResponse, .accessDenied: true
        }
    }

    // MARK: Settings

    /// What Settings says under a provider's name: "Connected · Max 20x", "Sign-in expired: open Claude Code once"…
    static func status(for entry: UsageStore.Entry, now: Date = .now) -> String {
        guard entry.isAvailable else {
            return String(localized: "Not set up on this Mac")
        }
        guard let usage = entry.usage else { return String(localized: "Checking…") }
        if let problem = usage.problem {
            switch problem {
            case .sessionExpired:
                return String(localized: "Sign-in expired: open \(toolName(for: entry.id, displayName: entry.displayName)) once")
            case .notSignedIn:
                return String(localized: "Not signed in on this Mac")
            default:
                return shortStatus(for: problem)
            }
        }
        let connected = String(localized: "Connected")
        if let plan = usage.plan, !plan.isEmpty { return "\(connected) · \(plan)" }
        return connected
    }
}

// MARK: - Setup hints

extension UsageText {
    /// How to set a provider up, in the user's language. The collectors (AltilloUsage) only carry an English hint;
    /// it's the fallback for any provider not listed here. Markdown backticks render as code in Settings.
    static func setupHint(for id: UsageProviderID, fallback: String) -> String {
        switch id.rawValue {
        case "claude": String(localized: "Sign in to Claude Code on this Mac")
        case "codex": String(localized: "Sign in to the Codex CLI on this Mac")
        case "cursor": String(localized: "Sign in to Cursor on this Mac")
        case "copilot": String(localized: "Sign in to GitHub Copilot in your editor, or run `gh auth login`")
        case "gemini": String(localized: "Open Antigravity or sign in with `agy` on this Mac")
        case "grok": String(localized: "Sign in to the Grok CLI on this Mac (run `grok login`)")
        case "openrouter": String(localized: "Add an OpenRouter API key to `~/.config/openrouter/key.json`")
        case "zai": String(localized: "Add a Z.ai API key to `~/.config/zai/key.json`")
        case "devin": String(localized: "Sign in to Devin on this Mac (run `devin auth login` or open the app)")
        case "opencode": String(localized: "Sign in to OpenCode Go in OpenCode on this Mac")
        default: fallback
        }
    }
}
