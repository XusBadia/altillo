import Foundation

// The legacy `openusage.mobile.v1` wire format read by the old TestFlight iPhone app (bundle me.badia.ailimits)
// from the iCloud container iCloud.me.badia.ailimits (PLAN §5.2 "transición opcional", docs/uso-ia.md).
// Shape and validation rules adapted from openusage's MobileUsageDocument (MIT, © Robin Ebers and contributors):
// the phone rejects any file that breaks them, so `validate()` mirrors the reader exactly. Nothing here is shown
// to the user as "OpenUsage"; the name only survives in the wire schema and the folder the phone reads.

struct OpenUsageMobileDocument: Codable, Hashable, Sendable {
    static let schema = "openusage.mobile.v1"

    var schema: String = Self.schema
    var deviceID: String
    var deviceName: String
    var updatedAt: Date
    var providerOrder: [String]
    var providers: [String: Provider]

    struct Provider: Codable, Hashable, Sendable {
        enum Status: String, Codable, Hashable, Sendable {
            case available, attention, unavailable
        }

        var providerID: String
        var displayName: String
        var plan: String?
        var refreshedAt: Date
        var status: Status
        var metrics: [Metric]
    }

    struct Metric: Codable, Hashable, Sendable {
        enum Presentation: String, Codable, Hashable, Sendable {
            case progress, values
        }

        var id: String
        var label: String
        var presentation: Presentation
        var used: Double?
        var limit: Double?
        var unit: Unit?
        var values: [Value] = []
        var resetsAt: Date?
        var periodDurationMilliseconds: Int?
        var expiriesAt: [Date] = []
        var colorHex: String?
    }

    struct Unit: Codable, Hashable, Sendable {
        enum Kind: String, Codable, Hashable, Sendable {
            case percent, dollars, count
        }

        var kind: Kind
        var suffix: String?
    }

    struct Value: Codable, Hashable, Sendable {
        var number: Double
        var unit: Unit
        var label: String?
        var estimated: Bool = false
    }

    // MARK: - Limits the phone enforces

    static let providerIDPattern = #"^[a-z0-9][a-z0-9-]*(?:@[a-f0-9]{8})?$"#
    static let maxDeviceNameLength = 120
    static let maxTextLength = 80
    static let maxValueLabelLength = 40
    static let maxSuffixLength = 20
    static let maxIdentifierLength = 128

    enum ValidationError: Error, Equatable {
        case unsupportedSchema, invalidDevice, invalidProviderOrder
        case invalidProvider(String), invalidPlan(String), duplicateMetric(String), invalidMetric(String)
    }

    /// The same checks the iPhone app runs before accepting a file.
    func validate() throws {
        guard schema == Self.schema else { throw ValidationError.unsupportedSchema }
        guard Self.isValidIdentifier(deviceID), Self.isValidText(deviceName, max: Self.maxDeviceNameLength) else {
            throw ValidationError.invalidDevice
        }
        guard Set(providerOrder).count == providerOrder.count, Set(providerOrder).isSubset(of: Set(providers.keys)) else {
            throw ValidationError.invalidProviderOrder
        }
        for (key, provider) in providers {
            guard key == provider.providerID, Self.isValidProviderID(key),
                  Self.isValidText(provider.displayName, max: Self.maxTextLength) else {
                throw ValidationError.invalidProvider(key)
            }
            if let plan = provider.plan, !Self.isValidText(plan, max: Self.maxTextLength) {
                throw ValidationError.invalidPlan(key)
            }
            guard Set(provider.metrics.map(\.id)).count == provider.metrics.count else {
                throw ValidationError.duplicateMetric(key)
            }
            for metric in provider.metrics where !metric.isValid {
                throw ValidationError.invalidMetric(key)
            }
        }
    }

    static func isValidProviderID(_ value: String) -> Bool {
        value.range(of: providerIDPattern, options: .regularExpression) != nil
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= maxIdentifierLength
            && value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
            && !value.contains("/") && !value.contains("\\")
    }

    static func isValidText(_ value: String, max: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= max
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

    // MARK: - Encoding

    /// Pretty-printed, sorted keys, ISO 8601 dates without fractional seconds (the phone's decoder uses plain
    /// `.iso8601`, which rejects fractions), exactly like the bridge wrote them.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func encoded() throws -> Data {
        try validate()
        return try Self.encoder().encode(self)
    }
}

extension OpenUsageMobileDocument.Metric {
    var isValid: Bool {
        guard OpenUsageMobileDocument.isValidIdentifier(id),
              OpenUsageMobileDocument.isValidText(label, max: OpenUsageMobileDocument.maxTextLength),
              values.allSatisfy(\.isValid),
              periodDurationMilliseconds.map({ $0 > 0 }) ?? true,
              colorHex.map({ $0.range(of: #"^#[A-Fa-f0-9]{6}$"#, options: .regularExpression) != nil }) ?? true
        else { return false }
        switch presentation {
        case .progress:
            guard let used, used.isFinite, used >= 0, let limit, limit.isFinite, limit > 0 else { return false }
            return unit != nil && values.isEmpty
        case .values:
            return used == nil && limit == nil && unit == nil && !values.isEmpty
        }
    }
}

extension OpenUsageMobileDocument.Value {
    var isValid: Bool {
        number.isFinite && number >= 0
            && label.map { $0.rangeOfCharacter(from: .controlCharacters) == nil && $0.count <= OpenUsageMobileDocument.maxValueLabelLength } ?? true
            && unit.suffix.map { $0.rangeOfCharacter(from: .controlCharacters) == nil && $0.count <= OpenUsageMobileDocument.maxSuffixLength } ?? true
    }
}
