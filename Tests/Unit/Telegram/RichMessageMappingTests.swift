//  Article-style ("rich") messages show their words, in order, without URLs.

import Testing
import Foundation
import TDLibKit
@testable import NodogramTelegram

@Suite("Rich message mapping")
struct RichMessageMappingTests {

    @Test("Rich message blocks flatten to readable text")
    func richText() {
        let title = PageBlock.pageBlockTitle(PageBlockTitle(title: .richTextPlain(RichTextPlain(text: "Yangi kitoblar"))))
        let paragraph = PageBlock.pageBlockParagraph(PageBlockParagraph(text: .richTexts(RichTexts(texts: [
            .richTextPlain(RichTextPlain(text: "Bugun ")),
            .richTextBold(RichTextBold(text: .richTextPlain(RichTextPlain(text: "chegirma")))),
            .richTextUrl(RichTextUrl(isCached: false, text: .richTextPlain(RichTextPlain(text: " bor")),
                                     url: "https://example.com")),
        ]))))
        let text = ContentMapping.richText([title, paragraph])
        #expect(text == "Yangi kitoblar\n\nBugun chegirma bor")
        #expect(!text.contains("example.com"))
    }
}
