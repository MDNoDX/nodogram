//  Renders a message's text with Telegram's formatting.
//
//  Telegram sends formatting as ranges in UTF-16 code units. Converting through
//  NSRange is the only correct way to map those onto a Swift string: counting
//  Characters instead would misplace every range after an emoji.

import SwiftUI
import NodogramDomain
import NodogramUI

enum FormattedText {

    static func attributed(_ text: String, entities: [TextEntity], baseSize: CGFloat) -> AttributedString {
        var result = AttributedString(text)
        let ns = text as NSString

        for entity in entities {
            let nsRange = NSRange(location: entity.offset, length: entity.length)
            guard nsRange.location >= 0, NSMaxRange(nsRange) <= ns.length,
                  let stringRange = Range(nsRange, in: text),
                  let range = Range(stringRange, in: result) else { continue }

            switch entity.kind {
            case .bold:
                result[range].inlinePresentationIntent = (result[range].inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            case .italic:
                result[range].inlinePresentationIntent = (result[range].inlinePresentationIntent ?? []).union(.emphasized)
            case .underline:
                result[range].underlineStyle = .single
            case .strikethrough:
                result[range].strikethroughStyle = .single
            case .code, .pre:
                result[range].font = .system(size: baseSize - 0.5, design: .monospaced)
                result[range].backgroundColor = Color.secondary.opacity(0.14)
            case .quote:
                result[range].foregroundColor = .secondary
                result[range].inlinePresentationIntent = (result[range].inlinePresentationIntent ?? []).union(.emphasized)
            case .spoiler:
                // Hidden until the bubble is clicked (see MessageBubble).
                result[range].foregroundColor = .clear
                result[range].backgroundColor = Color.secondary.opacity(0.45)
            case .url:
                if let url = webURL(String(text[stringRange])) { result[range].link = url }
            case .textLink(let target):
                if let url = webURL(target) { result[range].link = url }
            case .email:
                if let url = URL(string: "mailto:\(text[stringRange])") { result[range].link = url }
            case .phone:
                let digits = text[stringRange].filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "tel:\(digits)") { result[range].link = url }
            case .mention, .mentionName, .hashtag, .cashtag, .botCommand:
                result[range].foregroundColor = Theme.accent
            }
        }
        return result
    }

    static func hasSpoiler(_ entities: [TextEntity]) -> Bool {
        entities.contains { $0.kind == .spoiler }
    }

    /// Links without a scheme ("example.com") still need to open in a browser.
    private static func webURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://\(trimmed)")
    }
}

/// Lays out a bubble's contents: each child as wide as it needs up to a limit,
/// the bubble as wide as its widest child, and the last child (the time and
/// receipt) pinned to the trailing edge.
///
/// A plain VStack cannot do this — giving the footer a trailing alignment with
/// `maxWidth: .infinity` makes every bubble full-width — which is why short
/// messages in naive chat UIs look like wide empty boxes.
struct BubbleLayout: Layout {
    var maxWidth: CGFloat
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = min(proposal.width ?? maxWidth, maxWidth)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
            width = max(width, size.width)
            height += size.height + (index > 0 ? spacing : 0)
        }
        return CGSize(width: ceil(width), height: ceil(height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let isFooter = index == subviews.count - 1 && subviews.count > 1
            let x = isFooter ? bounds.maxX - size.width : bounds.minX
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: isFooter ? size.width : bounds.width, height: size.height))
            y += size.height + spacing
        }
    }
}
