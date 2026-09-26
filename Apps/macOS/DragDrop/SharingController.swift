import AltilloCore
import AppKit

@MainActor
protocol SharingServiceAdapterDelegate: AnyObject {
    func sharingServiceDidFinish()
    func sharingServiceDidFail(_ error: any Error)
}

/// Small seam around AppKit so lifecycle and cleanup can be tested without displaying system UI.
@MainActor
protocol SharingServiceAdapter: AnyObject {
    var eventDelegate: (any SharingServiceAdapterDelegate)? { get set }
    func canPerform(with items: [Any]) -> Bool
    func perform(with items: [Any])
}

@MainActor
final class AppKitSharingServiceAdapter: NSObject, SharingServiceAdapter, NSSharingServiceDelegate {
    let service: NSSharingService
    weak var eventDelegate: (any SharingServiceAdapterDelegate)?

    init(service: NSSharingService) {
        self.service = service
        super.init()
        service.delegate = self
    }

    func canPerform(with items: [Any]) -> Bool { service.canPerform(withItems: items) }

    func perform(with items: [Any]) { service.perform(withItems: items) }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        eventDelegate?.sharingServiceDidFinish()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        eventDelegate?.sharingServiceDidFail(error)
    }
}

/// One retained share. Disposable drop copies survive until AppKit reports success or failure.
@MainActor
final class SharingOperation: SharingServiceAdapterDelegate {
    let id = UUID()
    let items: [ShelfItem]
    let payload: [Any]

    private let service: any SharingServiceAdapter
    private let inboxRoot: URL
    private let cleansOwnedCopies: Bool
    private let completion: (UUID) -> Void
    private(set) var isFinished = false

    init(
        items: [ShelfItem],
        service: any SharingServiceAdapter,
        inboxRoot: URL,
        cleansOwnedCopies: Bool,
        completion: @escaping (UUID) -> Void
    ) {
        self.items = items
        payload = Self.payload(for: items)
        self.service = service
        self.inboxRoot = inboxRoot
        self.cleansOwnedCopies = cleansOwnedCopies
        self.completion = completion
        service.eventDelegate = self
    }

    static func payload(for items: [ShelfItem]) -> [Any] {
        items.map { item in
            switch item.kind {
            case let .file(url, _): url
            case let .link(url): url
            case let .text(text): text
            }
        }
    }

    /// Starts a service selected directly (AirDrop). Picker-selected services are performed by AppKit itself.
    @discardableResult
    func start() -> Bool {
        guard !payload.isEmpty, service.canPerform(with: payload) else {
            finish()
            return false
        }
        service.perform(with: payload)
        return true
    }

    func sharingServiceDidFinish() { finish() }

    func sharingServiceDidFail(_ error: any Error) { finish() }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        if cleansOwnedCopies { OwnedInboxCopy.discard(in: items, inboxRoot: inboxRoot) }
        completion(id)
    }
}

/// Owns every in-flight share so AppKit's weak delegates remain alive through success, failure or cancellation.
@MainActor
final class SharingController: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    typealias ServiceFactory = (NSSharingService.Name) -> (any SharingServiceAdapter)?

    private struct PickerContext {
        let picker: NSSharingServicePicker
        let items: [ShelfItem]
    }

    private let inboxRoot: URL
    private let serviceFactory: ServiceFactory
    private var operations: [UUID: SharingOperation] = [:]
    private var pickers: [ObjectIdentifier: PickerContext] = [:]

    init(
        inboxRoot: URL = FileIngest.standard.inboxRoot,
        serviceFactory: @escaping ServiceFactory = { name in
            NSSharingService(named: name).map { AppKitSharingServiceAdapter(service: $0) }
        }
    ) {
        self.inboxRoot = inboxRoot
        self.serviceFactory = serviceFactory
    }

    var activeOperationCount: Int { operations.count }

    /// Returns false only when AirDrop has nothing it can accept. Owned copies are still cleaned in that case.
    @discardableResult
    func sendViaAirDrop(_ items: [ShelfItem], cleanupOwnedCopies: Bool) -> Bool {
        guard let service = serviceFactory(.sendViaAirDrop) else {
            if cleanupOwnedCopies { OwnedInboxCopy.discard(in: items, inboxRoot: inboxRoot) }
            return false
        }
        let operation = makeOperation(items: items, service: service, cleansOwnedCopies: cleanupOwnedCopies)
        return operation.start()
    }

    /// Shows macOS's standard service picker. The caller supplies a stable view in the notch window to anchor it.
    @discardableResult
    func showSharePicker(for items: [ShelfItem], relativeTo view: NSView) -> Bool {
        let payload = SharingOperation.payload(for: items)
        guard !payload.isEmpty else { return false }
        let picker = NSSharingServicePicker(items: payload)
        picker.delegate = self
        pickers[ObjectIdentifier(picker)] = PickerContext(picker: picker, items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        return true
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        delegateFor sharingService: NSSharingService
    ) -> (any NSSharingServiceDelegate)? {
        guard let context = pickers[ObjectIdentifier(sharingServicePicker)] else { return nil }
        let adapter = AppKitSharingServiceAdapter(service: sharingService)
        _ = makeOperation(items: context.items, service: adapter, cleansOwnedCopies: false)
        return adapter
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose sharingService: NSSharingService?
    ) {
        pickers.removeValue(forKey: ObjectIdentifier(sharingServicePicker))
    }

    private func makeOperation(
        items: [ShelfItem], service: any SharingServiceAdapter, cleansOwnedCopies: Bool
    ) -> SharingOperation {
        let operation = SharingOperation(
            items: items,
            service: service,
            inboxRoot: inboxRoot,
            cleansOwnedCopies: cleansOwnedCopies
        ) { [weak self] id in
            self?.operations.removeValue(forKey: id)
        }
        operations[operation.id] = operation
        return operation
    }
}
