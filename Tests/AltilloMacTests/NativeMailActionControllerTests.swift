import AltilloMail
import Foundation
import Testing
@testable import Altillo

@MainActor struct NativeMailActionControllerTests {
    @Test func composeSendParsesRecipientsAndGuardsDoubleClick() async {
        let account = makeAccount("sender")
        let provider = ActionMailProvider(account: account)
        await provider.holdSending()
        let controller = makeController([provider])
        controller.startCompose()
        #expect(!controller.isComposing)
        controller.setEnabled(true)
        controller.startCompose()
        controller.draftTo = " one@example.invalid ; two@example.invalid, "
        controller.draftCc = "cc@example.invalid"
        controller.draftBcc = "hidden@example.invalid; another@example.invalid"
        controller.draftSubject = "Synthetic subject"
        controller.draftText = "Synthetic body"
        let attachment = NativeMailOutgoingAttachment(filename: "synthetic.txt", mimeType: "text/plain", data: Data("synthetic".utf8))
        do { try controller.addDraftAttachments([attachment]) }
        catch { Issue.record("Synthetic attachment should be accepted") }
        let send = Task { await controller.sendDraft() }
        await provider.waitForSend()
        #expect(controller.isSending)
        #expect(!controller.canRefresh)
        await controller.sendDraft()
        let sent = await provider.sentDrafts
        #expect(sent.count == 1)
        #expect(sent.first?.to == ["one@example.invalid", "two@example.invalid"])
        #expect(sent.first?.cc == ["cc@example.invalid"])
        #expect(sent.first?.bcc == ["hidden@example.invalid", "another@example.invalid"])
        #expect(sent.first?.text == "Synthetic body")
        #expect(sent.first?.attachments == [attachment])
        await provider.finishSend()
        await send.value
        #expect(!controller.isSending)
        #expect(!controller.isComposing)
        #expect(controller.draftTo.isEmpty && controller.draftCc.isEmpty && controller.draftBcc.isEmpty)
        #expect(controller.draftSubject.isEmpty && controller.draftText.isEmpty)
        #expect(controller.draftAttachments.isEmpty)
        #expect(controller.actionStatus != nil)
        controller.setEnabled(false)
    }

    @Test(arguments: [false, true])
    func pauseClearsDraftAndDiscardsLateSendCompletion(suspend: Bool) async {
        let provider = ActionMailProvider(account: makeAccount("sender"))
        await provider.holdSending()
        let controller = makeController([provider])
        controller.setEnabled(true)
        controller.startCompose()
        controller.draftTo = "recipient@example.invalid"
        controller.draftBcc = "private@example.invalid"
        controller.draftSubject = "Private synthetic subject"
        controller.draftText = "Private synthetic text"
        do {
            try controller.addDraftAttachments([.init(filename: "private.txt", mimeType: "text/plain", data: Data("private synthetic".utf8))])
        } catch { Issue.record("Synthetic attachment should be accepted") }
        #expect(controller.draftAttachments.count == 1)
        let send = Task { await controller.sendDraft() }
        await provider.waitForSend()
        if suspend { controller.setSuspended(true) } else { controller.setEnabled(false) }
        #expect(!controller.isComposing && !controller.isSending)
        #expect(controller.draftTo.isEmpty && controller.draftBcc.isEmpty)
        #expect(controller.draftSubject.isEmpty && controller.draftText.isEmpty)
        #expect(controller.draftAttachments.isEmpty)
        #expect(controller.composeAccountID == nil && controller.replyingTo == nil)
        await provider.finishSend()
        await send.value
        #expect(controller.actionStatus == nil)
        #expect(controller.composeProblem == nil)
        #expect(await provider.sentDrafts.count == 1)
        controller.setEnabled(false)
    }

    @Test func invalidRecipientsNeverReachProviderAndDraftRemainsEditable() async {
        let provider = ActionMailProvider(account: makeAccount("sender"))
        let controller = makeController([provider])
        controller.setEnabled(true)
        controller.startCompose()
        controller.draftTo = "recipient@example.invalid\r\nBcc: injected@example.invalid"
        controller.draftText = "Synthetic body"
        await controller.sendDraft()
        #expect(await provider.sentDrafts.isEmpty)
        #expect(controller.isComposing)
        #expect(controller.composeProblem != nil)
        #expect(controller.draftText == "Synthetic body")
        controller.setEnabled(false)
    }

