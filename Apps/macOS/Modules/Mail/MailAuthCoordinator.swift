import AppKit
import Foundation
import Observation
import AltilloMail
@preconcurrency import AppAuth
@preconcurrency import AppAuthCore
@preconcurrency import MSAL

struct MailOAuthCredential: Sendable {
    let token: String
    let googleState: Data?
    let microsoftAccountID: String?
}

@MainActor protocol MailAuthenticationDriver: AnyObject {
    func authorize(service: NativeMailService) async throws -> MailOAuthCredential
    func refresh(record: MailCredentialRecord, force: Bool) async throws -> MailOAuthCredential
    func remove(record: MailCredentialRecord) throws
    func discard(_ credential: MailOAuthCredential, preserving: [MailCredentialRecord]) throws
    func cancel()
}

@MainActor @Observable final class MailAuthCoordinator {
    private let vault: MailCredentialStore
    private let configuration: MailNativeConfiguration
    private let driver: any MailAuthenticationDriver
    private let resolveIdentity: @MainActor (NativeMailService, String) async throws -> NativeMailIdentity
    private let validateServer: @Sendable (NativeMailServerCredentials) async throws -> Void
    private var operation: UUID?
    private var cancelledOperations: Set<UUID> = []
    private var serverValidation: Task<Void, Error>?
    private var generations: [UUID: UUID] = [:]
    private struct Flight {
        let id: UUID
        let forced: Bool
        let task: Task<String, Error>
    }
    private var flights: [UUID: Flight] = [:]

    init(vault: MailCredentialStore = MailCredentialStore(),
         configuration: MailNativeConfiguration = MailNativeConfiguration(),
         driver: (any MailAuthenticationDriver)? = nil,
         validateServer: @escaping @Sendable (NativeMailServerCredentials) async throws -> Void = {
             try await IMAPNativeMailProvider.validate(credentials: $0)
         },
         resolveIdentity: @escaping @MainActor (NativeMailService, String) async throws -> NativeMailIdentity = {
             try await NativeMailIdentityResolver.resolve(service: $0, token: $1)
         }) {
        self.vault = vault
        self.configuration = configuration
        self.driver = driver ?? SDKMailAuthenticationDriver(configuration: configuration)
        self.resolveIdentity = resolveIdentity
        self.validateServer = validateServer
    }

    var availableServices: [NativeMailService] { configuration.availableServices }

    func restoreAccounts() throws -> [NativeMailAccount] { try vault.records().map(\.account) }

    func connect(service: NativeMailService, replacing: NativeMailAccount? = nil) async throws -> NativeMailAccount {
        guard service == .google || service == .microsoft else { throw MailAuthFailure.notConfigured }
        guard availableServices.contains(service) else { throw MailAuthFailure.notConfigured }
        guard operation == nil else { throw MailAuthFailure.operationInProgress }
        if let replacing, replacing.service != service { throw MailAuthFailure.accountMismatch }
        let id = UUID()
        operation = id
        defer { if operation == id { operation = nil }; cancelledOperations.remove(id) }
        return try await withTaskCancellationHandler {
            var pending: MailOAuthCredential?
            do {
                try Task.checkCancellation()
                let credential = try await driver.authorize(service: service)
                pending = credential
                guard operation == id, !cancelledOperations.contains(id) else { throw MailAuthFailure.cancelled }
                let identity = try await resolveIdentity(service, credential.token)
                try Task.checkCancellation()
                guard operation == id, !cancelledOperations.contains(id) else { throw MailAuthFailure.cancelled }
                let records = try vault.records()
                if let replacing {
                    guard records.contains(where: { $0.account == replacing }),
                          replacing.remoteID == identity.remoteID else { throw MailAuthFailure.accountMismatch }
                }
                let existing = records.first { $0.account.service == service && $0.account.remoteID == identity.remoteID }
                let account = NativeMailAccount(id: replacing?.id ?? existing?.account.id ?? UUID(), service: service,
                                                remoteID: identity.remoteID, address: identity.address,
                                                displayName: identity.displayName)
                try vault.save(MailCredentialRecord(account: account, googleState: credential.googleState,
                                                    microsoftAccountID: credential.microsoftAccountID,
                                                    authorizationVersion: MailNativeConfiguration.authorizationVersion))
                generations[account.id] = UUID()
                flights.removeValue(forKey: account.id)?.task.cancel()
                return account
            } catch {
                if let pending {
                    // MSAL already cached a successful login. Remove only an unreferenced new SDK identity.
                    try? driver.discard(pending, preserving: vault.records())
                }
                if cancelledOperations.contains(id) || Task.isCancelled { throw MailAuthFailure.cancelled }
                throw Self.failure(error)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.operation == id else { return }
                self?.cancel()
            }
        }
    }

