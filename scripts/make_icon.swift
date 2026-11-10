// Рисует иконку приложения (волна на лаймовом скруглённом квадрате) и собирает .icns.
// Запуск: swift scripts/make_icon.swift app/Resources/AppIcon.icns
// Кодом, а не картинкой: на Command Line Tools нет actool и asset-каталогов.
import AppKit

guard CommandLine.arguments.count == 2 else {
    print("usage: make_icon.swift <AppIcon.icns>")
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(_ pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    // сетка иконок macOS: квадрат 824 в поле 1024, скругление ~22 %
    let plate = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                       cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(plate)
    ctx.setFillColor(CGColor(srgbRed: 0.83, green: 0.95, blue: 0.35, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let colors = [CGColor(srgbRed: 0.90, green: 0.98, blue: 0.50, alpha: 1),
                  CGColor(srgbRed: 0.76, green: 0.91, blue: 0.27, alpha: 1)] as CFArray
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!,
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // волна: графитовые штрихи разной высоты
    let heights: [CGFloat] = [120, 250, 400, 220, 470, 300, 160]
    let width: CGFloat = 52, gap: CGFloat = 36
    var x = 512 - (CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap) / 2
    ctx.setFillColor(CGColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1))
    for height in heights {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 512 - height / 2, width: width, height: height),
                           cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
        x += width + gap
    }
    ctx.fillPath()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try png(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
