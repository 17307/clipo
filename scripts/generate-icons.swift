#!/usr/bin/env swift

//  scripts/generate-icons.swift
//
//  Renders a cute cat-themed app icon at every size required by
//  AppIcon.appiconset and writes out Contents.json referencing them.
//
//  Run:
//      swift scripts/generate-icons.swift
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Targets

struct IconSize {
    let filename: String
    let pixels: Int
    let idiom: String
    let size: String   // logical size "16x16"
    let scale: String  // "1x" / "2x"
}

let iconSet: [IconSize] = [
    IconSize(filename: "icon_16x16.png",      pixels: 16,   idiom: "mac", size: "16x16",   scale: "1x"),
    IconSize(filename: "icon_16x16@2x.png",   pixels: 32,   idiom: "mac", size: "16x16",   scale: "2x"),
    IconSize(filename: "icon_32x32.png",      pixels: 32,   idiom: "mac", size: "32x32",   scale: "1x"),
    IconSize(filename: "icon_32x32@2x.png",   pixels: 64,   idiom: "mac", size: "32x32",   scale: "2x"),
    IconSize(filename: "icon_128x128.png",    pixels: 128,  idiom: "mac", size: "128x128", scale: "1x"),
    IconSize(filename: "icon_128x128@2x.png", pixels: 256,  idiom: "mac", size: "128x128", scale: "2x"),
    IconSize(filename: "icon_256x256.png",    pixels: 256,  idiom: "mac", size: "256x256", scale: "1x"),
    IconSize(filename: "icon_256x256@2x.png", pixels: 512,  idiom: "mac", size: "256x256", scale: "2x"),
    IconSize(filename: "icon_512x512.png",    pixels: 512,  idiom: "mac", size: "512x512", scale: "1x"),
    IconSize(filename: "icon_512x512@2x.png", pixels: 1024, idiom: "mac", size: "512x512", scale: "2x"),
]

// MARK: - Drawing

