#!/usr/bin/env swift
import AppKit
import Foundation

// SVG → icns 转换脚本
let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: svg2icns <input.svg> <output.icns>")
    exit(1)
}

let svgPath = args[1]
let icnsPath = args[2]

guard let svgData = FileManager.default.contents(atPath: svgPath) else {
    print("无法读取 SVG 文件: \(svgPath)")
    exit(1)
}

// 使用 NSImage 加载 SVG
guard let svgImage = NSImage(data: svgData) else {
    print("无法解析 SVG")
    exit(1)
}

// iconset 需要的尺寸
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let iconsetDir = "/tmp/AppIcon_\(ProcessInfo.processInfo.processIdentifier).iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    svgImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    let pngData = rep.representation(using: .png, properties: [:])!
    let filePath = (iconsetDir as NSString).appendingPathComponent(name)
    try! pngData.write(to: URL(fileURLWithPath: filePath))
}

// 调用 iconutil 生成 icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", icnsPath, iconsetDir]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("生成成功: \(icnsPath)")
} else {
    print("iconutil 失败")
    exit(1)
}

// 清理
try? FileManager.default.removeItem(atPath: iconsetDir)
