//  Builds the JSON the bot asks Nodogram for over the local control server:
//  live search, a person's profile and shared-group activity, and your own
//  account picture. Everything here is what Telegram already shows you —
//  your chats, your groups, and the public side of people you share them with.

import Foundation
import NodogramDomain

extension AppModel {

    /// Routes a control-server path to a JSON payload. Returns nil for unknown
    /// paths. Runs on the main actor (TDLib work is awaited inside).
    func controlResponse(path: String, query: [String: String]) async -> [String: Any]? {
        switch path {
        case "/ping":
            return ["ok": true, "app": "nodogram", "signedIn": myUserID != nil]
        case "/myinfo":
            return await myInfoPayload()
        case "/search":
            return await searchPayload(query["q"] ?? "")
        case "/info":
            return await personInfoPayload(query["q"] ?? "")
        case "/resolve":
            return await resolvePayload(query["q"] ?? "")
        default:
            return nil
        }
    }

    private func myInfoPayload() async -> [String: Any] {
        let groups = myGroups()
        func summarise(_ g: GroupSummary) -> [String: Any] {
            ["id": g.id.rawValue, "title": g.title, "isChannel": g.isChannel,
             "role": g.role.rawValue, "members": g.memberCount]
        }
        let mine = groups.filter { $0.role != .left }
        let left = groups.filter { $0.role == .left }
        var usernames: [String] = []
        if let me = myUserID, let profile = await gatewayProfile(me) {
            usernames = profile.usernames
        }
        return [
            "ok": true,
            "groups": mine.filter { !$0.isChannel }.map(summarise),
            "channels": mine.filter { $0.isChannel }.map(summarise),
            "owned": mine.filter { $0.role == .owner }.map(summarise),
            "left": left.map(summarise),
            "usernames": usernames,
            "stats": ["groups": mine.filter { !$0.isChannel }.count,
                      "channels": mine.filter { $0.isChannel }.count,
                      "owned": mine.filter { $0.role == .owner }.count,
                      "left": left.count]
        ]
    }

    private func searchPayload(_ q: String) async -> [String: Any] {
        guard !q.isEmpty, let gateway else { return ["ok": true, "chats": [], "messages": []] }
        let chatIDs = await gateway.searchGlobalChats(q)
        var chats: [[String: Any]] = []
        for id in chatIDs.prefix(20) {
            var chat = chatsByID[id]
            if chat == nil { chat = await gateway.resolveChat(id) }
            guard let chat else { continue }
            chats.append(["id": id.rawValue, "title": chat.title,
                          "kind": String(describing: chat.kind), "members": chat.memberCount])
        }
        let msgs = (try? await gateway.searchGlobalMessages(q, limit: 20).messages) ?? []
        let messages = msgs.prefix(20).map { m in
            ["chatId": m.chatID.rawValue, "chat": chatTitle(m.chatID),
             "text": m.text, "date": Int(m.date.timeIntervalSince1970)] as [String: Any]
        }
        return ["ok": true, "chats": chats, "messages": messages]
    }

    private func resolvePayload(_ q: String) async -> [String: Any] {
        guard !q.isEmpty, let gateway else { return ["ok": false, "error": "empty query"] }
        guard let user = await gateway.resolvePerson(q) else {
            return ["ok": false, "found": false, "error": "could not resolve that person"]
        }
        let brief = await gateway.personBrief(user)
        return ["ok": true, "found": true, "userId": user.rawValue,
                "title": brief?.title ?? "User", "username": brief?.username ?? ""]
    }

    private func personInfoPayload(_ q: String) async -> [String: Any] {
        guard !q.isEmpty, let gateway else { return ["ok": false, "error": "empty query"] }
        // Resolve across the user's own chats, contacts, and public usernames.
        guard let user = await gateway.resolvePerson(q) else {
            return ["ok": false, "error": "could not resolve that person"]
        }

        async let profileTask = gateway.personProfile(user)
        async let commonTask = gateway.groupsInCommon(user)
        let profile = await profileTask
        let common = await commonTask

        var groups: [[String: Any]] = []
        var theirMessages: [[String: Any]] = []
        for chat in common.prefix(15) {
            let title = chatTitle(chat)
            let page = await gateway.messages(from: user, in: chat, limit: 5)
            groups.append(["id": chat.rawValue, "title": title, "theirMessages": page.total])
            for m in page.messages.prefix(3) {
                theirMessages.append(["group": title, "text": m.text,
                                      "date": Int(m.date.timeIntervalSince1970)])
            }
        }
        let identities = identityHistory(user).map { id in
            ["name": id.name, "usernames": id.usernames] as [String: Any]
        }
        var payload: [String: Any] = [
            "ok": true,
            "userId": user.rawValue,
            "commonGroups": groups,
            "theirMessages": Array(theirMessages.prefix(25)),
            "identityHistory": identities
        ]
        if let p = profile {
            payload["profile"] = [
                "name": [p.firstName, p.lastName].filter { !$0.isEmpty }.joined(separator: " "),
                "usernames": p.usernames,
                "bio": p.bio,
                "isMutualContact": p.isMutualContact,
                "isContact": p.isContact,
                "isPremium": p.isPremium,
                "isBot": p.isBot,
                "groupsInCommon": p.groupsInCommonCount
            ]
        }
        return payload
    }
}
