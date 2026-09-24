import Foundation

// MARK: - Sources

/// A page the web lookup drew on, shown under the answer next to the globe and opened with a click.
struct AssistantWebSource: Hashable, Sendable, Identifiable {
    var url: URL
    var title: String

    var id: URL { url }

    /// "fcbarcelona.es", without the "www.".
    var domain: String { AssistantWeb.domain(of: url) }
}

// MARK: - Lookup

/// Searches DuckDuckGo and reads the top pages, or asks Open-Meteo when the question is about the weather, and
/// hands the model a short plain-text digest (never more than `AssistantContent.toolOutputLimit`).
///
/// DuckDuckGo's HTML endpoint needs no key or account and gives titles, snippets and dates; the snippets alone
/// often hold the fact (a price, a score), and the first one or two pages fill in the rest. Wikipedia is the
/// fallback when DuckDuckGo can't be reached or answers with its bot check. Privacy: only the search words leave
/// the Mac (plus the place name for the weather); requests carry a descriptive User-Agent, no cookies, no cache,
/// and are cancelled with the answer.
enum AssistantWeb {
    struct Lookup: Sendable {
        enum Backend: String, Sendable { case search, weather, wikipedia, none }
        var text: String
        var sources: [AssistantWebSource]
        var backend: Backend
    }

    /// One search result.
    struct Result: Equatable, Sendable {
        var title: String
        var url: URL
        var snippet: String
        /// "2026-09-19" when the engine knows when the page is from.
        var date: String?
    }

    enum Failure: Error, Equatable { case blocked, badResponse, empty }

    /// Per request; the pages are read in parallel, so a lookup takes at most about twice this.
    static let timeout: TimeInterval = 6
    /// Pages bigger than this aren't worth downloading for a few sentences.
    static let pageByteLimit = 3_000_000
    /// How many results the digest lists, and how many of them are read.
    static let resultCount = 5
    static let pagesToRead = 2

    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Altillo/\(version) (Macintosh; on-device assistant; +https://github.com/XusBadia/altillo)"
    }()

