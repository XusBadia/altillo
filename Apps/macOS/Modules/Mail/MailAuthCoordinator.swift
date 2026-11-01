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
    private var operation: UUID?
    private var cancelledOperations: Set<UUID> = []
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
         resolveIdentity: @escaping @MainActor (NativeMailService, String) async throws -> NativeMailIdentity = {
             try await NativeMailIdentityResolver.resolve(service: $0, token: $1)
         }) {
        self.vault = vault
        self.configuration = configuration
        self.driver = driver ?? SDKMailAuthenticationDriver(configuration: configuration)
        self.resolveIdentity = resolveIdentity
    }

    var availableServices: [NativeMailService] { configuration.availableServices }

    func restoreAccounts() throws -> [NativeMailAccount] { try vault.records().map(\.account) }

    func connect(service: NativeMailService, replacing: NativeMailAccount? = nil) async throws -> NativeMailAccount {
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
                                                    microsoftAccountID: credential.microsoftAccountID))
                generations[account.id] = UUID()
                flights.removeValue(forKey: account.id)?.task.cancel()
                return account
            } catch {
                if let pending {
                    // MSAL already cached a successful login. Remove only an unreferenced new SDK identity.
                    try? driver.discard(pending, preserving: vault.records())
                }
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
        if let flight = flights[account.id] {
            let result = try await flight.task.value
            if !forceRefresh || flight.forced { return result }
            if flights[account.id]?.id == flight.id { flights.removeValue(forKey: account.id) }
            return try await accessToken(for: account, forceRefresh: true)
        }
        guard let record = try vault.record(for: account.id), record.account == account else {
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
                                                        microsoftAccountID: nil))
                }
                return credential.token
            } catch { throw Self.failure(error) }
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
        do { try driver.remove(record: record) }
        catch { throw Self.failure(error) }
        try vault.remove(account.id)
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
                                               scopes: ["openid", "email", "https://www.googleapis.com/auth/gmail.readonly"],
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
        let parameters = MSALInteractiveTokenParameters(scopes: ["User.Read", "Mail.Read"], webviewParameters: web)
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
            return MailOAuthCredential(token: token, googleState: try archive(state), microsoftAccountID: nil)
        case .microsoft:
            let app = try msal()
            guard let identifier = record.microsoftAccountID else { throw MailAuthFailure.reconnectRequired }
            guard let account = try app.allAccounts().first(where: { $0.identifier == identifier }) else {
                throw MailAuthFailure.reconnectRequired
            }
            let parameters = MSALSilentTokenParameters(scopes: ["User.Read", "Mail.Read"], account: account)
            parameters.forceRefresh = force
            parameters.completionBlockQueue = .main
            return try await withCheckedThrowingContinuation { continuation in
                app.acquireTokenSilent(with: parameters) { result, error in
                    if let result {
                        continuation.resume(returning: MailOAuthCredential(token: result.accessToken, googleState: nil,
                                                                           microsoftAccountID: result.account.identifier))
                    } else { continuation.resume(throwing: error ?? MailAuthFailure.reconnectRequired) }
                }
            }
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
