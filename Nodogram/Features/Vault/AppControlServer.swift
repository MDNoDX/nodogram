//  A tiny HTTP server on 127.0.0.1 that lets the Nodogram Vault bot ask the
//  running app for things only a logged-in session can answer: live search,
//  a person's shared-group activity, and your own account picture.
//
//  Loopback only, Bearer-token authenticated with the same secret as the Vault
//  (VAULT_API_TOKEN). GET only, small JSON responses, one request per
//  connection. It exists only while the app runs; the bot falls back to its
//  own stored data when the app is closed.

import Foundation
import Network

@MainActor
public final class AppControlServer {
    public static let shared = AppControlServer()
    private var listener: NWListener?
    private let port: NWEndpoint.Port = 47824
    private var token: String?

    public func start(model: AppModel) {
        guard listener == nil else { return }
        guard let client = VaultClient.fromEnvironment() else { return }  // no Vault set up → no server
        token = client.token
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                Task { @MainActor in self?.handle(connection, model: model) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            NSLog("[nodogram] control server failed to start: \(error.localizedDescription)")
        }
    }

    private func handle(_ connection: NWConnection, model: AppModel) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel(); return
            }
            Task { @MainActor in
                let response = await self.respond(to: request, model: model)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    private func respond(to request: String, model: AppModel) async -> Data {
        let lines = request.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return Self.http(401, ["error": "bad request"]) }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return Self.http(405, ["error": "GET only"]) }

        // Bearer auth.
        let auth = lines.first { $0.lowercased().hasPrefix("authorization:") }
            .map { $0.split(separator: " ").last.map(String.init) ?? "" } ?? ""
        guard let token, auth == token else { return Self.http(401, ["error": "unauthorized"]) }

        // Path and query.
        let target = String(parts[1])
        let comps = URLComponents(string: "http://127.0.0.1\(target)")
        let path = comps?.path ?? target
        var query: [String: String] = [:]
        for item in comps?.queryItems ?? [] { query[item.name] = item.value ?? "" }

        guard let payload = await model.controlResponse(path: path, query: query) else {
            return Self.http(404, ["error": "unknown endpoint"])
        }
        return Self.http(200, payload)
    }

    private static func http(_ status: Int, _ body: [String: Any]) -> Data {
        let json = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(json.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data(head.utf8) + json
    }
}