    /// Ephemeral: no cookies, no cache, nothing kept between lookups.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 2
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: configuration)
    }()

    /// The whole lookup. Never throws: whatever goes wrong becomes a sentence the model can pass on.
    static func lookUp(_ rawQuery: String) async -> Lookup {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return Lookup(text: "The search was empty. Ask the user what to look up.", sources: [], backend: .none)
        }
        if let place = AssistantWeather.place(in: query),
           let weather = try? await AssistantWeather.lookUp(place: place) {
            return weather
        }
        do {
            let results = try await search(query)
            return await digest(query: query, results: results)
        } catch is CancellationError {
            return Lookup(text: "The search was stopped.", sources: [], backend: .none)
        } catch {
            if Task.isCancelled { return Lookup(text: "The search was stopped.", sources: [], backend: .none) }
            // Wikipedia can't know today's score or price; for anything else it's a decent second best.
            if !AssistantLiveness.questionLooksLive(query), let wikipedia = try? await AssistantWikipedia.lookUp(query) {
                return wikipedia
            }
            return Lookup(
                text: "The web couldn't be reached right now. Tell the user you couldn't search, and answer from what you know if you can.",
                sources: [],
                backend: .none
            )
        }
    }

    // MARK: Search

    /// DuckDuckGo's HTML results, then its "lite" page, then Bing when DuckDuckGo is throttling (it answers bursts
    /// with a bot check for a minute or two). POST for DuckDuckGo, because GET is much more likely to get the check.
    static func search(_ query: String) async throws -> [Result] {
        let attempts: [@Sendable () async throws -> [Result]] = [
            { parseHTMLResults(try await post("https://html.duckduckgo.com/html/", form: ["q": query])) },
            { parseLiteResults(try await post("https://lite.duckduckgo.com/lite/", form: ["q": query])) },
            { parseBingResults(try await get("https://www.bing.com/search", query: ["q": query])) },
        ]
        for attempt in attempts {
            try Task.checkCancellation()
            do {
                let results = try await attempt()
                if !results.isEmpty { return results }
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        throw Failure.empty
    }

    private static func get(_ address: String, query: [String: String]) async throws -> String {
        var components = URLComponents(string: address)
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw Failure.badResponse }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.blocked }
        return decode(data, response: response)
    }

    private static func post(_ address: String, form: [String: String]) async throws -> String {
        guard let url = URL(string: address) else { throw Failure.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(form).utf8)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.blocked }
        let html = decode(data, response: response)
        guard !isBotCheck(html) else { throw Failure.blocked }
        return html
    }

    static func formEncoded(_ form: [String: String]) -> String {
        // ASCII only: `.alphanumerics` would let "ç" through unencoded.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return form.sorted { $0.key < $1.key }
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
    }

    /// DuckDuckGo answers bots it's unsure about with a "select all squares containing a duck" page.
    static func isBotCheck(_ html: String) -> Bool {
        html.contains("anomaly-modal") || html.contains("bots use DuckDuckGo too")
    }

    /// Results from html.duckduckgo.com: `result__a` for the title and link, `result__snippet` for the text.
    /// Ads (links through `y.js`) are skipped.
    static func parseHTMLResults(_ html: String) -> [Result] {
        var results: [Result] = []
        let blocks = html.components(separatedBy: "class=\"result__a\"").dropFirst()
        for block in blocks {
            guard let href = attribute("href", inTagStartingAt: block),
                  let url = resultURL(href),
                  let titleEnd = block.range(of: "</a>"),
                  let titleStart = block.range(of: ">")
            else { continue }
            let title = AssistantHTML.inlineText(String(block[titleStart.upperBound..<titleEnd.lowerBound]))
            var snippet = ""
            if let snippetRange = block.range(of: "class=\"result__snippet\""),
               let open = block[snippetRange.upperBound...].range(of: ">"),
               let close = block[open.upperBound...].range(of: "</a>") {
                snippet = AssistantHTML.inlineText(String(block[open.upperBound..<close.lowerBound]))
            }
            let date = firstDate(in: block.prefix(3_000))
            append(Result(title: title, url: url, snippet: snippet, date: date), to: &results)
        }
        return results
    }

    /// Results from lite.duckduckgo.com: a table with `result-link`, `result-snippet` and `timestamp` cells.
    static func parseLiteResults(_ html: String) -> [Result] {
        var results: [Result] = []
        let blocks = html.components(separatedBy: "class='result-link'").dropFirst()
        let previous = html.components(separatedBy: "class='result-link'")
        for (index, block) in blocks.enumerated() {
            // The href comes before the class in this markup: it's at the end of the previous chunk.
            let before = previous[index]
            guard let hrefRange = before.range(of: "href=\"", options: .backwards) else { continue }
            let hrefTail = before[hrefRange.upperBound...]
            guard let quote = hrefTail.firstIndex(of: "\""),
                  let url = resultURL(String(hrefTail[..<quote])),
                  let titleStart = block.range(of: ">"),
                  let titleEnd = block.range(of: "</a>")
            else { continue }
            let title = AssistantHTML.inlineText(String(block[titleStart.upperBound..<titleEnd.lowerBound]))
            var snippet = ""
            if let snippetRange = block.range(of: "class='result-snippet'"),
               let open = block[snippetRange.upperBound...].range(of: ">"),
               let close = block[open.upperBound...].range(of: "</td>") {
                snippet = AssistantHTML.inlineText(String(block[open.upperBound..<close.lowerBound]))
            }
            append(Result(title: title, url: url, snippet: snippet, date: firstDate(in: block)), to: &results)
        }
        return results
    }

    /// Results from bing.com: `b_algo` items, the link in the `<h2>` (through Bing's `/ck/a` redirect, whose `u`
    /// parameter is the real address in base64), the first paragraph as the snippet.
    static func parseBingResults(_ html: String) -> [Result] {
        var results: [Result] = []
        for block in html.components(separatedBy: "<li class=\"b_algo\"").dropFirst() {
            let item = block.components(separatedBy: "<li class=\"b_algo\"").first ?? block
            guard let heading = item.range(of: "<h2"),
                  let anchor = item[heading.upperBound...].range(of: "<a "),
                  let hrefStart = item[anchor.upperBound...].range(of: "href=\""),
                  let hrefEnd = item[hrefStart.upperBound...].firstIndex(of: "\""),
                  let tagClose = item[hrefEnd...].firstIndex(of: ">"),
                  let titleEnd = item[tagClose...].range(of: "</a>"),
                  let url = bingURL(String(item[hrefStart.upperBound..<hrefEnd]))
            else { continue }
            let title = AssistantHTML.inlineText(String(item[item.index(after: tagClose)..<titleEnd.lowerBound]))
            var snippet = ""
            if let paragraph = item[titleEnd.upperBound...].range(of: "<p"),
               let open = item[paragraph.upperBound...].firstIndex(of: ">"),
               let close = item[open...].range(of: "</p>") {
                snippet = AssistantHTML.inlineText(String(item[item.index(after: open)..<close.lowerBound]))
            }
            append(Result(title: title, url: url, snippet: snippet, date: nil), to: &results)
        }
        return results
    }

    static func bingURL(_ href: String) -> URL? {
        let decoded = AssistantHTML.decodeEntities(href)
        guard let url = URL(string: decoded), let host = url.host() else { return nil }
        guard host.hasSuffix("bing.com") else { return resultURL(decoded) }
        guard let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "u" })?.value,
              encoded.hasPrefix("a1")
        else { return nil }
        var base64 = String(encoded.dropFirst(2))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let target = String(data: data, encoding: .utf8) else { return nil }
        return resultURL(target)
    }

    private static func append(_ result: Result, to results: inout [Result]) {
        guard results.count < 10, !result.title.isEmpty, !results.contains(where: { $0.url == result.url }) else { return }
        results.append(result)
    }

    private static func attribute(_ name: String, inTagStartingAt text: String) -> String? {
        guard let tagEnd = text.firstIndex(of: ">"),
              let start = text[..<tagEnd].range(of: "\(name)=\"")
        else { return nil }
        let tail = text[start.upperBound..<tagEnd]
        guard let quote = tail.firstIndex(of: "\"") else { return nil }
        return String(tail[..<quote])
    }

    /// A result's real address: plain links as they are, DuckDuckGo's redirect (`/l/?uddg=…`) unwrapped, ads
    /// and anything that isn't http(s) left out.
    static func resultURL(_ href: String) -> URL? {
        let decoded = AssistantHTML.decodeEntities(href)
        let absolute = decoded.hasPrefix("//") ? "https:" + decoded : decoded
        guard let url = URL(string: absolute), let host = url.host() else { return nil }
        if host.hasSuffix("duckduckgo.com") {
            guard url.path().hasPrefix("/l/"),
                  let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "uddg" })?.value
            else { return nil }
            return resultURL(target)
        }
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    private static func firstDate<S: StringProtocol>(in text: S) -> String? {
        guard let range = text.range(of: #"\b20\d\d-\d\d-\d\d(?=T)"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    // MARK: Reading pages

    /// Sites that don't serve their content to a plain request (or need an account), so reading them is wasted time.
    static let unreadableHosts = [
        "youtube.com", "youtu.be", "facebook.com", "instagram.com", "x.com", "twitter.com", "tiktok.com",
        "linkedin.com", "pinterest.com", "reddit.com", "accuweather.com", "weather.com", "google.com",
    ]

    static func isReadable(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        let path = url.path().lowercased()
        guard !path.hasSuffix(".pdf") else { return false }
        return !unreadableHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Downloads a page and returns its readable text as lines, or nil when it isn't HTML or text.
    static func fetchLines(_ url: URL) async throws -> [String] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("text/html,text/plain;q=0.9", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.badResponse
        }
        let type = (http.mimeType ?? "text/html").lowercased()
        guard type.hasPrefix("text/html") || type.hasPrefix("application/xhtml") || type.hasPrefix("text/plain"),
              data.count <= pageByteLimit
        else { throw Failure.badResponse }
        let text = decode(data, response: response)
        return type.hasPrefix("text/plain") ? AssistantHTML.cleanLines(text) : AssistantHTML.readableLines(text)
    }

    static func decode(_ data: Data, response: URLResponse) -> String {
        if let name = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let text = String(data: data, encoding: encoding) { return text }
            }
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: Digest

    /// The results as a short list, then what the first readable pages say about the query.
    static func digest(query: String, results: [Result]) async -> Lookup {
        let shown = Array(results.prefix(resultCount))
        let toRead = Array(results.filter { isReadable($0.url) }.prefix(pagesToRead))
        let terms = AssistantHTML.terms(in: query)

        // Read the pages in parallel; a slow one just doesn't make it.
        let pages: [(Int, Result, [String])] = await withTaskGroup(of: (Int, Result, [String])?.self) { group in
            for (index, result) in toRead.enumerated() {
                group.addTask {
                    guard let lines = try? await fetchLines(result.url), !lines.isEmpty else { return nil }
                    return (index, result, lines)
                }
            }
            var pages: [(Int, Result, [String])] = []
            for await page in group {
                if let page { pages.append(page) }
            }
            return pages.sorted { $0.0 < $1.0 }
        }

        let text = digestText(query: query, results: shown, pages: pages.map { ($0.1, $0.2) }, terms: terms)
        var sources = pages.map { AssistantWebSource(url: $0.1.url, title: $0.1.title) }
        for result in shown where sources.count < 3 && !sources.contains(where: { $0.url == result.url }) {
            sources.append(AssistantWebSource(url: result.url, title: result.title))
        }
        return Lookup(text: text, sources: sources, backend: .search)
    }

    /// Pure, for tests: the text the model gets, within `AssistantContent.toolOutputLimit`. What the pages say
    /// comes first (it's where the facts are), then the other results as one line each.
    static func digestText(query: String, results: [Result], pages: [(Result, [String])], terms: [String]) -> String {
        guard !results.isEmpty else {
            return "The web search found nothing for \"\(clip(query, to: 120))\"."
        }
        let limit = AssistantContent.toolOutputLimit
        var list = "Search results:\n"
        for (index, result) in results.prefix(4).enumerated() {
            var line = "\(index + 1). \(clip(result.title, to: 80)) (\(domain(of: result.url))"
            if let date = result.date { line += ", \(date)" }
            line += ")"
            if !result.snippet.isEmpty { line += ": " + clip(result.snippet, to: 170) }
            list += line + "\n"
        }
        var text = ""
        let pageBudget = limit - list.count - 20
        if !pages.isEmpty, pageBudget > 200 {
            let each = pageBudget / pages.count
            for (result, lines) in pages {
                let excerpt = AssistantHTML.excerpt(lines: lines, terms: terms, limit: each - 40)
                guard !excerpt.isEmpty else { continue }
                text += "From \(domain(of: result.url)):\n" + excerpt + "\n\n"
            }
        }
        text += list
        return AssistantContent.truncate(text.trimmingCharacters(in: .whitespacesAndNewlines), to: limit)
    }

    /// Cut on a word with "…": for titles and snippets, where the truncation marker would be noise.
    static func clip(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        var head = String(text.prefix(limit - 1))
        if let space = head.lastIndex(of: " "), head.distance(from: space, to: head.endIndex) < 30 {
            head = String(head[..<space])
        }
        return head.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.-")) + "…"
    }

    static func domain(of url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// A search for the question in the default browser, for "Open in browser".
    static func browserSearchURL(_ question: String) -> URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: question)]
        return components?.url
    }
}

