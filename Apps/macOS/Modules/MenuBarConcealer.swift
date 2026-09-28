import Foundation
import ObjectiveC
import Security
import os

/// What the menu bar may show while the Drawer hides the rest: whole apps by bundle id, plus macOS's own
/// items by number (`MenuBarSystemItemIdentifier`: 2 clock, 6 network, 8 Control Center… measured on 27.0).
struct MenuBarAllowList: Equatable, Sendable {
    var bundleIDs: Set<String>
    var systemItems: Set<Int>

    /// Growing an active list is seamless; anything else needs a fresh assertion.
    func extends(_ other: MenuBarAllowList) -> Bool {
        other.bundleIDs.isSubset(of: bundleIDs) && other.systemItems.isSubset(of: systemItems)
    }
}

/// Hides every menu-bar item that isn't allowed. Tests use a fake: they must never touch the real menu bar.
@MainActor
protocol MenuBarConcealing: AnyObject {
    /// The system can hide icons at all. Unavailable means nothing is ever hidden.
    var isAvailable: Bool { get }
    var isActive: Bool { get }
    /// Shows only `list`. Returns false (and hides nothing) when macOS refuses.
    func conceal(allowing list: MenuBarAllowList) async -> Bool
    /// Every icon comes back. Also happens on its own when Altillo quits or crashes.
    func release()
}

/// macOS 27's MenuBarAgent keeps an allow-list for Assessment Mode (the exam lockdown): while an assertion
/// is held, only the listed apps and system items are drawn. `MenuBarClientCore` is private, so everything is
/// looked up at run time and fails closed: a missing class or selector means hiding is unavailable, never
/// that icons get stuck. The assertion lives in Altillo's process, so quitting or crashing restores the bar.
///
/// Measured on 27.0 (docs/spikes/macos27-menubar-assessment.md): activating the same assertion again with a
/// longer list shows the new items without a flicker; a shorter list is ignored, so shrinking needs a new
/// assertion, and the bar shows everything for about a second in between.
@MainActor
final class MenuBarConcealer: MenuBarConcealing {
    private typealias InitConfiguration = @convention(c) (NSObject, Selector, NSArray, NSArray) -> Unmanaged<NSObject>?
    private typealias Activate = @convention(c) (NSObject, Selector, NSObject, @escaping @convention(block) (NSError?) -> Void) -> Void

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let initSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")
    private static let activationTimeout: Duration = .seconds(2)
    private static let log = Logger(subsystem: "me.badia.altillo", category: "drawer")

    private let assertionClass: NSObject.Type?
    private let configurationClass: AnyClass?
    private var assertion: NSObject?
    private var current: MenuBarAllowList?

    init() {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration"),
              assertion.instancesRespond(to: Self.activateSelector),
              assertion.instancesRespond(to: Self.invalidateSelector),
              class_getInstanceMethod(configuration, Self.initSelector) != nil else {
            Self.log.error("concealer unavailable: MenuBarClientCore API missing")
            assertionClass = nil
            configurationClass = nil
            return
        }
        assertionClass = assertion
        configurationClass = configuration
        if Self.isAdHocSigned {
            Self.log.notice("concealer: ad-hoc signature, macOS will hide Altillo's own menu bar item while hiding")
        }
    }

    /// MenuBarAgent allow-lists signed apps by bundle; an ad-hoc build (Debug from DerivedData) is never shown.
    private static var isAdHocSigned: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? UInt32 else { return false }
        return flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    }

    var isAvailable: Bool { assertionClass != nil }
    var isActive: Bool { assertion != nil }

    func conceal(allowing list: MenuBarAllowList) async -> Bool {
        guard let assertionClass else { return false }
        if let assertion, let current, list.extends(current) {
            if list == current { return true }
            return await activate(assertion, with: list)
        }
        release()
        let fresh = assertionClass.init()
        assertion = fresh
        return await activate(fresh, with: list)
    }

    func release() {
        guard let assertion else { return }
        _ = assertion.perform(Self.invalidateSelector)
        self.assertion = nil
        current = nil
    }

    private func activate(_ target: NSObject, with list: MenuBarAllowList) async -> Bool {
        guard let configuration = makeConfiguration(list) else {
            Self.log.error("concealer: configuration init returned nil")
            release()
            return false
        }
        let activate = unsafeBitCast(target.method(for: Self.activateSelector), to: Activate.self)
        let outcome = OSAllocatedUnfairLock<CheckedContinuation<Bool, Never>?>(initialState: nil)
        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            outcome.withLock { $0 = continuation }
            let timeout = Task {
                try? await Task.sleep(for: Self.activationTimeout)
                outcome.withLock { $0.take() }?.resume(returning: false)
            }
            activate(target, Self.activateSelector, configuration) { error in
                if let error { Self.log.error("concealer: activation failed \(error.localizedDescription, privacy: .public)") }
                timeout.cancel()
                outcome.withLock { $0.take() }?.resume(returning: error == nil)
            }
        }
        // A newer call may have replaced or released this assertion while macOS answered.
        guard assertion === target else { return false }
        if succeeded {
            current = list
        } else {
            release()
        }
        Self.log.debug("concealer: active=\(succeeded) bundles=\(list.bundleIDs.count) system=\(list.systemItems.count)")
        return succeeded
    }

    private func makeConfiguration(_ list: MenuBarAllowList) -> NSObject? {
        guard let configurationClass,
              let allocMethod = class_getClassMethod(configurationClass, NSSelectorFromString("alloc")) else { return nil }
        typealias Alloc = @convention(c) (AnyClass, Selector) -> Unmanaged<NSObject>
        let alloc = unsafeBitCast(method_getImplementation(allocMethod), to: Alloc.self)
        let allocated = alloc(configurationClass, NSSelectorFromString("alloc"))
        let initialize = unsafeBitCast(class_getMethodImplementation(configurationClass, Self.initSelector),
                                       to: InitConfiguration.self)
        // `init` consumes the allocated reference and returns an owned one (or releases it and returns nil).
        let systemItems = list.systemItems.sorted().map { NSNumber(value: $0) } as NSArray
        let bundles = list.bundleIDs.sorted() as NSArray
        return initialize(allocated.takeUnretainedValue(), Self.initSelector, systemItems, bundles)?
            .takeRetainedValue()
    }
}

/// Where hiding can't work (macOS 26, or a future macOS without the API): the Drawer only opens menus.
@MainActor
final class UnavailableMenuBarConcealer: MenuBarConcealing {
    var isAvailable: Bool { false }
    var isActive: Bool { false }
    func conceal(allowing list: MenuBarAllowList) async -> Bool { false }
    func release() {}
}
