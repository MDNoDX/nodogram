// Draws Nodogram's app icon at 1024 px with Core Graphics.
//
// The mark: a chat bubble holding an "N" drawn as a small graph — four nodes
// joined by edges — on a deep indigo-to-violet squircle. Deliberately unlike
// Telegram's (no paper plane, no light-blue circle).
//
//   swift Tools/icon/make_icon.swift <output.png>

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}

// macOS icon grid: an 824 pt body centred on the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(20, 10, 60, 0.45))
ctx.addPath(squircle); ctx.setFillColor(color(60, 45, 160)); ctx.fillPath()
ctx.restoreGState()

// Background gradient, top-left light to bottom-right deep.
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [color(124, 92, 255), color(83, 61, 214), color(48, 33, 140)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
// Soft highlight.
let glow = CGGradient(colorsSpace: space, colors: [color(255, 255, 255, 0.28), color(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 820), startRadius: 0,
                       endCenter: CGPoint(x: 300, y: 820), endRadius: 520, options: [])
ctx.restoreGState()

// The bubble: rounded body with a tail at the lower left.
let bubbleRect = CGRect(x: 232, y: 300, width: 560, height: 470)
let bubble = CGMutablePath()
bubble.addRoundedRect(in: bubbleRect, cornerWidth: 150, cornerHeight: 150)
bubble.move(to: CGPoint(x: 300, y: 340))
bubble.addCurve(to: CGPoint(x: 236, y: 232), control1: CGPoint(x: 292, y: 290), control2: CGPoint(x: 270, y: 250))
bubble.addCurve(to: CGPoint(x: 400, y: 312), control1: CGPoint(x: 310, y: 236), control2: CGPoint(x: 360, y: 262))
bubble.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(20, 8, 70, 0.35))
ctx.addPath(bubble); ctx.setFillColor(color(255, 255, 255)); ctx.fillPath()
ctx.restoreGState()

// The "N" as a graph: four nodes, three edges.
let nodes = [CGPoint(x: 392, y: 418), CGPoint(x: 392, y: 652), CGPoint(x: 632, y: 418), CGPoint(x: 632, y: 652)]
let edges = [(0, 1), (1, 2), (2, 3)]
ctx.saveGState()
ctx.setLineCap(.round)
ctx.setLineWidth(44)
let ink = CGGradient(colorsSpace: space, colors: [color(124, 92, 255), color(66, 46, 190)] as CFArray, locations: [0, 1])!
let strokes = CGMutablePath()
for (a, b) in edges { strokes.move(to: nodes[a]); strokes.addLine(to: nodes[b]) }
ctx.addPath(strokes); ctx.replacePathWithStrokedPath(); ctx.clip()
ctx.drawLinearGradient(ink, start: CGPoint(x: 0, y: 700), end: CGPoint(x: 0, y: 380), options: [])
ctx.restoreGState()
for (i, node) in nodes.enumerated() {
    let r: CGFloat = (i == 1 || i == 2) ? 50 : 46
    ctx.setFillColor(color(255, 255, 255))
    ctx.fillEllipse(in: CGRect(x: node.x - r - 10, y: node.y - r - 10, width: (r + 10) * 2, height: (r + 10) * 2))
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: node.x - r, y: node.y - r, width: r * 2, height: r * 2)); ctx.clip()
    ctx.drawLinearGradient(ink, start: CGPoint(x: node.x, y: node.y + r), end: CGPoint(x: node.x, y: node.y - r), options: [])
    ctx.restoreGState()
}
// A small accent dot: the "online" spark.
ctx.setFillColor(color(52, 211, 153))
ctx.fillEllipse(in: CGRect(x: 724, y: 690, width: 92, height: 92))
ctx.setStrokeColor(color(255, 255, 255)); ctx.setLineWidth(16)
ctx.strokeEllipse(in: CGRect(x: 724, y: 690, width: 92, height: 92))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
