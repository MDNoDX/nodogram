//  Layout rules for media in the timeline: aspect ratios, album mosaics and
//  how album messages are grouped into one row.

import Foundation
import Testing
import CoreGraphics
@testable import NodogramFeatures
import NodogramDomain

@Suite("Media layout")
struct MediaLayoutTests {

    @Test("Ordinary shapes keep their exact aspect ratio", arguments: [
        (1920, 1080), (1080, 1920), (1280, 1280), (4000, 3000), (720, 1280), (640, 360),
    ])
    func aspectIsExact(width: Int, height: Int) {
        let size = fittedMediaSize(width: width, height: height)
        let expected = Double(width) / Double(height)
        #expect(abs(Double(size.width / size.height) - expected) < 0.01)
        #expect(size.width <= 420 && size.height <= 460)
    }

    @Test("16:9 video fills the bubble width")
    func wideVideo() {
        let size = fittedMediaSize(width: 1920, height: 1080)
        #expect(size.width == 420)
        #expect(abs(size.height - 236.25) < 0.01)
    }

    @Test("Unknown dimensions fall back to 16:9")
    func unknownDimensions() {
        #expect(fittedMediaSize(width: 0, height: 0) == CGSize(width: 320, height: 180))
    }

    @Test("Every mosaic row spans the full width", arguments: 2...10)
    func rowsFillWidth(count: Int) {
        let aspects = (0..<count).map { CGFloat([1.0, 1.78, 0.56, 1.33][$0 % 4]) }
        let rows = AlbumGrid.layout(aspects, width: 420)
        #expect(rows.reduce(0) { $0 + $1.items.count } == count)
        #expect(rows.map(\.items.count) == AlbumGrid.rowCounts(count))
        for row in rows {
            let width = row.items.reduce(0) { $0 + $1.width } + 2 * CGFloat(row.items.count - 1)
            #expect(abs(width - 420) < 0.5)
            #expect(row.height >= 90 && row.height <= 320)
        }
    }

    @Test("Items keep their order across rows")
    func order() {
        let rows = AlbumGrid.layout(Array(repeating: 1, count: 7), width: 420)
        #expect(rows.flatMap { $0.items.map(\.index) } == Array(0..<7))
    }

    private func photo(_ id: Int64, album: Int64, text: String = "", minute: Int = 0) -> Message {
        let file = MediaFile(id: Int(id), uniqueID: "u\(id)", size: 1000)
        return Message(id: MessageID(id), chatID: ChatID(1), senderID: UserID(7), senderName: "A", text: text,
                       date: Date(timeIntervalSince1970: 1_700_000_000 + Double(minute * 60)),
                       media: .photo(PhotoMedia(preview: file, full: file, width: 800, height: 600, minithumbnail: nil)),
                       albumID: album)
    }

    @Test("Consecutive album messages become one row")
    func groupsAlbums() {
        let messages = [photo(1, album: 0), photo(2, album: 9), photo(3, album: 9, text: "caption"),
                        photo(4, album: 9), photo(5, album: 0)]
        let rows = TimelineRow.build(from: messages, groupChat: false).filter {
            if case .day = $0.kind { return false }
            return true
        }
        #expect(rows.count == 3)
        if case .album(let items, _) = rows[1].kind {
            #expect(items.map(\.id.rawValue) == [2, 3, 4])
        } else {
            Issue.record("Expected an album row")
        }
    }

    @Test("A lone album member renders as an ordinary message")
    func singleAlbumMember() {
        let rows = TimelineRow.build(from: [photo(1, album: 5)], groupChat: false)
        #expect(rows.contains { if case .message = $0.kind { return true }; return false })
    }
}