    @Test func invalidAttachmentCannotPartiallyModifyDraft() throws {
        let provider = ActionMailProvider(account: makeAccount("sender"))
        let controller = makeController([provider])
        controller.setEnabled(true)
        controller.startCompose()
        let original = NativeMailOutgoingAttachment(filename: "original.txt", mimeType: "text/plain", data: Data("original".utf8))
        try controller.addDraftAttachments([original])
        let safe = NativeMailOutgoingAttachment(filename: "safe.txt", mimeType: "text/plain", data: Data("safe".utf8))
        let invalid = NativeMailOutgoingAttachment(filename: "../private.txt", mimeType: "text/plain", data: Data())
        #expect(throws: NativeMailFailure.invalidDraft) { try controller.addDraftAttachments([safe, invalid]) }
        #expect(controller.draftAttachments == [original])
        controller.setEnabled(false)
        #expect(controller.draftAttachments.isEmpty)
    }

    @Test func replyUsesReplyToAndOriginalThreadOnlyOnItsAccount() async {
        let one = makeAccount("one"), two = makeAccount("two")
        let message = makeSummary(one, "message", replyTo: "Support <reply@example.invalid>")
        let first = ActionMailProvider(account: one, messages: [message])
        let second = ActionMailProvider(account: two)
        let controller = makeController([first, second])
        controller.setEnabled(true)
        await controller.refresh()
        controller.startCompose(replyingTo: message)
        #expect(controller.draftTo == "reply@example.invalid")
        #expect(controller.draftSubject == "Re: Synthetic subject")
        #expect(controller.replyingTo == message.key)
        controller.draftText = "Synthetic reply"
        controller.composeAccountID = two.id
        await controller.sendDraft()
        #expect(await first.sentDrafts.isEmpty)
        #expect(await second.sentDrafts.isEmpty)
        controller.composeAccountID = one.id
        await controller.sendDraft()
        let sent = await first.sentDrafts.first
        #expect(sent?.to == ["reply@example.invalid"])
        #expect(sent?.inReplyTo == "<original@example.invalid>")
        #expect(sent?.replyingTo == message.key)
        #expect(await second.sentDrafts.isEmpty)
        controller.setEnabled(false)
    }

    @Test func replyResolvesCanonicalInboxMetadataInsteadOfSuppliedSpoof() async {
        let account = makeAccount("one")
        let original = makeSummary(account, "message", replyTo: "real@example.invalid")
        let provider = ActionMailProvider(account: account, messages: [original])
        let controller = makeController([provider])
        controller.setEnabled(true)
        await controller.refresh()
        let spoofed = NativeMailSummary(key: original.key, sender: "spoof@example.invalid", subject: "Fake subject",
                                        receivedAt: original.receivedAt, rfcMessageID: "fake@example.invalid",
                                        replyTo: "attacker@example.invalid")
        controller.startCompose(replyingTo: spoofed)
        #expect(controller.draftTo == "real@example.invalid")
        #expect(controller.draftSubject == "Re: Synthetic subject")
        controller.draftText = "Synthetic reply"
        await controller.sendDraft()
        #expect(await provider.sentDrafts.first?.inReplyTo == "<original@example.invalid>")
        controller.setEnabled(false)
    }

    @Test(arguments: ["read", "archive", "trash"])
    func mutationRequiresInboxMembershipAndKeepsEqualRemoteIDsAccountScoped(actionName: String) async {
        let one = makeAccount("one"), two = makeAccount("two")
        let firstMessage = makeSummary(one, "same-id"), secondMessage = makeSummary(two, "same-id")
        let first = ActionMailProvider(account: one, messages: [firstMessage])
        let second = ActionMailProvider(account: two, messages: [secondMessage])
        let controller = makeController([first, second])
        controller.setEnabled(true)
        await controller.refresh()
        let action: NativeMailController.MessageAction = actionName == "read" ? .read(true) : (actionName == "archive" ? .archive : .trash)
        await controller.perform(action, on: makeSummary(one, "not-in-inbox"))
        #expect(await first.mutations.isEmpty)
        await controller.perform(action, on: firstMessage)
        #expect(await first.mutations == [ActionMailMutation(name: actionName, key: firstMessage.key)])
        #expect(await second.mutations.isEmpty)
        #expect(controller.messages.contains(secondMessage))
        if actionName == "read" {
            #expect(controller.messages.first(where: { $0.key == firstMessage.key })?.isUnread == false)
            #expect(controller.messages.first(where: { $0.key == secondMessage.key })?.isUnread == true)
        } else {
            #expect(!controller.messages.contains(where: { $0.key == firstMessage.key }))
            await controller.perform(action, on: firstMessage)
            #expect(await first.mutations.count == 1)
        }
        controller.setEnabled(false)
        await controller.perform(action, on: secondMessage)
        #expect(await second.mutations.isEmpty)
    }

