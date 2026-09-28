import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: swift make-icon.swift /absolute/output.png\n", stderr)
    exit(64)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let canvas = NSRect(origin: .zero, size: size)
let rounded = NSBezierPath(
    roundedRect: canvas.insetBy(dx: 44, dy: 44),
    xRadius: 230,
    yRadius: 230
)
rounded.addClip()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.19, green: 0.13, blue: 0.44, alpha: 1),
    NSColor(calibratedRed: 0.38, green: 0.26, blue: 0.86, alpha: 1),
    NSColor(calibratedRed: 0.11, green: 0.75, blue: 0.82, alpha: 1),
])!
gradient.draw(in: canvas, angle: -48)

NSColor.white.withAlphaComponent(0.12).setFill()
NSBezierPath(ovalIn: NSRect(x: 480, y: 470, width: 700, height: 700)).fill()

let barWidth: CGFloat = 92
let gap: CGFloat = 72
let heights: [CGFloat] = [310, 520, 700, 460]
let originX: CGFloat = 213

for (index, height) in heights.enumerated() {
    let x = originX + CGFloat(index) * (barWidth + gap)
    let rect = NSRect(
        x: x,
        y: (1024 - height) / 2,
        width: barWidth,
        height: height
    )
    let path = NSBezierPath(
        roundedRect: rect,
        xRadius: barWidth / 2,
        yRadius: barWidth / 2
    )
    NSColor.white.withAlphaComponent(index == 2 ? 1 : 0.86).setFill()
    path.fill()

    let knobY = rect.minY + height * [0.34, 0.67, 0.48, 0.76][index]
    let knob = NSBezierPath(
        ovalIn: NSRect(
            x: x - 20,
            y: knobY - 66,
            width: barWidth + 40,
            height: 132
        )
    )
    NSColor(calibratedWhite: 0.08, alpha: 0.94).setFill()
    knob.fill()
    NSColor.white.withAlphaComponent(0.9).setStroke()
    knob.lineWidth = 8
    knob.stroke()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
