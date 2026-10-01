//  Nodogram — TDLib verification probe
//
//  The cheapest smoke test that a pinned TDLib actually loads and reports
//  itself. Run after any dependency bump (see Documentation/UPSTREAM.md §3):
//
//      swift run --package-path Tools/tdlib-probe tdlib-probe
//
//  This file is a miniature of the real Telegram gateway, and exists partly to
//  keep that pattern honest. Three constraints it demonstrates:
//
//  1. `TDLibKit.TDLibClient` is NOT Sendable. Calling one of its `nonisolated
//     async` methods from any isolated context fails to compile under Swift 6
//     ("sending value of non-Sendable type 'TDLibClient'"). An `actor` does not
//     fix this — the call still sends the client out of the actor's domain.
//     The client must be *confined* inside one Sendable-by-contract type whose
//     methods return only Sendable values. See ARCHITECTURE.md §1.3.
//
//  2. That confinement is sound because of TDLib's documented C contract
//     (td/telegram/td_json_client.h): `td_send` may be called from any thread,
//     while `td_receive` has exactly one owner — here, TDLibClientManager's.
//
//  3. The file must NOT be called `main.swift`, because `@main` is illegal in a
//     module containing top-level code.

import Foundation
import TDLibKit

/// The single point where TDLib is touched.
///
/// `@unchecked Sendable` is deliberate and justified by constraint 2 above: we
/// only ever *send* from arbitrary tasks, which TDLib documents as thread-safe,
/// and the one receive loop is owned by `TDLibClientManager`.
private final class ProbeGateway: @unchecked Sendable {
    private let manager: TDLibClientManager
    private let client: TDLibClient

    init() {
        manager = TDLibClientManager()
        // `createClient` also activates the client by sending getOption("version")
        // itself, so updates begin flowing immediately.
        client = manager.createClient { _, _ in }
    }

    /// Returns a plain `String` — a Sendable value — so the non-Sendable client
    /// never crosses an isolation boundary.
    func stringOption(_ name: String) async throws -> String? {
        guard case .optionValueString(let value) = try await client.getOption(name: name)
        else { return nil }
        return value.value
    }

    /// Required before termination, per td_json_client.h: "All TDLib client
    /// instances must be closed before application termination to ensure data
    /// consistency."
    func shutdown() {
        manager.closeClients()
    }
}

@main
enum Probe {
    static func main() async {
        let gateway = ProbeGateway()

        do {
            // TDLib answers getOption even while parked in
            // authorizationStateWaitTdlibParameters, so this needs no login.
            guard
                let version = try await gateway.stringOption("version"),
                let commit = try await gateway.stringOption("commit_hash")
            else {
                fail(gateway, "TDLib returned no value for version/commit_hash.")
            }

            gateway.shutdown()

            print("""
                TDLib probe OK
                  version : \(version)
                  commit  : \(commit)

                Compare against Documentation/UPSTREAM.md §1.
                """)
        } catch {
            fail(gateway, "\(error)")
        }
    }

    private static func fail(_ gateway: ProbeGateway, _ reason: String) -> Never {
        gateway.shutdown()
        FileHandle.standardError.write(Data("""
            FAIL: \(reason)
                  Check the pinned versions in Documentation/UPSTREAM.md §1.

            """.utf8))
        exit(1)
    }
}
