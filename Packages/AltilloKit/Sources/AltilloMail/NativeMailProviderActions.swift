import Foundation

extension GoogleNativeMailProvider {
    public func send(_ draft: NativeMailDraft) async throws -> NativeMailSendReceipt {
        guard account.service == .google else { throw NativeMailFailure.invalidResponse }
        try NativeMailMIME.validateDraft(draft)
        var outgoing = draft
        var payload: [String: Any] = [:]
        // Gmail requires both RFC reply headers and threadId to append to an existing thread.
        var replyID: String?
        if let key = draft.replyingTo {
            _ = try operationURL(key)
            replyID = key.remoteID
        } else if let reply = draft.inReplyTo {
            let list = try nativeMailDecode(SendGmailList.self, from: await api.get(try nativeMailURL(Self.base + "/messages", query: [
                .init(name: "q", value: "rfc822msgid:" + reply), .init(name: "maxResults", value: "1")
            ])))
            replyID = list.messages?.first?.id
        }
        if let id = replyID {
            let message = try nativeMailDecode(SendGmailMessage.self, from: await api.get(try nativeMailURL(Self.base + "/messages/" + nativeMailPathComponent(id), query: [.init(name: "format", value: "metadata"), .init(name: "metadataHeaders", value: "Message-ID")])))
            guard message.id == id else { throw NativeMailFailure.invalidResponse }
            if let thread = message.threadId { payload["threadId"] = thread }
            if outgoing.inReplyTo == nil {
                outgoing.inReplyTo = message.payload?.headers?.first { $0.name.caseInsensitiveCompare("Message-ID") == .orderedSame }?.value
            }
        }
        let mime = try NativeMailMIME.encode(draft: outgoing, from: account.address, includeBcc: true)
        payload["raw"] = nativeMailBase64URL(mime)
        let body = try JSONSerialization.data(withJSONObject: payload)
        let response = try await api.request(try nativeMailURL(Self.base + "/messages/send"), method: "POST", body: body, isSend: true)
        guard let receipt = try? JSONDecoder().decode(SendGmailMessage.self, from: response), !receipt.id.isEmpty else { throw NativeMailFailure.deliveryUncertain }
        return .init(remoteID: receipt.id)
    }

    public func setRead(_ isRead: Bool, for key: NativeMailMessageKey) async throws {
        try await modify(key, values: [isRead ? "removeLabelIds" : "addLabelIds": ["UNREAD"]])
    }
    public func archive(_ key: NativeMailMessageKey) async throws { try await modify(key, values: ["removeLabelIds": ["INBOX"]]) }
    public func trash(_ key: NativeMailMessageKey) async throws {
        let url = try operationURL(key, suffix: "/trash")
        _ = try await api.request(url, method: "POST", body: Data("{}".utf8))
    }
    private func modify(_ key: NativeMailMessageKey, values: [String: [String]]) async throws {
        let url = try operationURL(key, suffix: "/modify")
        _ = try await api.request(url, method: "POST", body: JSONEncoder().encode(values))
    }
    private func operationURL(_ key: NativeMailMessageKey, suffix: String = "") throws -> URL {
        guard key.accountID == account.id, account.service == .google else { throw NativeMailFailure.invalidResponse }
        return try nativeMailURL(Self.base + "/messages/" + nativeMailPathComponent(key.remoteID) + suffix)
    }

