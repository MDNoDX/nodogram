//  The Vault API's JSON (Postgres timestamps through node-postgres) decodes,
//  and Bot API message ids map onto TDLib's.

import Foundation
import Testing
@testable import NodogramFeatures
import NodogramDomain

@Suite("Vault client")
struct VaultClientTests {

    @Test("Bot API ids become TDLib ids")
    func ids() {
        #expect(AppModel.tdlibMessageID(fromBotID: 1) == MessageID(1_048_576))
        #expect(AppModel.tdlibMessageID(fromBotID: 4321).rawValue == 4321 << 20)
    }

    @Test("Dates round-trip through the query string format")
    func dates() throws {
        let date = Date(timeIntervalSince1970: 1_791_000_000.307)
        let text = VaultClient.iso(date)
        #expect(text.hasSuffix("Z"))
        let parsed = try Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
        #expect(abs(parsed.timeIntervalSince(date)) < 0.002)
    }
}
