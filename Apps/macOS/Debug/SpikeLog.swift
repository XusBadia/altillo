import Foundation
import Observation
import SwiftUI

/// In-app log for the phase 0 drag & drop spikes, so the test matrix can be checked without Console.app.
/// STUB: implemented by the drag & drop spike. Keep this API.
@MainActor
@Observable
final class SpikeLog {
    static let shared = SpikeLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let category: String
        let message: String
    }

    private(set) var entries: [Entry] = []

    func record(_ category: String, _ message: String) {
        entries.append(Entry(category: category, message: message))
    }
}

struct SpikeLogView: View {
    static let windowID = "spike-log"
    let log: SpikeLog

    var body: some View {
        List(log.entries) { entry in
            Text("[\(entry.category)] \(entry.message)")
        }
    }
}
