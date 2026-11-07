// Vẽ ảnh nền DMG. Chạy: swift scripts/dmg/make-background.swift scripts/dmg && tiffutil -cathidpicheck scripts/dmg/bg.png scripts/dmg/bg@2x.png -out scripts/dmg/background.tiff
import AppKit
// Ảnh nền DMG 640×400 (@1x) và 1280×800 (@2x)
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat((h>>16)&0xFF)/255, green: CGFloat((h>>8)&0xFF)/255, blue: CGFloat(h&0xFF)/255, alpha: a) }
func make(scale: CGFloat, out: String) {
    let W = Int(640*scale), H = Int(400*scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 640, height: 400)   // để Finder hiểu đây là ảnh @2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(x: 0, y: 0, width: 640, height: 400)
    NSGradient(colors: [rgb(0xF7FAFE), rgb(0xE6F0FA)])!.draw(in: r, angle: -90)
    // Dải màu trên cùng
    NSGradient(colors: [rgb(0x7DB8F0), rgb(0x4A90D9)])!.draw(in: NSRect(x: 0, y: 340, width: 640, height: 60), angle: 0)
    let title = NSAttributedString(string: "xTrans", attributes: [.font: NSFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: NSColor.white])
    title.draw(at: NSPoint(x: 28, y: 354))
    let sub = NSAttributedString(string: "Dịch song ngữ bằng AI", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
    sub.draw(at: NSPoint(x: 128, y: 362))
    // Mũi tên từ app → Applications (tâm icon: y = 400-190 = 210)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 250, y: 210)); arrow.line(to: NSPoint(x: 380, y: 210))
    arrow.lineWidth = 6; arrow.lineCapStyle = .round
    rgb(0x4A90D9, 0.85).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 398, y: 210)); head.line(to: NSPoint(x: 374, y: 226)); head.line(to: NSPoint(x: 374, y: 194)); head.close()
    rgb(0x4A90D9, 0.85).setFill(); head.fill()
    // Hướng dẫn
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let hint = NSAttributedString(string: "Kéo xTrans vào thư mục Applications để cài đặt", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: rgb(0x2F4A66), .paragraphStyle: p])
    hint.draw(in: NSRect(x: 0, y: 70, width: 640, height: 22))
    let hint2 = NSAttributedString(string: "Sau khi cài: icon xTrans luôn có ở góc phải menu bar", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: rgb(0x6B7F95), .paragraphStyle: p])
    hint2.draw(in: NSRect(x: 0, y: 48, width: 640, height: 18))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
let dir = CommandLine.arguments[1]
make(scale: 1, out: dir + "/bg.png")
make(scale: 2, out: dir + "/bg@2x.png")
print("ok")