/// Draws the cat icon into `ctx` at a canvas size of `size` × `size` points.
/// All dimensions are expressed in that canvas and scale naturally with it.
func drawCatIcon(in ctx: CGContext, size: CGFloat) {
    // ── Background: rounded square with an orange gradient ──
    let cornerRadius: CGFloat = size * 0.23  // macOS squircle-ish
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let bgPath = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        NSColor(srgbRed: 1.00, green: 0.64, blue: 0.38, alpha: 1.0).cgColor,  // top
        NSColor(srgbRed: 1.00, green: 0.42, blue: 0.24, alpha: 1.0).cgColor,  // bottom (brand)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end:   CGPoint(x: 0, y: 0),
        options: []
    )
    ctx.restoreGState()

    // ── Palette ──
    let fur      = NSColor(srgbRed: 1.00, green: 0.97, blue: 0.92, alpha: 1.0).cgColor
    let earPink  = NSColor(srgbRed: 0.98, green: 0.66, blue: 0.70, alpha: 1.0).cgColor
    let ink      = NSColor(srgbRed: 0.18, green: 0.12, blue: 0.10, alpha: 1.0).cgColor
    let nose     = NSColor(srgbRed: 0.97, green: 0.54, blue: 0.58, alpha: 1.0).cgColor
    let blush    = NSColor(srgbRed: 1.00, green: 0.68, blue: 0.68, alpha: 0.55).cgColor

    // ── Head frame ──
    let center = CGPoint(x: size * 0.50, y: size * 0.47)
    let faceR: CGFloat = size * 0.32

    // ── Ears (drawn first so head circle hides their base) ──
    func triangle(tip: CGPoint, left: CGPoint, right: CGPoint) -> CGPath {
        let p = CGMutablePath()
        p.move(to: left)
        p.addLine(to: tip)
        p.addLine(to: right)
        p.closeSubpath()
        return p
    }

    let lEarOuter = triangle(
        tip:   CGPoint(x: center.x - faceR * 0.75, y: center.y + faceR * 1.50),
        left:  CGPoint(x: center.x - faceR * 1.10, y: center.y + faceR * 0.55),
        right: CGPoint(x: center.x - faceR * 0.30, y: center.y + faceR * 0.92)
    )
    let rEarOuter = triangle(
        tip:   CGPoint(x: center.x + faceR * 0.75, y: center.y + faceR * 1.50),
        left:  CGPoint(x: center.x + faceR * 0.30, y: center.y + faceR * 0.92),
        right: CGPoint(x: center.x + faceR * 1.10, y: center.y + faceR * 0.55)
    )
    ctx.setFillColor(fur)
    ctx.addPath(lEarOuter); ctx.fillPath()
    ctx.addPath(rEarOuter); ctx.fillPath()

    let lEarInner = triangle(
        tip:   CGPoint(x: center.x - faceR * 0.72, y: center.y + faceR * 1.28),
        left:  CGPoint(x: center.x - faceR * 0.93, y: center.y + faceR * 0.72),
        right: CGPoint(x: center.x - faceR * 0.43, y: center.y + faceR * 0.88)
    )
    let rEarInner = triangle(
        tip:   CGPoint(x: center.x + faceR * 0.72, y: center.y + faceR * 1.28),
        left:  CGPoint(x: center.x + faceR * 0.43, y: center.y + faceR * 0.88),
        right: CGPoint(x: center.x + faceR * 0.93, y: center.y + faceR * 0.72)
    )
    ctx.setFillColor(earPink)
    ctx.addPath(lEarInner); ctx.fillPath()
    ctx.addPath(rEarInner); ctx.fillPath()

    // ── Face ──
    ctx.setFillColor(fur)
    ctx.addEllipse(in: CGRect(
        x: center.x - faceR,
        y: center.y - faceR,
        width: faceR * 2,
        height: faceR * 2
    ))
    ctx.fillPath()

    // Subtle shadow under the face for a tiny bit of depth.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.006),
        blur: size * 0.02,
        color: NSColor.black.withAlphaComponent(0.10).cgColor
    )
    ctx.setFillColor(NSColor.clear.cgColor)
    ctx.addEllipse(in: CGRect(
        x: center.x - faceR,
        y: center.y - faceR,
        width: faceR * 2,
        height: faceR * 2
    ))
    ctx.fillPath()
    ctx.restoreGState()

    // ── Cheek blush ──
    let cheekW = faceR * 0.24
    let cheekH = faceR * 0.14
    ctx.setFillColor(blush)
    ctx.addEllipse(in: CGRect(
        x: center.x - faceR * 0.66,
        y: center.y - faceR * 0.22,
        width: cheekW * 2,
        height: cheekH * 2
    ))
    ctx.fillPath()
    ctx.addEllipse(in: CGRect(
        x: center.x + faceR * 0.66 - cheekW * 2,
        y: center.y - faceR * 0.22,
        width: cheekW * 2,
        height: cheekH * 2
    ))
    ctx.fillPath()

    // ── Closed "^ ^" smile eyes for cuteness ──
    let eyeOffsetX = faceR * 0.38
    let eyeHalfW   = faceR * 0.19
    let eyeY       = center.y + faceR * 0.22
    let eyeDrop    = faceR * 0.18
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(max(1.2, size * 0.018))
    ctx.setLineCap(.round)

    func arcEye(centerX: CGFloat) {
        let eye = CGMutablePath()
        eye.move(to: CGPoint(x: centerX - eyeHalfW, y: eyeY))
        eye.addQuadCurve(
            to: CGPoint(x: centerX + eyeHalfW, y: eyeY),
            control: CGPoint(x: centerX, y: eyeY + eyeDrop)
        )
        ctx.addPath(eye)
        ctx.strokePath()
    }
    arcEye(centerX: center.x - eyeOffsetX)
    arcEye(centerX: center.x + eyeOffsetX)

    // Sparkle dot to make the eyes feel expressive at medium+ sizes.
    if size >= 96 {
        ctx.setFillColor(ink)
        let sparkleR = size * 0.008
        for xSign: CGFloat in [-1, 1] {
            ctx.addEllipse(in: CGRect(
                x: center.x + xSign * eyeOffsetX - sparkleR,
                y: eyeY + eyeDrop * 0.45,
                width: sparkleR * 2,
                height: sparkleR * 2
            ))
            ctx.fillPath()
        }
    }

    // ── Nose: small rounded triangle ──
    let noseHalfW = faceR * 0.11
    let noseTopY  = center.y - faceR * 0.07
    let noseTipY  = noseTopY - faceR * 0.10
    let nosePath = CGMutablePath()
    nosePath.move(to: CGPoint(x: center.x - noseHalfW, y: noseTopY))
    nosePath.addLine(to: CGPoint(x: center.x + noseHalfW, y: noseTopY))
    nosePath.addQuadCurve(
        to: CGPoint(x: center.x - noseHalfW, y: noseTopY),
        control: CGPoint(x: center.x, y: noseTipY)
    )
    nosePath.closeSubpath()
    ctx.setFillColor(nose)
    ctx.addPath(nosePath)
    ctx.fillPath()

    // ── Mouth: W-ish ──
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(max(1.2, size * 0.016))
    let mouthY = noseTipY - faceR * 0.01
    let mouthReach = faceR * 0.18
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: center.x - mouthReach, y: mouthY))
    mouth.addQuadCurve(
        to: CGPoint(x: center.x, y: mouthY - faceR * 0.09),
        control: CGPoint(x: center.x - mouthReach * 0.55, y: mouthY - faceR * 0.13)
    )
    mouth.addQuadCurve(
        to: CGPoint(x: center.x + mouthReach, y: mouthY),
        control: CGPoint(x: center.x + mouthReach * 0.55, y: mouthY - faceR * 0.13)
    )
    ctx.addPath(mouth)
    ctx.strokePath()

    // ── Whiskers — only on larger icons ──
    if size >= 64 {
        ctx.setStrokeColor(NSColor(srgbRed: 0.28, green: 0.22, blue: 0.20, alpha: 0.72).cgColor)
        ctx.setLineWidth(max(0.8, size * 0.0055))
        let whiskerY = center.y - faceR * 0.18
        let spacing  = faceR * 0.11
        for direction: CGFloat in [-1, 1] {
            for i in -1...1 {
                let yOffset = CGFloat(i) * spacing
                let start = CGPoint(
                    x: center.x + direction * faceR * 0.48,
                    y: whiskerY + yOffset
                )
                let end = CGPoint(
                    x: center.x + direction * faceR * 1.06,
                    y: whiskerY + yOffset + direction * CGFloat(i) * spacing * 0.35
                )
                let w = CGMutablePath()
                w.move(to: start)
                w.addLine(to: end)
                ctx.addPath(w)
                ctx.strokePath()
            }
        }
    }

    // ── Clipboard emblem in lower right (brand tie-in) ──
    if size >= 128 {
        let cbW: CGFloat = size * 0.18
        let cbH: CGFloat = size * 0.21
        let cbX: CGFloat = size * 0.72
        let cbY: CGFloat = size * 0.07
        let cbBG = NSColor(srgbRed: 1.00, green: 0.97, blue: 0.92, alpha: 0.95).cgColor
        let cbLine = NSColor(srgbRed: 0.20, green: 0.15, blue: 0.12, alpha: 0.70).cgColor

        // Board body
        let board = CGPath(
            roundedRect: CGRect(x: cbX, y: cbY, width: cbW, height: cbH),
            cornerWidth: cbW * 0.12,
            cornerHeight: cbW * 0.12,
            transform: nil
        )
        ctx.setFillColor(cbBG)
        ctx.addPath(board)
        ctx.fillPath()
        ctx.setStrokeColor(cbLine)
        ctx.setLineWidth(max(1, size * 0.008))
        ctx.addPath(board)
        ctx.strokePath()

        // Clip tab at top
        let clipW = cbW * 0.45
        let clipH = cbH * 0.18
        let clipRect = CGRect(
            x: cbX + (cbW - clipW) / 2,
            y: cbY + cbH - clipH * 0.55,
            width: clipW,
            height: clipH
        )
        let clipPath = CGPath(
            roundedRect: clipRect,
            cornerWidth: clipW * 0.2,
            cornerHeight: clipW * 0.2,
            transform: nil
        )
        ctx.setFillColor(cbLine)
        ctx.addPath(clipPath)
        ctx.fillPath()

        // Three content lines
        ctx.setStrokeColor(cbLine)
        ctx.setLineWidth(max(1, size * 0.009))
        ctx.setLineCap(.round)
        let lineInsetX = cbW * 0.18
        let lineStartY = cbY + cbH * 0.56
        let lineStep   = cbH * 0.15
        let lineLenLong  = cbW - lineInsetX * 2
        let lineLenShort = (cbW - lineInsetX * 2) * 0.65
        let lens: [CGFloat] = [lineLenLong, lineLenLong, lineLenShort]
        for (idx, len) in lens.enumerated() {
            let y = lineStartY - CGFloat(idx) * lineStep
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cbX + lineInsetX, y: y))
            path.addLine(to: CGPoint(x: cbX + lineInsetX + len, y: y))
            ctx.addPath(path)
            ctx.strokePath()
        }
    }
}

