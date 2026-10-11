// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit

/// The menu-bar form of Stok's lotus mark: three petals, drawn as a template image so
/// macOS tints it for light, dark, and a selected menu-bar item. The app icon draws the
/// same petal shape in Scripts/generate_icon.swift.
@MainActor
enum StokGlyph {
  static let ready: NSImage = {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { _ in
      let base = NSPoint(x: 9, y: 2.6)
      // (angle in degrees, length, width) in points.
      let petals: [(CGFloat, CGFloat, CGFloat)] = [(-50, 9.6, 7.4), (50, 9.6, 7.4), (0, 13.4, 8.4)]
      for (angle, length, width) in petals {
        let path = petal(length: length, width: width)
        let transform = NSAffineTransform()
        transform.translateX(by: base.x, yBy: base.y)
        transform.rotate(byDegrees: -angle)
        path.transform(using: transform as AffineTransform)
        // A cleared outline keeps a hairline gap where the centre petal overlaps the others.
        NSGraphicsContext.current?.compositingOperation = .clear
        path.lineWidth = 1.4
        path.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setFill()
        path.fill()
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Stok"
    return image
  }()

  private static func petal(length l: CGFloat, width: CGFloat) -> NSBezierPath {
    let w = width / 2
    let path = NSBezierPath()
    path.move(to: .zero)
    path.curve(
      to: NSPoint(x: 0, y: l), controlPoint1: NSPoint(x: w * 1.45, y: l * 0.30),
      controlPoint2: NSPoint(x: w * 0.95, y: l * 0.86))
    path.curve(
      to: .zero, controlPoint1: NSPoint(x: -w * 0.95, y: l * 0.86),
      controlPoint2: NSPoint(x: -w * 1.45, y: l * 0.30))
    path.close()
    return path
  }
}
