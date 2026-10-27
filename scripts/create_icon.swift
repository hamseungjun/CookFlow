import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Typographic identity: an ivory C and a quiet plate rim on forest green.
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let cream = CGColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)
context.setFillColor(CGColor(red: 0.19, green: 0.36, blue: 0.27, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setStrokeColor(CGColor(red: 0.77, green: 0.84, blue: 0.71, alpha: 1))
context.setLineWidth(3)
context.strokeEllipse(in: CGRect(x: 135, y: 135, width: 754, height: 754))
let font = CTFontCreateWithName("Baskerville" as CFString, 590, nil)
let string = NSAttributedString(string: "C", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): cream])
let line = CTLineCreateWithAttributedString(string)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
context.textPosition = CGPoint(x: 512 - bounds.midX, y: 512 - bounds.midY)
CTLineDraw(line, context)
context.setFillColor(CGColor(red: 0.77, green: 0.84, blue: 0.71, alpha: 1))
context.fillEllipse(in: CGRect(x: 681, y: 320, width: 34, height: 34))
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write app icon") }