    func accessToken(for account: NativeMailAccount, forceRefresh: Bool = false) async throws -> String {
        guard account.service == .google || account.service == .microsoft else { throw MailAuthFailure.notConfigured }
        if let flight = flights[account.id] {
            let result = try await flight.task.value
            if !forceRefresh || flight.forced { return result }
            if flights[account.id]?.id == flight.id { flights.removeValue(forKey: account.id) }
            return try await accessToken(for: account, forceRefresh: true)
        }
        guard let record = try vault.record(for: account.id), record.account == account else {
            throw MailAuthFailure.reconnectRequired
        }
        guard record.authorizationVersion == MailNativeConfiguration.authorizationVersion else {
            throw MailAuthFailure.reconnectRequired
        }
        let generation = generations[account.id] ?? UUID()
        generations[account.id] = generation
        let task = Task { @MainActor [self] in
            do {
                let credential = try await driver.refresh(record: record, force: forceRefresh)
                try Task.checkCancellation()
                guard generations[account.id] == generation,
                      try vault.record(for: account.id)?.account == account else { throw MailAuthFailure.cancelled }
                if account.service == .google {
                    try vault.save(MailCredentialRecord(account: account, googleState: credential.googleState,
                                                        microsoftAccountID: nil,
                                                        authorizationVersion: record.authorizationVersion))
                }
                return credential.token
            } catch {
                if Task.isCancelled { throw MailAuthFailure.cancelled }
                throw Self.failure(error)
            }
        }
        let id = UUID()
        flights[account.id] = Flight(id: id, forced: forceRefresh, task: task)
        defer { if flights[account.id]?.id == id { flights.removeValue(forKey: account.id) } }
        return try await task.value
    }

    func disconnect(account: NativeMailAccount) async throws {
        guard let record = try vault.record(for: account.id), record.account == account else { return }
        generations[account.id] = UUID()
        flights.removeValue(forKey: account.id)?.task.cancel()
        do {
            if account.service == .google || account.service == .microsoft { try driver.remove(record: record) }
        }
        catch { throw Self.failure(error) }
        try vault.remove(account.id)
    }

