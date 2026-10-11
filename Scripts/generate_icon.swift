// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit

// Stok's original vector artwork. Run `make icon` to regenerate the macOS asset set.
func color(_ hex: Int) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

@MainActor
func drawIcon(pixels: Int) throws -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else { throw CocoaError(.coderInvalidValue) }
  NSGraphicsContext.saveGraphicsState()
  defer { NSGraphicsContext.restoreGraphicsState() }
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
  context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

  let cg = context.cgContext
  // NSShadow works in device pixels and ignores the scale above, so shadows scale here.
  let k = CGFloat(pixels) / 1024
  let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
  let tile = NSBezierPath(roundedRect: tileRect, xRadius: 184, yRadius: 184)

  // Ink tile with a grounding shadow.
  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
  shadow.shadowBlurRadius = 24 * k
  shadow.shadowOffset = NSSize(width: 0, height: -14 * k)
  shadow.set()
  color(0x1E2033).setFill()
  tile.fill()
  NSGraphicsContext.restoreGraphicsState()

  // The voice glow: saffron rising from below, periwinkle settling from above, meeting
  // behind the mark. Two soft radial pools, no bands.
  NSGraphicsContext.saveGraphicsState()
  tile.addClip()
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  func pool(_ hex: Int, alpha: CGFloat, center: CGPoint, radius: CGFloat) {
    let colors =
      [
        color(hex).withAlphaComponent(alpha).cgColor,
        color(hex).withAlphaComponent(alpha * 0.45).cgColor,
        color(hex).withAlphaComponent(0).cgColor,
      ] as CFArray
    guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1])
    else { return }
    cg.drawRadialGradient(
      gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
      options: [])
  }
  if pixels <= 32 {
    // 16 and 32 px: two flat bands, periwinkle over saffron, so the tile stays crisp where
    // soft pools would turn to mud.
    color(0x6A88E2).setFill()
    NSRect(x: 0, y: 420, width: 1024, height: 604).fill()
    color(0xE96C2F).setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 420).fill()
    NSGraphicsContext.restoreGraphicsState()
  } else {
    pool(0x3A3F5C, alpha: 1, center: CGPoint(x: 512, y: 924), radius: 820)
    pool(0x556ADC, alpha: 0.95, center: CGPoint(x: 700, y: 860), radius: 620)
    pool(0xA5BBFC, alpha: 0.55, center: CGPoint(x: 640, y: 760), radius: 360)
    pool(0xF97316, alpha: 1, center: CGPoint(x: 360, y: 180), radius: 640)
    pool(0xEE7944, alpha: 0.9, center: CGPoint(x: 512, y: 300), radius: 420)
    pool(0xE879A0, alpha: 0.35, center: CGPoint(x: 560, y: 520), radius: 300)
    NSGraphicsContext.restoreGraphicsState()
  }

  // Glass rim.
  NSColor.white.withAlphaComponent(0.18).setStroke()
  tile.lineWidth = 2
  tile.stroke()

  // The mark: a lotus of sound. Pointed petals rise from one base, stepped in height like
  // a level meter: the tallest in the middle. Gaps are cut between petals inside a
  // transparency layer so the glow shows through. As a half fan of a few petals it never
  // reads as a wheel. Three petals at 16 px, where five would fuse.
  let small = pixels <= 32
  let scale: CGFloat = small ? 0.95 : 0.8
  let base = CGPoint(x: 512, y: small ? 270 : 318)
  let petals: [(angle: CGFloat, length: CGFloat, width: CGFloat)] =
    small
    ? [(-50, 420, 380), (50, 420, 380), (0, 600, 400)]
    : [(-72, 300, 250), (72, 300, 250), (-38, 430, 300), (38, 430, 300), (0, 540, 320)]
  let gap: CGFloat = small ? 64 : 30
  func petalPath(_ petal: (angle: CGFloat, length: CGFloat, width: CGFloat)) -> NSBezierPath {
    let path = NSBezierPath()
    let l = petal.length
    let w = petal.width / 2
    path.move(to: NSPoint(x: 0, y: 0))
    path.curve(
      to: NSPoint(x: 0, y: l), controlPoint1: NSPoint(x: w * 1.45, y: l * 0.30),
      controlPoint2: NSPoint(x: w * 0.95, y: l * 0.86))
    path.curve(
      to: NSPoint(x: 0, y: 0), controlPoint1: NSPoint(x: -w * 0.95, y: l * 0.86),
      controlPoint2: NSPoint(x: -w * 1.45, y: l * 0.30))
    path.close()
    let transform = NSAffineTransform()
    transform.translateX(by: base.x, yBy: base.y)
    transform.scale(by: scale)
    transform.rotate(byDegrees: -petal.angle)
    path.transform(using: transform as AffineTransform)
    return path
  }
  NSGraphicsContext.saveGraphicsState()
  let markShadow = NSShadow()
  markShadow.shadowColor = color(0x1E2033).withAlphaComponent(0.35)
  markShadow.shadowOffset = NSSize(width: 0, height: -6 * k)
  markShadow.shadowBlurRadius = 14 * k
  markShadow.set()
  cg.beginTransparencyLayer(auxiliaryInfo: nil)
  for petal in petals {
    let path = petalPath(petal)
    // Cut a gap around the nearer petal, then fill it.
    cg.saveGState()
    cg.setBlendMode(.clear)
    path.lineWidth = gap
    path.lineJoinStyle = .round
    path.stroke()
    cg.restoreGState()
    color(0xFFFBFA).setFill()
    path.fill()
  }
  cg.endTransparencyLayer()
  NSGraphicsContext.restoreGraphicsState()

  // A four-point sparkle above the right petals, only where it stays crisp.
  if pixels >= 128 {
    let c = CGPoint(x: 752, y: 744)
    let r: CGFloat = 54
    let k: CGFloat = 0.18
    let star = NSBezierPath()
    star.move(to: NSPoint(x: c.x, y: c.y + r))
    star.curve(
      to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + r * k, y: c.y + r * k),
      controlPoint2: NSPoint(x: c.x + r * k, y: c.y + r * k))
    star.curve(
      to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + r * k, y: c.y - r * k),
      controlPoint2: NSPoint(x: c.x + r * k, y: c.y - r * k))
    star.curve(
      to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - r * k, y: c.y - r * k),
      controlPoint2: NSPoint(x: c.x - r * k, y: c.y - r * k))
    star.curve(
      to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - r * k, y: c.y + r * k),
      controlPoint2: NSPoint(x: c.x - r * k, y: c.y + r * k))
    star.close()
    color(0xFFE8B7).setFill()
    star.fill()
  }

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.coderInvalidValue)
  }
  return png
}

let output = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let filename = "icon_\(points)x\(points)@\(scale)x.png"
    let png = try MainActor.assumeIsolated { try drawIcon(pixels: points * scale) }
    try png.write(to: output.appendingPathComponent(filename))
    images.append([
      "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename,
    ])
  }
}
let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
  .write(to: output.appendingPathComponent("Contents.json"))
print("Generated all 10 macOS AppIcon representations.")