    @Test func lateMutationCompletionCannotRestoreStatusOrContentAfterLock() async {
        let account = makeAccount("one")
        let message = makeSummary(account, "message")
        let provider = ActionMailProvider(account: account, messages: [message])
        await provider.holdMutating()
        let controller = makeController([provider])
        controller.setEnabled(true)
        await controller.refresh()
        let operation = Task { await controller.perform(.archive, on: message) }
        await provider.waitForMutation()
        #expect(controller.isMutating)
        controller.setSuspended(true)
        await provider.finishMutation()
        await operation.value
        #expect(controller.messages.isEmpty)
        #expect(controller.actionStatus == nil)
        #expect(controller.problem == nil)
        #expect(!controller.isMutating)
        controller.setEnabled(false)
    }

    @Test(arguments: [false, true])
    func staleAttachmentMetadataCannotReplaceAnotherReaderOrReturnAfterLock(lock: Bool) async {
        let account = makeAccount("one")
        let first = makeSummary(account, "first"), second = makeSummary(account, "second")
        let provider = ActionMailProvider(account: account, messages: [first, second])
        await provider.holdAttachments(for: first.key)
        let controller = makeController([provider])
        controller.setEnabled(true)
        await controller.refresh()
        controller.read(first)
        await provider.waitForAttachments()
        if lock { controller.setSuspended(true) }
        else {
            controller.read(second)
            await settle { !controller.isReading && controller.selectedMessage?.key == second.key }
        }
        await provider.finishAttachments(for: first.key)
        for _ in 0..<40 { await Task.yield() }
        if lock {
            #expect(controller.selectedAttachments.isEmpty)
            #expect(controller.selectedMessage == nil)
            #expect(controller.selectedContent == nil)
        } else {
            #expect(controller.selectedMessage?.key == second.key)
            #expect(controller.selectedAttachments.map(\.key) == [second.key])
        }
        controller.setEnabled(false)
    }

    @Test func foreignAttachmentMetadataIsRejectedBeforeItCanBeOfferedForDownload() async {
        let account = makeAccount("one")
        let message = makeSummary(account, "message")
        let provider = ActionMailProvider(account: account, messages: [message])
        await provider.setForeignAttachmentKey(NativeMailMessageKey(accountID: UUID(), remoteID: "foreign"))
        let controller = makeController([provider])
        controller.setEnabled(true)
        await controller.refresh()
        controller.read(message)
        await settle { !controller.isReading }
        #expect(controller.selectedAttachments.isEmpty)
        controller.setEnabled(false)
    }

    private func makeController(_ providers: [ActionMailProvider]) -> NativeMailController {
        let accounts = providers.map(\.account)
        let indexed = Dictionary(uniqueKeysWithValues: providers.map { ($0.account.id, $0) })
        return NativeMailController(auth: ActionMailAuth(accounts: accounts), providerFactory: { indexed[$0.id]! }, automaticPolling: false)
    }
    private func makeAccount(_ name: String) -> NativeMailAccount {
        NativeMailAccount(service: .google, remoteID: name, address: "\(name)@example.invalid")
    }
    private func makeSummary(_ account: NativeMailAccount, _ remote: String, replyTo: String? = nil) -> NativeMailSummary {
        NativeMailSummary(key: .init(accountID: account.id, remoteID: remote), sender: "Sender <from@example.invalid>",
                          subject: "Synthetic subject", receivedAt: .now.addingTimeInterval(-60), isUnread: true,
                          rfcMessageID: "original@example.invalid", replyTo: replyTo)
    }
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition(), "Controller operation did not settle")
    }
}

private struct ActionMailMutation: Equatable, Sendable { let name: String; let key: NativeMailMessageKey }

@MainActor private final class ActionMailAuth: NativeMailAuthenticating {
    let availableServices: [NativeMailService] = [.google]
    var accounts: [NativeMailAccount]
    init(accounts: [NativeMailAccount]) { self.accounts = accounts }
    func restoreAccounts() throws -> [NativeMailAccount] { accounts }
    func connect(service: NativeMailService, replacing: NativeMailAccount?) async throws -> NativeMailAccount { throw MailAuthFailure.cancelled }
    func accessToken(for account: NativeMailAccount, forceRefresh: Bool) async throws -> String { "synthetic-token" }
    func disconnect(account: NativeMailAccount) async throws { accounts.removeAll { $0.id == account.id } }
    func cancel() {}
}