// MARK: - HTML to text

/// Just enough HTML handling to read a page: scripts, styles, menus, headers and footers are dropped, block
/// elements become lines, entities are decoded. No WebKit, no DOM, fast enough for a few megabytes.
enum AssistantHTML {
    /// Elements whose content is never what the user asked about.
    static let skipped: Set<String> = [
        "script", "style", "noscript", "svg", "template", "head", "nav", "footer", "header", "aside", "form",
        "iframe", "select", "button", "canvas", "math", "dialog", "object", "menu",
    ]
    /// Elements that start a new line.
    static let blocks: Set<String> = [
        "p", "div", "br", "li", "ul", "ol", "tr", "table", "tbody", "thead", "h1", "h2", "h3", "h4", "h5", "h6",
        "section", "article", "main", "blockquote", "pre", "hr", "dd", "dt", "dl", "figcaption", "caption",
        "title", "body", "time", "address", "summary", "details",
    ]
    /// Inline elements that sit inside words ("<b>re</b>sultados"); anything else is a space.
    static let glued: Set<String> = ["b", "i", "em", "strong", "u", "small", "sup", "sub", "mark", "abbr", "wbr"]

    /// A page's readable lines: its `<main>` (or `<article>`) when that holds enough text, otherwise the whole page.
    static func readableLines(_ html: String) -> [String] {
        for element in ["main", "article"] {
            if let inner = innerHTML(of: element, in: html) {
                let lines = cleanLines(text(fromHTML: inner))
                if lines.reduce(0, { $0 + $1.count }) >= 400 { return lines }
            }
        }
        return cleanLines(text(fromHTML: html))
    }

