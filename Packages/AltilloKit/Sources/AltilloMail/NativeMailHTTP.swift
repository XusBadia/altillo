import Foundation

private final class NativeMailRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// A fresh, non-persistent session: mail and bearer tokens never enter the shared HTTP cache or cookie jar.
public struct URLSessionNativeMailTransport: NativeMailTransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration, delegate: NativeMailRedirectBlocker(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest, byteLimit: Int) async throws -> NativeMailHTTPResponse {
        guard byteLimit > 0, byteLimit <= 4_194_304 else { throw NativeMailFailure.contentTooLarge }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw NativeMailFailure.invalidResponse }
            guard response.expectedContentLength <= byteLimit else { throw NativeMailFailure.contentTooLarge }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < byteLimit else { throw NativeMailFailure.contentTooLarge }
                data.append(byte)
            }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { values, entry in
                guard let key = entry.key as? String else { return }
                values[key.lowercased()] = String(describing: entry.value)
            }
            return .init(status: http.statusCode, headers: headers, data: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as NativeMailFailure { throw error }
        catch { throw NativeMailFailure.unavailable }
    }
}

struct NativeMailAPI: Sendable {
    let token: NativeMailTokenLoader
    let transport: any NativeMailTransport
    let allowedHosts: Set<String>

    func get(_ url: URL, byteLimit: Int = 2_097_152, headers: [String: String] = [:], notFound: NativeMailFailure = .messageMissing) async throws -> Data {
        guard Self.isSafe(url, hosts: allowedHosts) else { throw NativeMailFailure.invalidResponse }
        for force in [false, true] {
            try Task.checkCancellation()
            let accessToken: String
            do { accessToken = try await token(force) }
            catch is CancellationError { throw CancellationError() }
            catch let error as NativeMailFailure { throw error }
            catch { throw NativeMailFailure.unauthorized }
            guard !accessToken.isEmpty, !accessToken.contains("\r"), !accessToken.contains("\n") else { throw NativeMailFailure.unauthorized }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.httpMethod = "GET"
            request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let response: NativeMailHTTPResponse
            do { response = try await transport.send(request, byteLimit: byteLimit) }
            catch is CancellationError { throw CancellationError() }
            catch let error as NativeMailFailure { throw error }
            catch { throw NativeMailFailure.unavailable }
            guard response.data.count <= byteLimit else { throw NativeMailFailure.contentTooLarge }
            switch response.status {
            case 200...299: return response.data
            case 401 where !force: continue
            case 401: throw NativeMailFailure.unauthorized
            case 403: throw NativeMailFailure.forbidden
            case 404: throw notFound
            case 429:
                let retry = response.headers.first { $0.key.lowercased() == "retry-after" }?.value
                throw NativeMailFailure.rateLimited(Self.retryDelay(retry))
            case 500...599: throw NativeMailFailure.unavailable
            default: throw NativeMailFailure.invalidResponse
            }
        }
        throw NativeMailFailure.unauthorized
    }

    static func isSafe(_ url: URL, hosts: Set<String>) -> Bool {
        url.scheme?.lowercased() == "https" && url.host.map { hosts.contains($0.lowercased()) } == true &&
            url.user == nil && url.password == nil && (url.port == nil || url.port == 443) && url.fragment == nil
    }

    static func retryDelay(_ value: String?, now: Date = .now) -> TimeInterval {
        if let value, let seconds = Double(value), seconds.isFinite { return min(86_400, max(1, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        if let value, let date = formatter.date(from: value) { return min(86_400, max(1, date.timeIntervalSince(now))) }
        return 60
    }
}

func nativeMailURL(_ base: String, query: [URLQueryItem] = []) throws -> URL {
    guard var components = URLComponents(string: base) else { throw NativeMailFailure.invalidResponse }
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { throw NativeMailFailure.invalidResponse }
    return url
}

func nativeMailPathComponent(_ value: String) throws -> String {
    guard !value.isEmpty, value.utf8.count <= 4_096, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
          let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) else { throw NativeMailFailure.invalidResponse }
    return encoded
}

func nativeMailDecode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    guard let value = try? JSONDecoder().decode(type, from: data) else { throw NativeMailFailure.invalidResponse }
    return value
}