private actor ActionMailProvider: NativeMailProvider {
    nonisolated let account: NativeMailAccount
    private let messages: [NativeMailSummary]
    private(set) var sentDrafts: [NativeMailDraft] = []
    private(set) var mutations: [ActionMailMutation] = []
    private var holdSend = false
    private var holdMutation = false
    private var attachmentKey: NativeMailMessageKey?
    private var foreignAttachmentKey: NativeMailMessageKey?
    private var sendContinuation: CheckedContinuation<NativeMailSendReceipt, Error>?
    private var mutationContinuation: CheckedContinuation<Void, Error>?
    private var attachmentContinuation: CheckedContinuation<[NativeMailAttachment], Error>?
    private var sendWaiter: CheckedContinuation<Void, Never>?
    private var mutationWaiter: CheckedContinuation<Void, Never>?
    private var attachmentWaiter: CheckedContinuation<Void, Never>?
    init(account: NativeMailAccount, messages: [NativeMailSummary] = []) { self.account = account; self.messages = messages }
    func bootstrap(pageToken: String?) async throws -> NativeMailPage { NativeMailPage(messages: messages, cursor: "baseline") }
    func changes(cursor: String, pageToken: String?) async throws -> NativeMailPage { NativeMailPage(messages: [], cursor: "next") }
    func fetchContent(for key: NativeMailMessageKey) async throws -> NativeMailContent { NativeMailContent(key: key, text: "Synthetic body") }
    func holdSending() { holdSend = true }
    func holdMutating() { holdMutation = true }
    func holdAttachments(for key: NativeMailMessageKey) { attachmentKey = key }
    func setForeignAttachmentKey(_ key: NativeMailMessageKey) { foreignAttachmentKey = key }
    func send(_ draft: NativeMailDraft) async throws -> NativeMailSendReceipt {
        sentDrafts.append(draft)
        if holdSend {
            return try await withCheckedThrowingContinuation { continuation in
                sendContinuation = continuation; sendWaiter?.resume(); sendWaiter = nil
            }
        }
        return NativeMailSendReceipt(remoteID: "synthetic-sent")
    }
    func setRead(_ isRead: Bool, for key: NativeMailMessageKey) async throws { try await mutate("read", key) }
    func archive(_ key: NativeMailMessageKey) async throws { try await mutate("archive", key) }
    func trash(_ key: NativeMailMessageKey) async throws { try await mutate("trash", key) }
    private func mutate(_ action: String, _ key: NativeMailMessageKey) async throws {
        mutations.append(ActionMailMutation(name: action, key: key))
        if holdMutation {
            try await withCheckedThrowingContinuation { continuation in
                mutationContinuation = continuation; mutationWaiter?.resume(); mutationWaiter = nil
            }
        }
    }
    func attachments(for key: NativeMailMessageKey) async throws -> [NativeMailAttachment] {
        if key == attachmentKey {
            return try await withCheckedThrowingContinuation { continuation in
                attachmentContinuation = continuation; attachmentWaiter?.resume(); attachmentWaiter = nil
            }
        }
        return [attachment(for: foreignAttachmentKey ?? key)]
    }
    private func attachment(for key: NativeMailMessageKey) -> NativeMailAttachment {
        NativeMailAttachment(key: key, remoteID: "attachment-\(key.remoteID)", filename: "synthetic.txt", mimeType: "text/plain", byteCount: 12)
    }
    func waitForSend() async {
        if sendContinuation != nil { return }; await withCheckedContinuation { sendWaiter = $0 }
    }
    func waitForMutation() async {
        if mutationContinuation != nil { return }; await withCheckedContinuation { mutationWaiter = $0 }
    }
    func waitForAttachments() async {
        if attachmentContinuation != nil { return }; await withCheckedContinuation { attachmentWaiter = $0 }
    }
    func finishSend() { sendContinuation?.resume(returning: NativeMailSendReceipt(remoteID: "synthetic-sent")); sendContinuation = nil }
    func finishMutation() { mutationContinuation?.resume(); mutationContinuation = nil }
    func finishAttachments(for key: NativeMailMessageKey) { attachmentContinuation?.resume(returning: [attachment(for: key)]); attachmentContinuation = nil }
}