    /// From the first `<element` to the last `</element>`.
    static func innerHTML(of element: String, in html: String) -> String? {
        guard let open = html.range(of: "<\(element)", options: .caseInsensitive),
              let tagEnd = html[open.upperBound...].firstIndex(of: ">"),
              let close = html.range(of: "</\(element)>", options: [.caseInsensitive, .backwards]),
              tagEnd < close.lowerBound
        else { return nil }
        return String(html[html.index(after: tagEnd)..<close.lowerBound])
    }

    /// Tags stripped (skipped elements with everything inside them), blocks as line breaks, entities decoded.
    static func text(fromHTML html: String) -> String {
        let bytes = Array(html.utf8)
        let count = bytes.count
        var out: [UInt8] = []
        out.reserveCapacity(count / 3)
        var index = 0

        func lower(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
        func isNameByte(_ byte: UInt8) -> Bool {
            (97...122).contains(byte) || (65...90).contains(byte) || (48...57).contains(byte) || byte == 45
        }
        /// Where `needle` (lowercase ASCII) next appears from `start`, ignoring case.
        func find(_ needle: [UInt8], from start: Int) -> Int? {
            guard !needle.isEmpty, start < count else { return nil }
            var position = start
            while position + needle.count <= count {
                if lower(bytes[position]) == needle[0] {
                    var matched = true
                    for offset in 1..<needle.count where lower(bytes[position + offset]) != needle[offset] {
                        matched = false
                        break
                    }
                    if matched { return position }
                }
                position += 1
            }
            return nil
        }
        /// The `>` that closes the tag opened at `start`, respecting quoted attributes.
        func tagEnd(from start: Int) -> Int {
            var position = start
            var quote: UInt8?
            while position < count {
                let byte = bytes[position]
                if let open = quote {
                    if byte == open { quote = nil }
                } else if byte == 34 || byte == 39 {
                    quote = byte
                } else if byte == 62 {
                    return position
                }
                position += 1
            }
            return count - 1
        }

        while index < count {
            let byte = bytes[index]
            guard byte == 60, index + 1 < count else { // "<"
                out.append(byte)
                index += 1
                continue
            }
            let next = bytes[index + 1]
            if next == 33 { // "<!": comment, doctype, CDATA
                if index + 3 < count, bytes[index + 2] == 45, bytes[index + 3] == 45 {
                    index = (find(Array("-->".utf8), from: index + 4).map { $0 + 3 }) ?? count
                } else {
                    index = tagEnd(from: index) + 1
                }
                continue
            }
            if next == 63 { // "<?"
                index = tagEnd(from: index) + 1
                continue
            }
            let isClosing = next == 47
            var nameStart = index + (isClosing ? 2 : 1)
            guard nameStart < count, isNameByte(bytes[nameStart]) else {
                // A lone "<" in text.
                out.append(byte)
                index += 1
                continue
            }
            var name: [UInt8] = []
            while nameStart < count, isNameByte(bytes[nameStart]) {
                name.append(lower(bytes[nameStart]))
                nameStart += 1
            }
            let end = tagEnd(from: nameStart)
            let tag = String(decoding: name, as: UTF8.self)
            let selfClosing = end > 0 && bytes[end - 1] == 47
            index = end + 1

            if !isClosing, !selfClosing, skipped.contains(tag) {
                // Skip to the matching close; an unclosed one only loses its own tag.
                if let close = find(Array("</\(tag)".utf8), from: index) {
                    index = tagEnd(from: close) + 1
                }
                out.append(10)
                continue
            }
            if blocks.contains(tag) {
                out.append(10)
            } else if tag == "td" || tag == "th" {
                out.append(32)
            } else if !glued.contains(tag) {
                out.append(32)
            }
        }
        return decodeEntities(String(decoding: out, as: UTF8.self))
    }

    /// Lines with their spaces collapsed, empty ones dropped.
    static func cleanLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }

