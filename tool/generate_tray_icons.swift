// Reproducible, native-resolution monochrome companions to the AuraScribe mark.
// Run from the project root: swift tool/generate_tray_icons.swift
import AppKit
for (name, state) in [("tray_icon", 0), ("tray_icon_recording", 1), ("tray_icon_transcribing", 2)] {
    let image = NSImage(size: NSSize(width: 36, height: 36))
    image.lockFocus()
    NSColor.black.setStroke()
    let curves = [(CGFloat(5), CGFloat(27)), (CGFloat(7), CGFloat(21)), (CGFloat(9), CGFloat(15))]
    for (base, peak) in curves {
        let path = NSBezierPath()
        path.lineWidth = 2.8; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 4, y: base))
        path.curve(to: NSPoint(x: 28, y: base + 1),
                   controlPoint1: NSPoint(x: 14, y: base), controlPoint2: NSPoint(x: 15, y: peak + 16))
        path.stroke()
    }
    NSColor.black.setFill()
    if state == 1 { NSBezierPath(ovalIn: NSRect(x: 28, y: 25, width: 7, height: 7)).fill() }
    if state == 2 {
        for y in [CGFloat(24), CGFloat(30)] { NSBezierPath(ovalIn: NSRect(x: 29, y: y, width: 4, height: 4)).fill() }
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "assets/\(name).png"))
}