// MARK: - PNG export

func renderPNG(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    guard let gCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gCtx
    gCtx.cgContext.setShouldAntialias(true)
    gCtx.cgContext.interpolationQuality = .high
    drawCatIcon(in: gCtx.cgContext, size: CGFloat(pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [.interlaced: false])
}

// MARK: - Main

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let projectRoot = scriptURL
    .deletingLastPathComponent()    // scripts/
    .deletingLastPathComponent()    // project root
    .standardizedFileURL

// 1) Write PNGs into Assets.xcassets so the asset catalog still reflects the
//    same art. Xcode's actool will dedupe to 16/32/128/256 — that's fine;
//    the authoritative icon is the stand-alone icns produced below.
let iconsetURL = projectRoot.appending(path: "Clipo/Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for icon in iconSet {
    guard let data = renderPNG(pixelSize: icon.pixels) else {
        FileHandle.standardError.write(Data("✗ failed to render \(icon.filename)\n".utf8))
        exit(1)
    }
    let out = iconsetURL.appending(path: icon.filename)
    try? data.write(to: out)
    print("✓ \(icon.filename)  \(icon.pixels)×\(icon.pixels)  (\(data.count / 1024) KB)")
}

let contentsImages: [[String: Any]] = iconSet.map {
    [
        "idiom": $0.idiom,
        "size": $0.size,
        "scale": $0.scale,
        "filename": $0.filename,
    ]
}
let contents: [String: Any] = [
    "images": contentsImages,
    "info": ["author": "xcode", "version": 1],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconsetURL.appending(path: "Contents.json"))
print("✓ Contents.json")

// 2) Build a proper multi-resolution .icns (all 10 entries) via iconutil.
//    CFBundleIconFile in Info.plist points at this file, so it overrides
//    whatever actool packs from the asset catalog.
let iconsetStaging = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "Clipo-\(UUID().uuidString).iconset")
try? FileManager.default.removeItem(at: iconsetStaging)
try FileManager.default.createDirectory(at: iconsetStaging, withIntermediateDirectories: true)

for icon in iconSet {
    let src = iconsetURL.appending(path: icon.filename)
    let dst = iconsetStaging.appending(path: icon.filename)
    try? FileManager.default.copyItem(at: src, to: dst)
}

let icnsOut = projectRoot.appending(path: "Clipo/Resources/AppIcon.icns")
let iconutil = Process()
iconutil.launchPath = "/usr/bin/iconutil"
iconutil.arguments = ["-c", "icns", iconsetStaging.path, "-o", icnsOut.path]
let pipe = Pipe()
iconutil.standardOutput = pipe
iconutil.standardError = pipe
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0, FileManager.default.fileExists(atPath: icnsOut.path) {
    let sz = (try? FileManager.default.attributesOfItem(atPath: icnsOut.path)[.size] as? Int) ?? 0
    print("✓ AppIcon.icns  (\(sz / 1024) KB)")
} else {
    let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    FileHandle.standardError.write(Data("✗ iconutil failed: \(err)\n".utf8))
    exit(1)
}

// Clean up staging
try? FileManager.default.removeItem(at: iconsetStaging)