    public func attachments(for key: NativeMailMessageKey) async throws -> [NativeMailAttachment] {
        let message = try await attachmentMessage(key)
        var result: [NativeMailAttachment] = [], visited = 0
        func visit(_ part: ActionGmailPart, depth: Int) throws {
            visited += 1
            guard depth <= 20, visited <= 200 else { throw NativeMailFailure.invalidResponse }
            if let filename = part.filename, !filename.isEmpty {
                let id = part.body?.attachmentId ?? part.partId.map { "inline:" + $0 }
                if let id, let size = part.body?.size, size >= 0 {
                    result.append(.init(key: key, remoteID: id, filename: NativeMailText.bounded(filename, utf8Limit: 512),
                                        mimeType: part.mimeType ?? "application/octet-stream", byteCount: size))
                }
            }
            for child in part.parts ?? [] { try visit(child, depth: depth + 1) }
        }
        if let part = message.payload { try visit(part, depth: 0) }
        return result
    }
    public func download(_ attachment: NativeMailAttachment) async throws -> Data {
        guard attachment.byteCount >= 0, attachment.byteCount <= NativeMailMIME.attachmentDownloadByteLimit else { throw NativeMailFailure.contentTooLarge }
        _ = try operationURL(attachment.key)
        if attachment.remoteID.hasPrefix("inline:") {
            let partID = String(attachment.remoteID.dropFirst(7))
            let message = try await attachmentMessage(attachment.key)
            var visited = 0
            func find(_ part: ActionGmailPart, depth: Int) throws -> String? {
                visited += 1
                guard depth <= 20, visited <= 200 else { throw NativeMailFailure.invalidResponse }
                if part.partId == partID, part.filename?.isEmpty == false { return part.body?.data }
                for child in part.parts ?? [] { if let data = try find(child, depth: depth + 1) { return data } }
                return nil
            }
            guard let payload = message.payload, let value = try find(payload, depth: 0) else { throw NativeMailFailure.messageMissing }
            return try nativeMailAttachmentData(value)
        }
        let url = try operationURL(attachment.key, suffix: "/attachments/" + nativeMailPathComponent(attachment.remoteID))
        let body = try nativeMailDecode(ActionGmailBody.self, from: await api.get(url, byteLimit: 29 * 1_048_576))
        guard let value = body.data else { throw NativeMailFailure.invalidResponse }
        return try nativeMailAttachmentData(value)
    }
    private func attachmentMessage(_ key: NativeMailMessageKey) async throws -> ActionGmailMessage {
        var components = URLComponents(url: try operationURL(key), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "format", value: "full")]
        let message = try nativeMailDecode(ActionGmailMessage.self, from: await api.get(components.url!, byteLimit: 29 * 1_048_576))
        guard message.id == key.remoteID else { throw NativeMailFailure.invalidResponse }
        return message
    }
}

extension MicrosoftNativeMailProvider {
    public func send(_ draft: NativeMailDraft) async throws -> NativeMailSendReceipt {
        guard account.service == .microsoft else { throw NativeMailFailure.invalidResponse }
        let mime = try NativeMailMIME.encode(draft: draft, from: account.address, includeBcc: true)
        let body = Data(mime.base64EncodedString().utf8)
        if let reply = draft.replyingTo { _ = try operationURL(reply) }
        if body.count <= 4_000_000, draft.replyingTo == nil {
            _ = try await api.request(try nativeMailURL(Self.base + "/me/sendMail"), method: "POST", body: body,
                                      contentType: "text/plain", isSend: true)
            // A 202 acknowledges submission; it is not a guarantee of final delivery.
            return .init()
        }
        return try await sendThroughDraft(draft)
    }

    private func sendThroughDraft(_ draft: NativeMailDraft) async throws -> NativeMailSendReceipt {
        // Build a small draft first; attachments are added individually to avoid Graph's 4 MB request limit.
        var skeleton = draft; skeleton.attachments = []
        let skeletonBody = Data(try NativeMailMIME.encode(draft: skeleton, from: account.address, includeBcc: true).base64EncodedString().utf8)
        let createURL: URL
        if let reply = draft.replyingTo { createURL = try operationURL(reply, suffix: "/createReply") }
        else { createURL = try nativeMailURL(Self.base + "/me/messages") }
        let raw = try await api.request(createURL, method: "POST", body: skeletonBody, contentType: "text/plain",
                                        headers: ["Prefer": "IdType=\"ImmutableId\""])
        let created = try nativeMailDecode(SendGmailID.self, from: raw)
        let key = NativeMailMessageKey(accountID: account.id, remoteID: created.id)
        _ = try operationURL(key)
        // If upload fails, an UNSENT provider draft may remain. Never retry or send it in the background.
        for attachment in draft.attachments {
            if attachment.data.count < 3_000_000 {
                let object: [String: Any] = ["@odata.type": "#microsoft.graph.fileAttachment", "name": attachment.filename,
                                             "contentType": attachment.mimeType, "contentBytes": attachment.data.base64EncodedString()]
                let data = try JSONSerialization.data(withJSONObject: object)
                _ = try await api.request(operationURL(key, suffix: "/attachments"), method: "POST", body: data,
                                          headers: ["Prefer": "IdType=\"ImmutableId\""])
            } else { try await upload(attachment, to: key) }
        }
        _ = try await api.request(operationURL(key, suffix: "/send"), method: "POST", body: Data(), isSend: true)
        return .init(remoteID: created.id)
    }