    func connectServer(configuration input: NativeMailServerConfiguration, password: String,
                       service: NativeMailService, replacing: NativeMailAccount? = nil) async throws -> NativeMailAccount {
        guard service == .icloud || service == .imap else { throw MailAuthFailure.notConfigured }
        guard operation == nil else { throw MailAuthFailure.operationInProgress }
        if let replacing, replacing.service != service { throw MailAuthFailure.accountMismatch }
        let configuration = try Self.validatedServerConfiguration(input, service: service, password: password)
        let credentials = NativeMailServerCredentials(configuration: configuration, password: password)
        let id = UUID()
        operation = id
        defer { if operation == id { operation = nil; serverValidation = nil }; cancelledOperations.remove(id) }
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let validation = Task { [validateServer] in try await validateServer(credentials) }
                serverValidation = validation
                try await validation.value
                try Task.checkCancellation()
                guard operation == id, !cancelledOperations.contains(id) else { throw MailAuthFailure.cancelled }
                let remoteID = "imap:\(configuration.imapHost):\(configuration.imapPort):\(configuration.username)"
                let records = try vault.records()
                if let replacing {
                    guard records.contains(where: { $0.account == replacing }), replacing.remoteID == remoteID else {
                        throw MailAuthFailure.accountMismatch
                    }
                }
                let existing = records.first { $0.account.service == service && $0.account.remoteID == remoteID }
                let account = NativeMailAccount(id: replacing?.id ?? existing?.account.id ?? UUID(), service: service,
                                                remoteID: remoteID, address: configuration.address,
                                                displayName: configuration.displayName)
                try vault.save(MailCredentialRecord(account: account, googleState: nil, microsoftAccountID: nil,
                                                    serverCredentials: credentials))
                generations[account.id] = UUID()
                return account
            } catch {
                if cancelledOperations.contains(id) || Task.isCancelled { throw MailAuthFailure.cancelled }
                throw Self.failure(error)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.operation == id else { return }
                self?.cancel()
            }
        }
    }

    func serverCredentials(for account: NativeMailAccount) async throws -> NativeMailServerCredentials {
        try Task.checkCancellation()
        guard account.service == .icloud || account.service == .imap,
              let record = try vault.record(for: account.id), record.account == account,
              let credentials = record.serverCredentials else { throw MailAuthFailure.reconnectRequired }
        return credentials
    }

    private static func validatedServerConfiguration(_ input: NativeMailServerConfiguration,
                                                     service: NativeMailService, password: String) throws -> NativeMailServerConfiguration {
        var config = input
        config.address = input.address.trimmingCharacters(in: .whitespacesAndNewlines)
        config.username = input.username.trimmingCharacters(in: .whitespacesAndNewlines)
        config.imapHost = input.imapHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        config.smtpHost = input.smtpHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fields = [config.address, config.username, config.displayName, config.imapHost, config.smtpHost]
        guard fields.allSatisfy({ !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) && $0.utf8.count <= 1_024 }),
              config.address.split(separator: "@", omittingEmptySubsequences: false).count == 2,
              !config.address.hasPrefix("@"), !config.address.hasSuffix("@"),
              !config.address.contains(where: { $0.isWhitespace || "<>\"".contains($0) }),
              !config.username.isEmpty, !password.isEmpty, password.utf8.count <= 4_096,
              !password.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              (1...65_535).contains(config.imapPort), (1...65_535).contains(config.smtpPort),
              [config.imapHost, config.smtpHost].allSatisfy({ host in
                  !host.isEmpty && host.range(of: #"^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$"#, options: .regularExpression) != nil
              }) else { throw MailAuthFailure.denied }
        if service == .icloud {
            guard config.imapHost == "imap.mail.me.com", config.imapPort == 993,
                  config.smtpHost == "smtp.mail.me.com", config.smtpPort == 587,
                  config.smtpSecurity == .startTLS else { throw MailAuthFailure.denied }
        }
        return config
    }

    func cancel() {
        if let operation { cancelledOperations.insert(operation) }
        // SDK silent refresh APIs return no cancellable request handle. Invalidate their results
        // before cancelling the wrapper tasks, so late completion cannot update our vault or hand
        // a token back to a provider. MSAL may finish rotating its own private credential cache;
        // pausing intentionally retains credentials, and no mail request follows that completion.
        for accountID in flights.keys { generations[accountID] = UUID() }
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
        serverValidation?.cancel()
        driver.cancel()
    }

    static func failure(_ error: Error) -> MailAuthFailure {
        if let failure = error as? MailAuthFailure { return failure }
        if error is CancellationError { return .cancelled }
        if let failure = error as? NativeMailFailure {
            switch failure {
            case .unauthorized: return .reconnectRequired
            case .forbidden: return .denied
            default: return .unavailable
            }
        }
        let ns = error as NSError
        if ns.domain == OIDGeneralErrorDomain && ns.code == -3 { return .cancelled }
        if ns.domain == OIDOAuthAuthorizationErrorDomain { return .denied }
        if ns.domain == OIDOAuthTokenErrorDomain { return .reconnectRequired }
        if ns.domain == MSALErrorDomain {
            if ns.code == MSALError.userCanceled.rawValue { return .cancelled }
            if ns.code == MSALError.interactionRequired.rawValue { return .reconnectRequired }
            return .denied
        }
        return .unavailable
    }
}

/// SDK objects never cross the main actor; only archived Google state leaves this adapter.
@MainActor private final class SDKMailAuthenticationDriver: MailAuthenticationDriver {
    private let configuration: MailNativeConfiguration
    private var application: MSALPublicClientApplication?
    private var handler: OIDRedirectHTTPHandler?
    private var authorization: (any OIDExternalUserAgentSession)?
    private var pendingCancellation: (() -> Void)?
    private var preexistingMicrosoftIDs: Set<String> = []

    init(configuration: MailNativeConfiguration) { self.configuration = configuration }

    func authorize(service: NativeMailService) async throws -> MailOAuthCredential {
        switch service {
        case .google: return try await authorizeGoogle()
        case .microsoft: return try await authorizeMicrosoft()
        case .icloud, .imap: throw MailAuthFailure.notConfigured
        }
    }

