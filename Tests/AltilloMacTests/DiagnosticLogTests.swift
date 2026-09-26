import Foundation
import Testing
@testable import Altillo

@MainActor
struct DiagnosticLogTests {
    @Test func redactsPathsFilenamesActiveApplicationsAndPasteboardTypes() {
        let message = "active app: Finder · types: public.file-url, public.utf8-plain-text · copy → /Users/alice/Private/Quarterly Plan.pdf"

        let redacted = DiagnosticLog.redact(message)

        #expect(redacted.contains("active app: <redacted>"))
        #expect(redacted.contains("types: <redacted>"))
        #expect(redacted.contains("<path>"))
        #expect(!redacted.contains("Finder"))
        #expect(!redacted.contains("public.file-url"))
        #expect(!redacted.contains("alice"))
        #expect(!redacted.contains("Quarterly Plan.pdf"))
    }

    @Test func redactsStandaloneFilenamesAndHomeRelativePaths() {
        let message = "FAILED reading Private roadmap 2027.pages at ~/Desktop/Private roadmap 2027.pages"

        let redacted = DiagnosticLog.redact(message)

        #expect(!redacted.contains("Private roadmap 2027.pages"))
        #expect(!redacted.contains("~/Desktop"))
        #expect(redacted.contains("<file>"))
        #expect(redacted.contains("<path>"))
    }

    @Test func recordAndExportOnlyUseTheRedactedMessage() {
        let log = DiagnosticLog()
        log.record(DiagnosticLog.Category.ingest, "reference → /Users/alice/Documents/taxes-2026.pdf")

        let entry = log.entries.first
        let exported = DiagnosticLog.export(log.entries)

        #expect(entry?.message == "reference → <path>")
        #expect(!exported.contains("alice"))
        #expect(!exported.contains("taxes-2026.pdf"))
        #expect(exported.contains("<path>"))
    }
}