    private func upload(_ attachment: NativeMailOutgoingAttachment, to key: NativeMailMessageKey) async throws {
        let object: [String: Any] = ["AttachmentItem": ["attachmentType": "file", "name": attachment.filename,
                                                       "contentType": attachment.mimeType, "size": attachment.data.count]]
        let raw = try await api.request(operationURL(key, suffix: "/attachments/createUploadSession"), method: "POST",
                                        body: JSONSerialization.data(withJSONObject: object))
        let session = try nativeMailDecode(ActionGraphUpload.self, from: raw)
        guard let url = URL(string: session.uploadUrl), NativeMailAPI.isSafe(url, hosts: ["outlook.office.com"]),
              url.path.lowercased().hasPrefix("/api/"), url.path.lowercased().contains("attachmentsessions("),
              session.nextExpectedRanges == nil || Self.expectsUploadOffset(session.nextExpectedRanges!, offset: 0) else { throw NativeMailFailure.invalidResponse }
        // uploadUrl contains its own short-lived capability. NEVER forward the Graph bearer token to it.
        var offset = 0
        while offset < attachment.data.count {
            try Task.checkCancellation()
            let end = min(offset + 3_276_800, attachment.data.count)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
            request.httpMethod = "PUT"
            request.httpBody = attachment.data.subdata(in: offset..<end)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(String(end - offset), forHTTPHeaderField: "Content-Length")
            request.setValue("bytes \(offset)-\(end - 1)/\(attachment.data.count)", forHTTPHeaderField: "Content-Range")
            let response: NativeMailHTTPResponse
            do { response = try await api.transport.send(request, byteLimit: 262_144) }
            catch is CancellationError { throw CancellationError() }
            catch { throw NativeMailFailure.unavailable }
            guard response.data.count <= 262_144 else { throw NativeMailFailure.contentTooLarge }
            if end == attachment.data.count {
                guard response.status == 201 else { throw NativeMailFailure.unavailable }
            } else {
                guard response.status == 200 else { throw NativeMailFailure.unavailable }
                let progress = try nativeMailDecode(ActionGraphUploadProgress.self, from: response.data)
                guard Self.expectsUploadOffset(progress.nextExpectedRanges, offset: end) else { throw NativeMailFailure.invalidResponse }
            }
            offset = end
        }
    }

    private static func expectsUploadOffset(_ ranges: [String], offset: Int) -> Bool {
        // Accept Outlook's documented offset and the generic uploadSession open-range representation.
        ranges == [String(offset)] || ranges == [String(offset) + "-"]
    }

