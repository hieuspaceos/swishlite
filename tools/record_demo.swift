import Cocoa

// Headless demo recorder for SwishLite.
// `swift tools/record_demo.swift /tmp/sl-frames` renders 720 PNG frames
// (1920x1080, 60fps) replaying the real snap-zone geometry from
// GestureEngine.apply — halves → two-thirds → maximize → restore → split pair.
// No windows are created; the moving "window" is a real crop of the screen
// capture, framed with a macOS titlebar. ffmpeg stitches frames to MP4:
//   ffmpeg -framerate 60 -i /tmp/sl-frames/f%04d.png -c:v libx264 -pix_fmt yuv420p demo.mp4

let W: CGFloat = 1920, H: CGFloat = 1080
let TOTAL = 720
let easeOut: (CGFloat) -> CGFloat = { 1 - pow(1 - $0, 3) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }


func png(_ img: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    if let d = rep.representation(using: .png, properties: [:]) {
        try? d.write(to: URL(fileURLWithPath: path))
    }
}

func roundRect(_ ctx: CGContext, _ r: CGRect, _ rad: CGFloat) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
}

func drawText(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, color: NSColor) {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size), .foregroundColor: color]))
    ctx.saveGState()
    ctx.textPosition = p
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// Draws a "window": titlebar chrome + real screen-crop content, clipped rounded.
func drawWindow(_ ctx: CGContext, rect: CGRect, content: CGImage,
                contentRect: CGRect, title: String) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 44,
                  color: CGColor(gray: 0, alpha: 0.55))
    roundRect(ctx, rect, 10)
    ctx.setFillColor(CGColor(gray: 0.13, alpha: 1))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.saveGState()
    roundRect(ctx, rect, 10)
    ctx.clip()
    // content
    ctx.draw(content, in: CGRect(x: rect.minX, y: rect.minY,
                                 width: rect.width, height: rect.height - 28))
    // titlebar
    let tb = CGRect(x: rect.minX, y: rect.maxY - 28, width: rect.width, height: 28)
    ctx.setFillColor(CGColor(gray: 0.17, alpha: 1))
    ctx.fill(tb)
    let lights: [CGColor] = [
        CGColor(red: 1, green: 0.37, blue: 0.34, alpha: 1),
        CGColor(red: 1, green: 0.74, blue: 0.18, alpha: 1),
        CGColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)]
    for (i, c) in lights.enumerated() {
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: rect.minX + 10 + CGFloat(i) * 18,
                                   y: tb.minY + 8, width: 11, height: 11))
    }
    drawText(ctx, title, at: CGPoint(x: rect.minX + 70, y: tb.minY + 8),
             size: 12, color: NSColor(white: 0.65, alpha: 1))
    ctx.restoreGState()
    ctx.restoreGState()
}

/// Real bezel: small glyph right above the cursor (26x26, ~380ms flash).
func drawBezel(_ ctx: CGContext, at p: CGPoint, glyph: String, opacity: CGFloat) {
    ctx.saveGState()
    ctx.setAlpha(opacity)
    let r = CGRect(x: p.x - 13, y: p.y + 12, width: 26, height: 26)
    roundRect(ctx, r, 6)
    ctx.setFillColor(CGColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 0.9))
    ctx.fillPath()
    drawText(ctx, glyph, at: CGPoint(x: r.minX + 5, y: r.minY + 5),
             size: 14, color: NSColor(white: 0.1, alpha: 1))
    ctx.restoreGState()
}

/// two-finger trackpad hint travelling along the title bar
func drawFingers(_ ctx: CGContext, x: CGFloat, y: CGFloat, opacity: CGFloat) {
    ctx.saveGState()
    ctx.setAlpha(opacity)
    for i in 0..<2 {
        let r = CGRect(x: x + CGFloat(i) * 26, y: y, width: 22, height: 28)
        roundRect(ctx, r, 11)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.3))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

// MARK: - main

guard CommandLine.arguments.count > 1 else {
    print("usage: record_demo.swift <outdir>"); exit(1)
}
let outdir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true)