    /// Inline HTML (a title, a snippet) as one plain line.
    static func inlineText(_ html: String) -> String {
        cleanLines(text(fromHTML: html)).joined(separator: " ")
    }

    static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
        "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "middot": "·", "bull": "•", "euro": "€", "pound": "£", "copy": "©", "reg": "®", "deg": "°", "times": "×",
        "iexcl": "¡", "iquest": "¿", "ordm": "º", "ordf": "ª", "aacute": "á", "eacute": "é", "iacute": "í",
        "oacute": "ó", "uacute": "ú", "Aacute": "Á", "Eacute": "É", "Iacute": "Í", "Oacute": "Ó", "Uacute": "Ú",
        "agrave": "à", "egrave": "è", "ograve": "ò", "Agrave": "À", "Egrave": "È", "Ograve": "Ò", "ntilde": "ñ",
        "Ntilde": "Ñ", "ccedil": "ç", "Ccedil": "Ç", "uuml": "ü", "Uuml": "Ü", "ouml": "ö", "Ouml": "Ö",
        "auml": "ä", "Auml": "Ä", "iuml": "ï", "euml": "ë", "szlig": "ß", "acirc": "â", "ecirc": "ê", "ocirc": "ô",
        "rarr": "→", "larr": "←", "uarr": "↑", "darr": "↓", "trade": "™", "ensp": " ", "emsp": " ", "thinsp": " ",
        "shy": "", "zwj": "", "zwnj": "", "lrm": "", "rlm": "",
    ]

    /// `&amp;`, `&#241;`, `&#xF1;` and the common named entities.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&",
                  let semicolon = text[index...].prefix(12).firstIndex(of: ";")
            else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let entity = text[text.index(after: index)..<semicolon]
            var replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if entity.hasPrefix("#") {
                replacement = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[String(entity)]
            }
            if let replacement {
                result += replacement
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: Picking what matters

    /// Words that say nothing about what a page is about.
    static let stopwords: Set<String> = [
        "the", "a", "an", "of", "in", "on", "at", "for", "to", "and", "or", "is", "are", "was", "were", "be", "did",
        "does", "do", "what", "who", "when", "where", "which", "how", "why", "whats", "today", "now", "latest",
        "last", "current", "new", "vs", "el", "la", "los", "las", "un", "una", "de", "del", "en", "y", "o", "que",
        "quien", "cuando", "donde", "como", "cual", "hoy", "ahora", "ultimo", "ultima", "al", "por", "para", "con",
        "se", "es", "fue", "ha", "les", "des", "le", "du", "et", "avui", "ara", "darrer", "amb", "per", "der", "die",
        "das", "und", "im", "am", "il", "di", "da", "e", "com",
    ]

    /// The query's meaningful words, folded (lowercase, no accents), for matching against page text.
    static func terms(in query: String) -> [String] {
        var seen = Set<String>()
        return fold(query)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { ($0.count > 2 || $0.allSatisfy(\.isNumber)) && !stopwords.contains($0) }
            .filter { seen.insert($0).inserted }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The parts of a page that best match the query, in page order, within `limit` characters. Short lines are
    /// merged first (a score split over five `<div>`s reads "Sevilla 1 - 3 FC Barcelona" again).
    static func excerpt(lines: [String], terms: [String], limit: Int) -> String {
        guard limit > 80 else { return "" }
        var paragraphs: [String] = []
        var current = ""
        for line in lines {
            if line.count >= 120 {
                if !current.isEmpty { paragraphs.append(current); current = "" }
                paragraphs.append(String(line.prefix(600)))
            } else if current.count + line.count > 280 {
                paragraphs.append(current)
                current = line
            } else {
                current += current.isEmpty ? line : " " + line
            }
        }
        if !current.isEmpty { paragraphs.append(current) }

        // Stems, so "resultados" finds "resultado" and "barcelona" finds "Barcelona's".
        let stems = terms.map { $0.count > 6 ? String($0.prefix(6)) : $0 }
        let scored = paragraphs.enumerated().map { index, paragraph -> (index: Int, score: Int) in
            let folded = fold(paragraph)
            let hits = stems.filter { folded.contains($0) }.count
            guard hits > 0 else { return (index, 0) }
            let numbers = min(3, paragraph.split { !$0.isNumber }.count)
            let prose = paragraph.count > 100 ? 1 : 0
            return (index, hits * 4 + numbers + prose)
        }

        var chosen = Set<Int>()
        var used = 0
        for candidate in scored.filter({ $0.score > 0 }).sorted(by: { $0.score > $1.score || ($0.score == $1.score && $0.index < $1.index) }) {
            let length = paragraphs[candidate.index].count + 1
            guard used + length <= limit else { continue }
            chosen.insert(candidate.index)
            used += length
        }
        if chosen.isEmpty {
            // Nothing matches the words: the start of the page's prose is the best guess.
            for (index, paragraph) in paragraphs.enumerated() where paragraph.count >= 60 {
                guard used + paragraph.count + 1 <= limit else { break }
                chosen.insert(index)
                used += paragraph.count + 1
            }
        }
        let picked = chosen.sorted().map { paragraphs[$0] }.joined(separator: "\n")
        return AssistantContent.truncate(picked, to: limit)
    }
}

// MARK: - Weather

/// The weather from Open-Meteo (no key, no account): the place is looked up by name, then today and the next two
/// days. Weather sites don't show numbers to a plain request, so a search alone can't answer "what's the weather".
enum AssistantWeather {
    static let words: Set<String> = [
        "weather", "forecast", "temperature", "temperatures", "rain", "raining", "sunny", "tiempo", "clima",
        "pronostico", "temperatura", "llovera", "llueve", "lluvia", "temps", "meteo", "previsio", "prevision",
        "pluja", "ploura", "wetter", "tempo", "previsioni", "temperatur",
    ]
    /// Words around a place in a weather question that aren't the place.
    static let filler: Set<String> = [
        "today", "tonight", "tomorrow", "now", "this", "week", "weekend", "right", "will", "it", "be", "like",
        "going", "to", "the", "in", "at", "for", "what", "whats", "is", "how", "hows", "current", "currently",
        "hoy", "manana", "ahora", "esta", "semana", "fin", "de", "en", "el", "la", "que", "hace", "hara", "va",
        "a", "para", "del", "avui", "dema", "ara", "fa", "fara", "al", "aujourd", "hui", "demain", "heute",
        "morgen", "oggi", "domani", "y", "and", "report", "actual", "sera", "weekly", "daily", "hourly",
        "degrees", "grados", "graus", "celsius", "fahrenheit", "quin", "quina", "com", "como", "cual", "quel",
        "quelle", "wie", "come", "qual", "fera", "expected",
    ]

    /// The place named in a weather search ("weather Barcelona today" → "Barcelona"), "" when it's about the
    /// weather but names no place, nil when it isn't about the weather at all.
    static func place(in query: String) -> String? {
        let tokens = query.split { !$0.isLetter && !$0.isNumber && $0 != "-" }
            .map(String.init)
            .filter { $0.count > 1 || $0.first?.isNumber == true }
        let folded = tokens.map(AssistantHTML.fold)
        guard folded.contains(where: words.contains) else { return nil }
        // "¿Cuánto tiempo…?" is about time, not weather.
        if folded.contains(where: { ["cuanto", "quant", "how", "long", "much"].contains($0) }),
           !folded.contains("weather") { return nil }
        let kept = zip(tokens, folded)
            .filter { !words.contains($0.1) && !filler.contains($0.1) }
            .map(\.0)
        return kept.joined(separator: " ")
    }

    struct GeocodingResponse: Decodable {
        struct Place: Decodable {
            var name: String
            var latitude: Double
            var longitude: Double
            var country: String?
            var admin1: String?
        }
        var results: [Place]?
    }

    struct ForecastResponse: Decodable {
        struct Current: Decodable {
            var time: String
            var temperature_2m: Double
            var apparent_temperature: Double?
            var relative_humidity_2m: Double?
            var weather_code: Int
            var wind_speed_10m: Double?
            var precipitation: Double?
        }
        struct Daily: Decodable {
            var time: [String]
            var weather_code: [Int]
            var temperature_2m_max: [Double]
            var temperature_2m_min: [Double]
            var precipitation_probability_max: [Int?]?
        }
        var timezone: String?
        var current: Current
        var daily: Daily
    }

    /// Fahrenheit and mph where the Mac is set to US units.
    static var usesImperial: Bool { Locale.current.measurementSystem == .us }

    static func lookUp(place rawPlace: String) async throws -> AssistantWeb.Lookup {
        var name = rawPlace
        var guessed = false
        if name.isEmpty {
            // No place: the city of the Mac's time zone ("Europe/Madrid" → "Madrid"), and the model is told so.
            name = TimeZone.current.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? ""
            guessed = true
        }
        guard !name.isEmpty else { throw AssistantWeb.Failure.empty }
        let language = AssistantInstructions.language(of: rawPlace) ?? Locale.current.language.languageCode?.identifier ?? "en"

        // The full name first, then its last and first words ("Weather Girona" → "Girona", "Barcelona Spain" →
        // "Barcelona").
        var candidates = [name]
        let parts = name.split(separator: " ").map(String.init)
        for part in [parts.last, parts.first].compactMap({ $0 }) where !candidates.contains(part) {
            candidates.append(part)
        }
        var found: GeocodingResponse.Place?
        for candidate in candidates {
            var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
            components?.queryItems = [
                URLQueryItem(name: "name", value: candidate), URLQueryItem(name: "count", value: "1"),
                URLQueryItem(name: "language", value: language), URLQueryItem(name: "format", value: "json"),
            ]
            guard let url = components?.url else { continue }
            let (data, _) = try await AssistantWeb.session.data(from: url)
            if let place = try JSONDecoder().decode(GeocodingResponse.self, from: data).results?.first {
                found = place
                break
            }
        }
        guard let place = found else { throw AssistantWeb.Failure.empty }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        var items = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,precipitation"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "3"),
        ]
        if usesImperial {
            items += [URLQueryItem(name: "temperature_unit", value: "fahrenheit"), URLQueryItem(name: "wind_speed_unit", value: "mph")]
        }
        components?.queryItems = items
        guard let url = components?.url else { throw AssistantWeb.Failure.badResponse }
        let (data, response) = try await AssistantWeb.session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AssistantWeb.Failure.badResponse }
        let forecast = try JSONDecoder().decode(ForecastResponse.self, from: data)

        let label = [place.name, place.admin1, place.country].compactMap { $0 }.reduce(into: [String]()) { labels, part in
            if !labels.contains(part) { labels.append(part) }
        }.joined(separator: ", ")
        let text = report(forecast, place: label, guessed: guessed, imperial: usesImperial)
        let source = AssistantWebSource(
            url: URL(string: "https://open-meteo.com/")!,
            title: "Open-Meteo"
        )
        return AssistantWeb.Lookup(text: text, sources: [source], backend: .weather)
    }

    /// Pure, for tests.
    static func report(_ forecast: ForecastResponse, place: String, guessed: Bool, imperial: Bool) -> String {
        let degrees = imperial ? "°F" : "°C"
        let speed = imperial ? "mph" : "km/h"
        let current = forecast.current
        let time = current.time.split(separator: "T").last.map(String.init) ?? current.time
        var text = "Weather for \(place) (Open-Meteo, live):\n"
        if guessed {
            text = "No place was given, so this is for \(place), from the Mac's time zone. Say so.\n" + text
        }
        var now = "Now (\(time) local): \(Int(current.temperature_2m.rounded()))\(degrees), \(description(current.weather_code))"
        if let feels = current.apparent_temperature { now += ", feels like \(Int(feels.rounded()))\(degrees)" }
        if let humidity = current.relative_humidity_2m { now += ", humidity \(Int(humidity))%" }
        if let wind = current.wind_speed_10m { now += ", wind \(Int(wind.rounded())) \(speed)" }
        text += now + ".\n"
        let names = ["Today", "Tomorrow", "Day after tomorrow"]
        let daily = forecast.daily
        for index in daily.time.indices.prefix(3) {
            guard index < daily.weather_code.count, index < daily.temperature_2m_max.count,
                  index < daily.temperature_2m_min.count else { break }
            var line = "\(names[index]) (\(daily.time[index])): \(description(daily.weather_code[index])), "
            line += "\(Int(daily.temperature_2m_min[index].rounded()))–\(Int(daily.temperature_2m_max[index].rounded()))\(degrees)"
            if let chances = daily.precipitation_probability_max, index < chances.count, let chance = chances[index] {
                line += ", \(chance)% chance of rain"
            }
            text += line + ".\n"
        }
        return text
    }

    /// WMO weather codes in words.
    static func description(_ code: Int) -> String {
        switch code {
        case 0: "clear sky"
        case 1: "mainly clear"
        case 2: "partly cloudy"
        case 3: "overcast"
        case 45, 48: "fog"
        case 51, 53, 55: "drizzle"
        case 56, 57: "freezing drizzle"
        case 61: "light rain"
        case 63: "rain"
        case 65: "heavy rain"
        case 66, 67: "freezing rain"
        case 71: "light snow"
        case 73: "snow"
        case 75: "heavy snow"
        case 77: "snow grains"
        case 80, 81: "rain showers"
        case 82: "violent rain showers"
        case 85, 86: "snow showers"
        case 95: "thunderstorm"
        case 96, 99: "thunderstorm with hail"
        default: "mixed weather"
        }
    }
}