    public func setRead(_ isRead: Bool, for key: NativeMailMessageKey) async throws {
        _ = try await api.request(operationURL(key), method: "PATCH", body: JSONEncoder().encode(["isRead": isRead]), headers: ["Prefer": "IdType=\"ImmutableId\""])
    }
    public func archive(_ key: NativeMailMessageKey) async throws { try await move(key, destination: "archive") }
    public func trash(_ key: NativeMailMessageKey) async throws { try await move(key, destination: "deleteditems") }
    private func move(_ key: NativeMailMessageKey, destination: String) async throws {
        _ = try await api.request(operationURL(key, suffix: "/move"), method: "POST",
                                  body: JSONEncoder().encode(["destinationId": destination]), headers: ["Prefer": "IdType=\"ImmutableId\""])
    }
    private func operationURL(_ key: NativeMailMessageKey, suffix: String = "") throws -> URL {
        guard key.accountID == account.id, account.service == .microsoft else { throw NativeMailFailure.invalidResponse }
        return try nativeMailURL(Self.base + "/me/messages/" + nativeMailPathComponent(key.remoteID) + suffix)
    }
    public func attachments(for key: NativeMailMessageKey) async throws -> [NativeMailAttachment] {
        var components = URLComponents(url: try operationURL(key, suffix: "/attachments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "$select", value: "id,name,contentType,size"), .init(name: "$top", value: "100")]
        let expectedPath = components.url!.path
        var next = components.url, result: [NativeMailAttachment] = [], seen = Set<String>(), pages = 0
        while let url = next {
            pages += 1
            guard pages <= 5, result.count < 500, NativeMailAPI.isSafe(url, hosts: ["graph.microsoft.com"]), url.path == expectedPath else { throw NativeMailFailure.invalidResponse }
            let page = try nativeMailDecode(ActionGraphAttachments.self, from: await api.get(url, headers: ["Prefer": "IdType=\"ImmutableId\""]))
            for item in page.value {
                guard item.kind == "#microsoft.graph.fileAttachment" else { continue }
                guard !item.id.isEmpty, item.size >= 0 else { throw NativeMailFailure.invalidResponse }
                if seen.insert(item.id).inserted {
                    result.append(.init(key: key, remoteID: item.id, filename: NativeMailText.bounded(item.name, utf8Limit: 512), mimeType: item.contentType ?? "application/octet-stream", byteCount: item.size))
                }
            }
            if let link = page.nextLink { guard let url = URL(string: link) else { throw NativeMailFailure.invalidResponse }; next = url }
            else { next = nil }
        }
        return result
    }
    public func download(_ attachment: NativeMailAttachment) async throws -> Data {
        guard attachment.byteCount >= 0, attachment.byteCount <= NativeMailMIME.attachmentDownloadByteLimit else { throw NativeMailFailure.contentTooLarge }
        return try await api.get(operationURL(attachment.key, suffix: "/attachments/" + nativeMailPathComponent(attachment.remoteID) + "/$value"),
                                 byteLimit: NativeMailMIME.attachmentDownloadByteLimit, headers: ["Prefer": "IdType=\"ImmutableId\""])
    }
}

private struct SendGmailList: Decodable { let messages: [SendGmailID]? }
private struct SendGmailID: Decodable { let id: String }
private struct SendGmailMessage: Decodable {
    let id: String; let threadId: String?; let payload: Payload?
    struct Payload: Decodable { let headers: [Header]? }
    struct Header: Decodable { let name: String; let value: String }
}
private struct ActionGmailMessage: Decodable { let id: String; let payload: ActionGmailPart? }
private struct ActionGmailPart: Decodable {
    let partId: String?; let filename: String?; let mimeType: String?; let body: ActionGmailBody?; let parts: [ActionGmailPart]?
}
private struct ActionGmailBody: Decodable { let attachmentId: String?; let size: Int?; let data: String? }
private struct ActionGraphAttachments: Decodable {
    let value: [Item]; let nextLink: String?
    enum CodingKeys: String, CodingKey { case value; case nextLink = "@odata.nextLink" }
    struct Item: Decodable {
        let id: String; let name: String; let contentType: String?; let size: Int; let kind: String
        enum CodingKeys: String, CodingKey { case id, name, contentType, size; case kind = "@odata.type" }
    }
}

private struct ActionGraphUpload: Decodable { let uploadUrl: String; let nextExpectedRanges: [String]? }
private struct ActionGraphUploadProgress: Decodable { let nextExpectedRanges: [String] }