// MARK: - synthetic scene (no live screen capture → runs headless)
func syntheticScene() -> CGImage? {
    let sw: CGFloat = 1512, sh: CGFloat = 950
    guard let ctx = CGContext(data: nil, width: Int(sw * 2), height: Int(sh * 2),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.scaleBy(x: 2, y: 2)
    if let url = NSWorkspace.shared.desktopImageURL(for: NSScreen.main ?? NSScreen()),
       let wp = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let iw = CGFloat(wp.width), ih = CGFloat(wp.height)
        let z = max(sw / iw, sh / ih)
        ctx.draw(wp, in: CGRect(x: (sw - iw * z) / 2, y: (sh - ih * z) / 2,
                               width: iw * z, height: ih * z))
    }
    drawFinderWindow(ctx, rect: CGRect(x: 0, y: sh - 990 + 40 - 26, width: 756, height: 950),
                     title: "hieuspace",
                     items: ["Applications","bin","cAlgo","cTrader","Desktop","Downloads",
                             "html-video","Movies","Music","orca","Public"],
                     folderStyle: true)
    drawFinderWindow(ctx, rect: CGRect(x: 756, y: sh - 990 + 40 - 26, width: 756, height: 950),
                     title: "Applications",
                     items: ["App Store","Apps","Automator","Brave Browser","Calculator",
                             "Calendar","Contacts","Dictionary","FaceTime","Find My"],
                     folderStyle: false)
    return ctx.makeImage()
}

func drawFinderWindow(_ ctx: CGContext, rect: CGRect, title: String,
                      items: [String], folderStyle: Bool) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40,
                  color: CGColor(gray: 0, alpha: 0.45))
    roundRect(ctx, rect, 10)
    ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.saveGState()
    roundRect(ctx, rect, 10)
    ctx.clip()
    ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
    ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: 190, height: rect.height))
    let side = ["Recents","Shared","","FAVORITES","Applications","Desktop","Documents",
                "Downloads","","LOCATIONS","iCloud Drive","hieuspace","Trash"]
    var sy = rect.maxY - 60
    for s in side {
        let header = s == "FAVORITES" || s == "LOCATIONS"
        drawText(ctx, s.isEmpty ? " " : s, at: CGPoint(x: rect.minX + 14, y: sy),
                 size: header ? 10 : 12,
                 color: NSColor(white: header ? 0.45 : 0.75, alpha: 1))
        sy -= s.isEmpty ? 14 : 20
    }
    ctx.setFillColor(CGColor(gray: 0.17, alpha: 1))
    ctx.fill(CGRect(x: rect.minX + 190, y: rect.maxY - 40, width: rect.width - 190, height: 40))
    let lights: [CGColor] = [
        CGColor(red: 1, green: 0.37, blue: 0.34, alpha: 1),
        CGColor(red: 1, green: 0.74, blue: 0.18, alpha: 1),
        CGColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)]
    for (i, c) in lights.enumerated() {
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: rect.minX + 12 + CGFloat(i) * 20,
                                   y: rect.maxY - 26, width: 12, height: 12))
    }
    drawText(ctx, title, at: CGPoint(x: rect.minX + 210, y: rect.maxY - 27),
             size: 13, color: NSColor(white: 0.6, alpha: 1))
    for (i, name) in items.enumerated() {
        let col = i % 4, row = i / 4
        let ix = rect.minX + 214 + CGFloat(col) * 130
        let iy = rect.maxY - 140 - CGFloat(row) * 120
        let ir = CGRect(x: ix, y: iy, width: 60, height: 46)
        roundRect(ctx, ir, 8)
        ctx.setFillColor(folderStyle
            ? CGColor(red: 0.49, green: 0.78, blue: 0.95, alpha: 1)
            : CGColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1))
        ctx.fillPath()
        if folderStyle { ctx.fill(CGRect(x: ir.minX, y: ir.maxY - 4, width: 22, height: 8)) }
        drawText(ctx, name, at: CGPoint(x: ix, y: iy - 14), size: 11,
                 color: NSColor(white: 0.85, alpha: 1))
    }
    ctx.restoreGState()
    ctx.restoreGState()
}

guard let scene = syntheticScene() else {
    print("scene build failed"); exit(1)
}
let screen = scene
let scale: CGFloat = 2
// window content = crops of the synthetic scene's window regions (pixels)
let cropPx = CGRect(x: 215 * 2, y: 70 * 2, width: 520 * 2, height: 860 * 2)
let winContent = screen.cropping(to: cropPx)!
let cropPx2 = CGRect(x: 975 * 2, y: 70 * 2, width: 515 * 2, height: 860 * 2)
let winContent2 = screen.cropping(to: cropPx2)!

