import AVFoundation
import Foundation
import Observation
import Speech

// Phase 13: talk to Ask. The mic in the prompt field listens on this Mac only (on-device speech recognition,
// `requiresOnDeviceRecognition`), writes what it hears into the field as you speak, and stops when you go quiet or
// click again. Nothing is recorded or kept: the audio goes straight to the recogniser and is gone.
//
// `SpeechAnalyzer`/`DictationTranscriber` (macOS 26) would work too, but need their language assets installed
// first; `SFSpeechRecognizer` with on-device recognition uses the dictation models the Mac already has, and
// refuses to run (rather than going to a server) when it can't do it here.

/// What the recogniser tells the dictation, from any thread.
enum DictationEvent: Equatable, Sendable {
    /// Everything heard so far (it may still change).
    case partial(String)
    /// The final words, once the audio ended.
    case final(String)
    /// How loud the mic is, 0…1, for the meter.
    case level(Double)
    /// It stopped with an error; `noSpeech` when it simply heard nothing.
    case failed(noSpeech: Bool)
}

enum DictationPermission: Equatable, Sendable {
    case granted, microphoneDenied, speechDenied
}

/// The recogniser behind the mic, replaceable in tests.
@MainActor
protocol DictationRecognizer: AnyObject {
    /// Checks both permissions, showing the system's dialogs only when `ask` and they were never answered.
    func permission(ask: Bool) async -> DictationPermission
    /// The first of the user's languages this Mac can recognise on-device, or nil.
    func locale() -> Locale?
    /// Starts listening. `events` may be called on any thread.
    func start(locale: Locale, events: @escaping @Sendable (DictationEvent) -> Void) throws
    /// Stops the audio; the final words follow as an event.
    func finish()
    /// Stops at once, dropping everything.
    func cancel()
}

/// Delayed work the dictation needs (silence, time limits), replaceable in tests.
@MainActor
protocol DictationScheduling {
    func after(_ delay: Duration, _ work: @escaping @MainActor () -> Void) -> any DictationScheduled
}

@MainActor
protocol DictationScheduled {
    func cancel()
}

struct TaskDictationScheduler: DictationScheduling {
    private struct Scheduled: DictationScheduled {
        let task: Task<Void, Never>
        func cancel() { task.cancel() }
    }

    func after(_ delay: Duration, _ work: @escaping @MainActor () -> Void) -> any DictationScheduled {
        Scheduled(task: Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            work()
        })
    }
}

/// The mic's state machine: idle → preparing (permissions) → listening → finishing (waiting for the final
/// words) → idle. A problem is kept for the view to explain until the next start.
@MainActor
@Observable
final class AssistantDictation {
    enum State: Equatable, Sendable {
        case idle, preparing, listening, finishing
    }

    enum Problem: Equatable, Sendable {
        case microphoneDenied, speechDenied
        /// None of the user's languages can be recognised on this Mac.
        case unavailable
        case noSpeech
        case failed

        var message: String {
            switch self {
            case .microphoneDenied:
                String(localized: "Altillo can't use the microphone. Allow it in System Settings › Privacy & Security › Microphone.")
            case .speechDenied:
                String(localized: "Altillo can't use speech recognition. Allow it in System Settings › Privacy & Security › Speech Recognition.")
            case .unavailable:
                String(localized: "This Mac can't recognise speech in your language on its own yet. Try turning on Dictation in System Settings › Keyboard.")
            case .noSpeech:
                String(localized: "I didn't hear anything. Try again a bit closer to the mic.")
            case .failed:
                String(localized: "Dictation stopped unexpectedly. Try again.")
            }
        }
    }

    /// How it ended, for the store: the words and whether silence ended it (rather than a click).
    struct Ending: Equatable, Sendable {
        var text: String
        var bySilence: Bool
    }

    private(set) var state: State = .idle
    private(set) var problem: Problem?
    /// 0…1, for the meter.
    private(set) var level: Double = 0
    /// What's been heard so far.
    private(set) var transcript = ""

    var isActive: Bool { state != .idle }

