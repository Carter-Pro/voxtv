import AppKit
import Foundation

func renderSVG(_ svgPath: String, to pngPath: String, size: CGSize) {
    guard let image = NSImage(contentsOfFile: svgPath) else {
        print("ERROR: Cannot load \(svgPath)")
        exit(1)
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    image.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("ERROR: Cannot encode PNG for \(pngPath)")
        exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: pngPath))
    print("  \(pngPath) (\(Int(size.width))x\(Int(size.height)))")
}

// AppIcon sizes
let appIconSizes: [(String, CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

// MenuBarIcon sizes
let menuBarSizes: [(String, CGFloat)] = [
    ("MenuBarIcon", 20),
    ("MenuBarIcon@2x", 40),
    ("MenuBarIcon@3x", 60),
]

let fm = FileManager.default
let base = fm.currentDirectoryPath

// Generate AppIcon
print("Generating AppIcon...")
let appIconDir = "\(base)/Sources/Voxtv/Assets.xcassets/AppIcon.appiconset"
try! fm.createDirectory(atPath: appIconDir, withIntermediateDirectories: true)
for (name, size) in appIconSizes {
    renderSVG("\(base)/design/VoxTV-AppIcon.svg",
              to: "\(appIconDir)/\(name).png",
              size: CGSize(width: size, height: size))
}

// Generate MenuBarIcon
print("Generating MenuBarIcon...")
let menuBarDir = "\(base)/Sources/Voxtv/Assets.xcassets/MenuBarIcon.imageset"
try! fm.createDirectory(atPath: menuBarDir, withIntermediateDirectories: true)
for (name, size) in menuBarSizes {
    renderSVG("\(base)/design/VoxTV-MenuBarIcon.svg",
              to: "\(menuBarDir)/\(name).png",
              size: CGSize(width: size, height: size))
}
print("Done!")
