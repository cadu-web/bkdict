// Draws Resources/dmg-background.tiff (660×400 plus @2x) with the BKDG fonts and colors.
// Run by hand when the copy or layout changes:
//   swift scripts/gen-dmg-background.swift
// The icon positions must match build.sh: app at x 180, Applications at x 480, both at y 190.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
for name in ["IBMPlexSans-Regular", "IBMPlexMono-Medium"] {
    let url = root.appendingPathComponent("Resources/Fonts/\(name).ttf")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

let size = NSSize(width: 660, height: 400)
let tinta = NSColor(srgbRed: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255, alpha: 1)
let secondary = NSColor(srgbRed: 0x4A / 255, green: 0x4A / 255, blue: 0x45 / 255, alpha: 1)
let tertiary = NSColor(srgbRed: 0x7D / 255, green: 0x7B / 255, blue: 0x73 / 255, alpha: 1)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // AppKit draws bottom-up; `top` converts the Finder window's y (from the top).
    func top(_ y: CGFloat) -> CGFloat { size.height - y }

    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Arrow between the two icons.
    let arrow = NSBezierPath()
    arrow.lineWidth = 1.5
    arrow.move(to: NSPoint(x: 280, y: top(190)))
    arrow.line(to: NSPoint(x: 380, y: top(190)))
    arrow.move(to: NSPoint(x: 368, y: top(178)))
    arrow.line(to: NSPoint(x: 380, y: top(190)))
    arrow.line(to: NSPoint(x: 368, y: top(202)))
    tinta.setStroke()
    arrow.stroke()

    func draw(_ text: String, font: NSFont, color: NSColor, kern: CGFloat = 0, centerY: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.size()
        string.draw(at: NSPoint(x: (size.width - bounds.width) / 2, y: top(centerY) - bounds.height / 2))
    }
    draw("Arraste o BKDict para Aplicativos", font: NSFont(name: "IBMPlexSans", size: 14)!, color: secondary, centerY: 316)
    draw("BKDG · DITADO POR VOZ", font: NSFont(name: "IBMPlexMono-Medium", size: 10)!, color: tertiary, kern: 0.8, centerY: 44)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: size)
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
try! image.tiffRepresentation(using: .lzw, factor: 0)!
    .write(to: root.appendingPathComponent("Resources/dmg-background.tiff"))
print("Resources/dmg-background.tiff")