    /// Every change of the words heard.
    @ObservationIgnored var onTranscript: (String) -> Void = { _ in }
    /// Once it's over with some words.
    @ObservationIgnored var onEnded: (Ending) -> Void = { _ in }

    /// Quiet this long after some words ends it.
    @ObservationIgnored var silenceAfterSpeech: Duration = .seconds(1.8)
    /// Nothing heard this long ends it.
    @ObservationIgnored var silenceBeforeSpeech: Duration = .seconds(6)
    /// Never listens longer than this.
    @ObservationIgnored var maximum: Duration = .seconds(60)
    /// How long to wait for the final words after the audio stopped.
    @ObservationIgnored var finalWait: Duration = .seconds(1.5)

    @ObservationIgnored private let recognizer: any DictationRecognizer
    @ObservationIgnored private let scheduler: any DictationScheduling
    @ObservationIgnored private var silence: (any DictationScheduled)?
    @ObservationIgnored private var limit: (any DictationScheduled)?
    @ObservationIgnored private var finalTimeout: (any DictationScheduled)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var endsBySilence = false

    init(recognizer: any DictationRecognizer, scheduler: any DictationScheduling = TaskDictationScheduler()) {
        self.recognizer = recognizer
        self.scheduler = scheduler
    }

    /// The mic button: start, or stop and keep what was heard.
    func toggle() async {
        if state == .idle { await start() } else { stop() }
    }

    func start() async {
        guard state == .idle else { return }
        problem = nil
        transcript = ""
        level = 0
        state = .preparing
        generation += 1
        let current = generation
        let permission = await recognizer.permission(ask: true)
        // Cancelled while the dialog was up.
        guard state == .preparing, generation == current else { return }
        switch permission {
        case .microphoneDenied: return fail(.microphoneDenied)
        case .speechDenied: return fail(.speechDenied)
        case .granted: break
        }
        guard let locale = recognizer.locale() else { return fail(.unavailable) }
        do {
            try recognizer.start(locale: locale) { [weak self] event in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.handle(event)
                }
            }
        } catch {
            return fail(.failed)
        }
        state = .listening
        endsBySilence = false
        SpikeLog.shared.record(SpikeLog.Category.assistant, "dictation started (\(locale.identifier))")
        armSilence(after: silenceBeforeSpeech)
        limit = scheduler.after(maximum) { [weak self] in self?.stop() }
    }

    /// A click on the mic while it listens: stop and keep the words.
    func stop() {
        stop(bySilence: false)
    }

    /// Escape, a new conversation, the section going away: stop and keep what's already in the field, without
    /// sending anything.
    func cancel() {
        guard state != .idle else { return }
        recognizer.cancel()
        reset()
    }

    /// Something the recogniser said (the live one hops here from its thread).
    func handle(_ event: DictationEvent) {
        switch event {
        case let .level(value):
            guard state == .listening else { return }
            level = min(max(value, 0), 1)
        case let .partial(text):
            guard state == .listening || state == .finishing else { return }
            update(text)
            if state == .listening { armSilence(after: silenceAfterSpeech) }
        case let .final(text):
            guard state == .listening || state == .finishing else { return }
            update(text)
            end()
        case let .failed(noSpeech):
            guard state != .idle else { return }
            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                end()
            } else {
                recognizer.cancel()
                fail(noSpeech ? .noSpeech : .failed)
            }
        }
    }

    // MARK: - Private

    private func stop(bySilence: Bool) {
        guard state == .listening || state == .preparing else { return }
        if state == .preparing {
            // Still asking for permission: nothing was heard.
            generation += 1
            reset()
            return
        }
        endsBySilence = bySilence
        state = .finishing
        level = 0
        silence?.cancel()
        limit?.cancel()
        recognizer.finish()
        finalTimeout = scheduler.after(finalWait) { [weak self] in self?.end() }
    }

    private func update(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != transcript else { return }
        transcript = clean
        onTranscript(clean)
    }

    private func armSilence(after delay: Duration) {
        silence?.cancel()
        silence = scheduler.after(delay) { [weak self] in
            guard let self, self.state == .listening else { return }
            if self.transcript.isEmpty {
                self.recognizer.cancel()
                self.fail(.noSpeech)
            } else {
                self.stop(bySilence: true)
            }
        }
    }

    private func end() {
        guard state != .idle else { return }
        let text = transcript
        let bySilence = endsBySilence
        recognizer.cancel()
        reset()
        SpikeLog.shared.record(SpikeLog.Category.assistant, "dictation ended (\(text.count) chars, silence: \(bySilence))")
        guard !text.isEmpty else { return }
        onEnded(Ending(text: text, bySilence: bySilence))
    }

    private func fail(_ problem: Problem) {
        reset()
        self.problem = problem
        SpikeLog.shared.record(SpikeLog.Category.assistant, "dictation problem: \(problem)")
    }

    private func reset() {
        silence?.cancel()
        limit?.cancel()
        finalTimeout?.cancel()
        silence = nil
        limit = nil
        finalTimeout = nil
        state = .idle
        level = 0
    }

    func clearProblem() { problem = nil }
}