// MARK: - Wikipedia

/// When DuckDuckGo can't be reached: Wikipedia's search and page summary, in the query's language. Not live, and
/// the model is told so.
enum AssistantWikipedia {
    struct SearchResponse: Decodable {
        struct Page: Decodable {
            var key: String
            var title: String
            var description: String?
        }
        var pages: [Page]
    }

    struct Summary: Decodable {
        var title: String
        var extract: String
    }

    static func lookUp(_ query: String) async throws -> AssistantWeb.Lookup {
        let language = AssistantInstructions.language(of: query) ?? Locale.current.language.languageCode?.identifier ?? "en"
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/rest.php/v1/search/page")
        components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "1")]
        guard let url = components?.url else { throw AssistantWeb.Failure.badResponse }
        let (data, _) = try await AssistantWeb.session.data(from: url)
        guard let page = try JSONDecoder().decode(SearchResponse.self, from: data).pages.first,
              let key = page.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let summaryURL = URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/summary/\(key)")
        else { throw AssistantWeb.Failure.empty }
        let (summaryData, _) = try await AssistantWeb.session.data(from: summaryURL)
        let summary = try JSONDecoder().decode(Summary.self, from: summaryData)
        let text = """
        The web search didn't work, so this is Wikipedia's article "\(summary.title)" (may not be up to date):
        \(AssistantContent.truncate(summary.extract, to: 1_800))
        Answer from it if it helps; say it may not be the latest.
        """
        let pageURL = URL(string: "https://\(language).wikipedia.org/wiki/\(key)") ?? summaryURL
        return AssistantWeb.Lookup(
            text: text,
            sources: [AssistantWebSource(url: pageURL, title: summary.title)],
            backend: .wikipedia
        )
    }
}