let menu: CGFloat = 26
let visH = H - menu
func half(_ side: Int) -> CGRect {   // 0 left, 1 right
    CGRect(x: side == 0 ? 10 : W/2 + 5, y: 10, width: W/2 - 15, height: visH - 20) }
let CENTER = CGRect(x: 560, y: 140, width: 800, height: 700)
let LEFT = half(0)
let L23 = CGRect(x: LEFT.minX, y: LEFT.minY, width: W * 2/3 - 15, height: LEFT.height)
let FILL = CGRect(x: 10, y: 10, width: W - 20, height: visH - 20)
let RIGHT = half(1)

struct Stage { let a: Int, b: Int } // progress window
let p1 = Stage(a: 72, b: 112)   // center → left
let p2 = Stage(a: 187, b: 227)  // left → 2/3
let p3 = Stage(a: 302, b: 342)  // → fill
let p4 = Stage(a: 417, b: 452)  // → center (restore)
let p5 = Stage(a: 560, b: 600)  // → left, 2nd win → right

func prog(_ f: Int, _ s: Stage) -> CGFloat {
    guard f > s.a else { return 0 }
    return easeOut(min(1, CGFloat(f - s.a) / CGFloat(s.b - s.a)))
}
func rectBetween(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t),
           width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
}

// bezel moments: (frame flash begins, ends, glyph) — glyph shown at commit
let bezels: [(Int, Int, String)] = [
    (105, 130, "◧"), (220, 245, "▦"), (335, 360, "⬚"), (445, 468, "↩"), (595, 620, "◧")
]
// two-finger travel: (start, end, dx)
let fingers: [(Int, Int, CGFloat)] = [
    (40, 70, -80), (155, 185, -80), (270, 300, 0), (528, 558, -80)
]

for f in 0..<TOTAL {
    autoreleasepool {
        guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }


        // wallpaper + screen
        ctx.draw(screen, in: CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.25))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // compose window rect through stages
        var r = CENTER
        r = rectBetween(r, LEFT, prog(f, p1))
        r = rectBetween(r, L23, prog(f, p2))
        r = rectBetween(r, FILL, prog(f, p3))
        r = rectBetween(r, CENTER, prog(f, p4))
        r = rectBetween(r, LEFT, prog(f, p5))

        // second window → right half
        if f > 560 {
            let t2 = prog(f, Stage(a: 585, b: 630))
            let r2 = rectBetween(CGRect(x: 1300, y: 200, width: 520, height: 440),
                                 RIGHT, t2)
            drawWindow(ctx, rect: r2, content: winContent2,
                       contentRect: cropPx2, title: "Applications")
        }

        drawWindow(ctx, rect: r, content: winContent,
                   contentRect: cropPx, title: "hieuspace")

        // fingers + bezel at cursor (on title bar, above window centre)
        let cx = r.midX, cy = r.maxY - 14
        for (a, b, dx) in fingers {
            let op = f > a && f < b + 6 ? 1 : 0
            if op == 1 {
                let t = easeOut(min(1, CGFloat(f - a) / CGFloat(b - a)))
                drawFingers(ctx, x: cx - 24 + dx * t, y: cy + 6, opacity: 0.95)
            }
        }
        for (a, b, g) in bezels {
            if f >= a && f <= b {
                drawBezel(ctx, at: CGPoint(x: cx, y: cy), glyph: g, opacity: 1)
            }
        }

        // menubar
        ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.85))
        ctx.fill(CGRect(x: 0, y: H - 26, width: W, height: 26))
        drawText(ctx, "  Finder   File   Edit   View",
                 at: CGPoint(x: 14, y: H - 19), size: 13,
                 color: NSColor(white: 0.1, alpha: 1))
        drawText(ctx, "◫   Mon 19 Oct 13:40",
                 at: CGPoint(x: W - 190, y: H - 19), size: 12,
                 color: NSColor(white: 0.1, alpha: 1))

        if let img = ctx.makeImage() {
            png(img, to: String(format: "%@/f%04d.png", outdir, f))
        }
    }
    if f % 120 == 0 { print("frame \(f)/\(TOTAL)") }
}
print("done -> \(outdir)")