// MARK: - The real recogniser

/// `SFSpeechRecognizer` on this Mac only, fed by the default microphone through `AVAudioEngine`.
@MainActor
final class LiveDictationRecognizer: DictationRecognizer {
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    func permission(ask: Bool) async -> DictationPermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard ask, await Self.requestMicrophone() else { return .microphoneDenied }
        default: return .microphoneDenied
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined:
            guard ask else { return .speechDenied }
            return await Self.requestSpeech() == .authorized ? .granted : .speechDenied
        default: return .speechDenied
        }
    }

    func locale() -> Locale? {
        Self.onDeviceLocale(preferring: Locale.preferredLanguages)
    }

    /// The first language the user prefers that this Mac recognises on-device.
    static func onDeviceLocale(preferring languages: [String]) -> Locale? {
        for identifier in languages {
            let locale = Locale(identifier: identifier)
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition {
                return locale
            }
        }
        return nil
    }

    func start(locale: Locale, events: @escaping @Sendable (DictationEvent) -> Void) throws {
        cancel()
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition,
              recognizer.isAvailable
        else { throw CocoaError(.featureUnsupported) }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
        let sink = DictationAudioSink(request: request, events: events)
        input.installTap(onBus: 0, bufferSize: 4_096, format: format, block: Self.tap(sink))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        self.request = request
        self.recognizer = recognizer
        task = recognizer.recognitionTask(with: request, resultHandler: Self.results(events))
    }

    func finish() {
        stopAudio()
        request?.endAudio()
    }

    func cancel() {
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
    }

    private func stopAudio() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    // Built outside the main actor: AVFoundation and Speech call these on their own threads.

    private nonisolated static func tap(_ sink: DictationAudioSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.consume(buffer) }
    }

    private nonisolated static func results(
        _ events: @escaping @Sendable (DictationEvent) -> Void
    ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                events(result.isFinal ? .final(text) : .partial(text))
            } else if let error {
                // kAFAssistantErrorDomain 1110: no speech was detected.
                let nsError = error as NSError
                events(.failed(noSpeech: nsError.code == 1110 || nsError.code == 203))
            }
        }
    }

    private nonisolated static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private nonisolated static func requestSpeech() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}

/// Hands the microphone's buffers to the recogniser and measures their level, on the audio thread.
/// `SFSpeechAudioBufferRecognitionRequest.append` is made to be called from there.
private final class DictationAudioSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let events: @Sendable (DictationEvent) -> Void

    init(request: SFSpeechAudioBufferRecognitionRequest, events: @escaping @Sendable (DictationEvent) -> Void) {
        self.request = request
        self.events = events
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        events(.level(Self.level(of: buffer)))
    }

    /// Loudness of the first channel as 0…1 (−50 dB and below is silence).
    static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let rms = sqrt(sum / Float(count))
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(max((decibels + 50) / 50, 0), 1)
    }
}