    private func authorizeGoogle() async throws -> MailOAuthCredential {
        guard let clientID = configuration.googleClientID else { throw MailAuthFailure.notConfigured }
        let listener = OIDRedirectHTTPHandler(successURL: nil)
        var listenerError: NSError?
        let redirect = listener.startHTTPListener(&listenerError)
        guard listenerError == nil else { throw MailAuthFailure.unavailable }
        handler = listener
        defer { listener.cancelHTTPListener(); handler = nil; authorization = nil; pendingCancellation = nil }
        let service = OIDServiceConfiguration(authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                                               tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!)
        // This initializer generates state, nonce and an S256 PKCE challenge inside AppAuth.
        let request = OIDAuthorizationRequest(configuration: service, clientId: clientID, clientSecret: nil,
                                               scopes: MailNativeConfiguration.googleScopes,
                                               redirectURL: redirect, responseType: OIDResponseTypeCode,
                                               additionalParameters: ["access_type": "offline", "prompt": "consent select_account"])
        let authorized: SDKCallbackPayload = try await withCheckedThrowingContinuation { continuation in
            let gate = CallbackGate(continuation)
            pendingCancellation = { gate.finish(.failure(MailAuthFailure.cancelled)) }
            authorization = OIDAuthState.authState(byPresenting: request, externalUserAgent: OIDExternalUserAgentMac()) { state, error in
                let payload = SDKCallbackPayload(state: state, error: error)
                Task { @MainActor in
                    if payload.state != nil { gate.finish(.success(payload)) }
                    else { gate.finish(.failure(payload.error ?? MailAuthFailure.unavailable)) }
                }
            }
            listener.currentAuthorizationFlow = authorization
        }
        guard let state = authorized.state else { throw MailAuthFailure.unavailable }
        guard let token = state.lastTokenResponse?.accessToken, state.refreshToken != nil else {
            throw MailAuthFailure.reconnectRequired
        }
        if let scopes = state.lastTokenResponse?.scope {
            let granted = Set(scopes.split(separator: " ").map(String.init))
            let required = MailNativeConfiguration.googleScopes.filter { $0.contains("/auth/gmail.") }
            guard Set(required).isSubset(of: granted) else { throw MailAuthFailure.denied }
        }
        return MailOAuthCredential(token: token, googleState: try archive(state), microsoftAccountID: nil)
    }

    private func msal() throws -> MSALPublicClientApplication {
        if let application { return application }
        guard let clientID = configuration.microsoftClientID else { throw MailAuthFailure.notConfigured }
        let authority = try MSALAADAuthority(url: URL(string: "https://login.microsoftonline.com/common")!)
        let config = MSALPublicClientApplicationConfig(clientId: clientID,
                                                       redirectUri: configuration.microsoftRedirectURI, authority: authority)
        // MSAL documents bundle ID as the private cache group. No shared Keychain entitlement is needed.
        config.cacheConfig.keychainSharingGroup = configuration.bundleIdentifier
        let app = try MSALPublicClientApplication(configuration: config)
        application = app
        return app
    }

