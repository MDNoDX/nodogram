//  Talks to Nodogram Vault — the local service behind the user's Telegram
//  Business bot (vault/ in this repository). It runs even when Nodogram is
//  closed, and Telegram queues the bot's updates for 24 hours, so messages
//  deleted while the Mac was asleep still arrive here with their content.
//
//  The service listens on 127.0.0.1 only; the port and bearer token come
//  from ~/Library/Application Support/Nodogram/vault.env (owner-only).

import Foundation

struct VaultClient: Sendable {
    let base: URL
    let token: String

    struct Status: Decodable, Sendable {
        struct Stats: Decodable, Sendable { let total: Int; let deleted: Int; let edited: Int; let chats: Int }
        let ok: Bool
        let stats: Stats
        let connections: Int
    }

    struct Item: Decodable, Sendable {
        let chatId: Int64
        let messageId: Int64
        let chatTitle: String
        let senderId: Int64?
        let senderName: String
        let isOutgoing: Bool
        let sentAt: Date
        let text: String
        let mediaKind: String?
        let localPath: String?
        let editedAt: Date?
        let deletedAt: Date?
    }

    struct Version: Decodable, Sendable { let version: Int; let text: String; let at: Date }

    static let envFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nodogram/vault.env")

    /// Nil when the Vault is not set up on this Mac.
    static func fromEnvironment() -> VaultClient? {
        guard let text = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        guard let token = values["VAULT_API_TOKEN"], let port = Int(values["VAULT_PORT"] ?? "47823"),
              let base = URL(string: "http://127.0.0.1:\(port)") else { return nil }
        return VaultClient(base: base, token: token)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = fractionalISO.date(from: s) ?? plainISO.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: "bad date \(s)")
        }
        return decoder
    }()

    // ISO8601DateFormatter is thread-safe once configured.
    nonisolated(unsafe) private static let fractionalISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plainISO = ISO8601DateFormatter()

    static func iso(_ date: Date) -> String { fractionalISO.string(from: date) }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decoder.decode(T.self, from: data)
    }

    func status() async throws -> Status { try await get("/v1/status") }

    func deleted(since: Date?) async throws -> [Item] {
        struct R: Decodable { let messages: [Item] }
        let r: R = try await get("/v1/deleted", query: [URLQueryItem(name: "limit", value: "500")]
            + (since.map { [URLQueryItem(name: "since", value: Self.iso($0))] } ?? []))
        return r.messages
    }

    func edited(since: Date?) async throws -> [Item] {
        struct R: Decodable { let messages: [Item] }
        let r: R = try await get("/v1/edited", query: [URLQueryItem(name: "limit", value: "500")]
            + (since.map { [URLQueryItem(name: "since", value: Self.iso($0))] } ?? []))
        return r.messages
    }

    func versions(chatID: Int64, messageID: Int64) async throws -> [Version] {
        struct R: Decodable { let versions: [Version] }
        let r: R = try await get("/v1/versions/\(chatID)/\(messageID)")
        return r.versions
    }
}
