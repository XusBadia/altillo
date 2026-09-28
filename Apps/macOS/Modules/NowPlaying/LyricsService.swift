import Foundation
import Observation

struct LyricsQuery: Hashable, Sendable {
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval?

    init(track: NowPlayingStore.Track) {
        title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        duration = track.duration
    }
}

struct SyncedLyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
}

struct LyricsDocument: Equatable, Sendable {
    var synced: [SyncedLyricLine]
    var plain: [String]

    var isEmpty: Bool { synced.isEmpty && plain.isEmpty }

    static func parse(synced rawSynced: String?, plain rawPlain: String?) -> LyricsDocument {
        var timed: [(time: TimeInterval, text: String)] = []
        for rawLine in rawSynced?.split(whereSeparator: \.isNewline) ?? [] {
            let line = String(rawLine)
            let timestamps = timestamps(in: line)
            guard !timestamps.isEmpty else { continue }
            let text = line.replacingOccurrences(of: #"\[[0-9]{1,3}:[0-9]{2}(?:[.:][0-9]{1,3})?\]"#,
                                                 with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            timed.append(contentsOf: timestamps.map { ($0, text) })
        }
        timed.sort { $0.time < $1.time }
        let synced = timed.enumerated().map { index, line in
            SyncedLyricLine(id: index, time: line.time, text: line.text)
        }
        let plain = (rawPlain ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return LyricsDocument(synced: synced, plain: plain)
    }

    private static func timestamps(in line: String) -> [TimeInterval] {
        let expression = try? NSRegularExpression(pattern: #"\[([0-9]{1,3}):([0-9]{2})(?:[.:]([0-9]{1,3}))?\]"#)
        let range = NSRange(line.startIndex..., in: line)
        return expression?.matches(in: line, range: range).compactMap { match in
            guard let minutesRange = Range(match.range(at: 1), in: line),
                  let secondsRange = Range(match.range(at: 2), in: line),
                  let minutes = Double(line[minutesRange]), let seconds = Double(line[secondsRange]) else { return nil }
            var fraction = 0.0
            if match.range(at: 3).location != NSNotFound, let fractionRange = Range(match.range(at: 3), in: line) {
                let digits = line[fractionRange]
                fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
            }
            return minutes * 60 + seconds + fraction
        } ?? []
    }
}

struct LyricsService: Sendable {
    enum Failure: Error { case badResponse, notFound }

    private struct Response: Decodable {
        var syncedLyrics: String?
        var plainLyrics: String?
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.httpAdditionalHeaders = ["User-Agent": "Altillo/1.0 (+https://altillo.app/)"]
        return URLSession(configuration: configuration)
    }()

    func fetch(_ query: LyricsQuery) async throws -> LyricsDocument {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        if let album = query.album, !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration = query.duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw Failure.badResponse }
        let (data, response) = try await Self.session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw Failure.notFound }
        guard status == 200, let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw Failure.badResponse
        }
        let document = LyricsDocument.parse(synced: decoded.syncedLyrics, plain: decoded.plainLyrics)
        guard !document.isEmpty else { throw Failure.notFound }
        return document
    }
}

@MainActor
@Observable
final class LyricsStore {
    enum Phase: Equatable {
        case idle, loading, loaded(LyricsDocument), unavailable, failed
    }

    private(set) var phase: Phase = .idle
    private(set) var query: LyricsQuery?
    @ObservationIgnored private var cache: [LyricsQuery: LyricsDocument] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let loader: @Sendable (LyricsQuery) async throws -> LyricsDocument

    init(loader: @escaping @Sendable (LyricsQuery) async throws -> LyricsDocument = { query in
        try await LyricsService().fetch(query)
    }) {
        self.loader = loader
    }

    func reset(for track: NowPlayingStore.Track) {
        let next = LyricsQuery(track: track)
        guard next != query else { return }
        task?.cancel()
        query = next
        phase = cache[next].map(Phase.loaded) ?? .idle
    }

    func load(for track: NowPlayingStore.Track) {
        let next = LyricsQuery(track: track)
        task?.cancel()
        query = next
        if let cached = cache[next] {
            phase = .loaded(cached)
            return
        }
        phase = .loading
        task = Task { [weak self, loader] in
            do {
                let document = try await loader(next)
                try Task.checkCancellation()
                self?.cache[next] = document
                self?.phase = .loaded(document)
            } catch is CancellationError {
                return
            } catch LyricsService.Failure.notFound {
                self?.phase = .unavailable
            } catch {
                self?.phase = .failed
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