    private func authorizeMicrosoft() async throws -> MailOAuthCredential {
        let app = try msal()
        preexistingMicrosoftIDs = Set(try app.allAccounts().compactMap(\.identifier))
        guard let controller = (NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }))?.contentViewController else {
            throw MailAuthFailure.unavailable
        }
        let web = MSALWebviewParameters(authPresentationViewController: controller)
        web.webviewType = .authenticationSession
        let parameters = MSALInteractiveTokenParameters(scopes: MailNativeConfiguration.microsoftScopes, webviewParameters: web)
        // MSAL adds openid/profile/offline_access itself; passing them as resource scopes is invalid.
        parameters.promptType = .selectAccount
        parameters.completionBlockQueue = .main
        defer { pendingCancellation = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = CallbackGate<MailOAuthCredential>(continuation)
            pendingCancellation = { gate.finish(.failure(MailAuthFailure.cancelled)) }
            app.acquireToken(with: parameters) { result, error in
                let payload = SDKCallbackPayload(result: result, error: error)
                Task { @MainActor in
                    if let result = payload.result, let identifier = result.account.identifier, !identifier.isEmpty {
                        let granted = Set(result.scopes.map { $0.split(separator: "/").last.map(String.init)?.lowercased() ?? "" })
                        guard Set(MailNativeConfiguration.microsoftScopes.map { $0.lowercased() }).isSubset(of: granted) else {
                            if !self.preexistingMicrosoftIDs.contains(identifier) { try? app.remove(result.account) }
                            gate.finish(.failure(MailAuthFailure.denied))
                            return
                        }
                        let delivered = gate.finish(.success(MailOAuthCredential(token: result.accessToken, googleState: nil,
                                                               microsoftAccountID: identifier)))
                        if !delivered, !self.preexistingMicrosoftIDs.contains(identifier) {
                            try? app.remove(result.account)
                        }
                    } else { gate.finish(.failure(payload.error ?? MailAuthFailure.unavailable)) }
                }
            }
        }
    }

    func refresh(record: MailCredentialRecord, force: Bool) async throws -> MailOAuthCredential {
        switch record.account.service {
        case .google:
            guard let data = record.googleState,
                  let state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data),
                  state.isAuthorized, state.refreshToken != nil else { throw MailAuthFailure.reconnectRequired }
            if force { state.setNeedsTokenRefresh() }
            let token: String = try await withCheckedThrowingContinuation { continuation in
                state.performAction { token, _, error in
                    if let token { continuation.resume(returning: token) }
                    else { continuation.resume(throwing: error ?? MailAuthFailure.reconnectRequired) }
                }
            }
            if let scopes = state.lastTokenResponse?.scope {
                let granted = Set(scopes.split(separator: " ").map(String.init))
                let required = MailNativeConfiguration.googleScopes.filter { $0.contains("/auth/gmail.") }
                guard Set(required).isSubset(of: granted) else { throw MailAuthFailure.reconnectRequired }
            }
            return MailOAuthCredential(token: token, googleState: try archive(state), microsoftAccountID: nil)
        case .microsoft:
            let app = try msal()
            guard let identifier = record.microsoftAccountID else { throw MailAuthFailure.reconnectRequired }
            guard let account = try app.allAccounts().first(where: { $0.identifier == identifier }) else {
                throw MailAuthFailure.reconnectRequired
            }
            let parameters = MSALSilentTokenParameters(scopes: MailNativeConfiguration.microsoftScopes, account: account)
            parameters.forceRefresh = force
            parameters.completionBlockQueue = .main
            return try await withCheckedThrowingContinuation { continuation in
                app.acquireTokenSilent(with: parameters) { result, error in
                    if let result {
                        let granted = Set(result.scopes.map { $0.split(separator: "/").last.map(String.init)?.lowercased() ?? "" })
                        guard Set(MailNativeConfiguration.microsoftScopes.map { $0.lowercased() }).isSubset(of: granted) else {
                            continuation.resume(throwing: MailAuthFailure.reconnectRequired)
                            return
                        }
                        continuation.resume(returning: MailOAuthCredential(token: result.accessToken, googleState: nil,
                                                                           microsoftAccountID: result.account.identifier))
                    } else { continuation.resume(throwing: error ?? MailAuthFailure.reconnectRequired) }
                }
            }
        case .icloud, .imap: throw MailAuthFailure.notConfigured
        }
    }

    func remove(record: MailCredentialRecord) throws {
        if let id = record.microsoftAccountID,
           let account = try msal().allAccounts().first(where: { $0.identifier == id }) {
            try msal().remove(account)
        }
    }

    func discard(_ credential: MailOAuthCredential, preserving records: [MailCredentialRecord]) throws {
        guard let id = credential.microsoftAccountID, !preexistingMicrosoftIDs.contains(id),
              !records.contains(where: { $0.microsoftAccountID == id }) else { return }
        guard let account = try msal().allAccounts().first(where: { $0.identifier == id }) else { return }
        try msal().remove(account)
    }

    func cancel() {
        pendingCancellation?()
        pendingCancellation = nil
        authorization?.cancel()
        handler?.cancelHTTPListener()
        _ = MSALPublicClientApplication.cancelCurrentWebAuthSession()
    }

    private func archive(_ state: OIDAuthState) throws -> Data {
        do { return try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true) }
        catch { throw MailAuthFailure.credentialStorage }
    }
}

@MainActor private final class CallbackGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    @discardableResult func finish(_ result: Result<Value, Error>) -> Bool {
        guard let continuation else { return false }
        continuation.resume(with: result)
        self.continuation = nil
        return true
    }
}

/// Bridges SDK completion ownership onto MainActor. Neither the callback nor a background task
/// accesses these SDK objects again; every subsequent read/mutation stays in the main-actor driver.
private struct SDKCallbackPayload: @unchecked Sendable {
    var state: OIDAuthState? = nil
    var result: MSALResult? = nil
    var error: Error? = nil
}
