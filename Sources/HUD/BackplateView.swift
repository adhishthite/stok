// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import QuartzCore

/// The pill's surface: a near-black plate, and beside the bezel a faint specular rim that
/// sells the pill as glass. Layers only, so the width animation never redraws it on the
/// main thread: the plate is a background colour and the rim a gradient masked by the
/// capsule's stroked outline, rebuilt only when the size changes.
final class BackplateView: NSView {
  // The specular rim sells the pill as glass beside the bezel; wrapped in the pill-mode
  // aura it is a second, white outline fighting the tinted hairline, so it's off there.
  var specularRim: Bool = true {
    didSet { if specularRim != oldValue { refresh() } }
  }
  // Near-opaque beside the bezel; lowered in pill mode so the material underneath shows.
  var baseAlpha: CGFloat = 0.97 {
    didSet { if baseAlpha != oldValue { refresh() } }
  }

  private let rim = CAGradientLayer()
  private let rimMask = CAShapeLayer()
  private var rimSize: CGSize = .zero

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    build()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    build()
  }

  override var wantsUpdateLayer: Bool { true }

  private func build() {
    wantsLayer = true
    layer?.cornerCurve = .continuous
    rim.colors = [
      NSColor(white: 1.0, alpha: 0.28).cgColor, NSColor(white: 1.0, alpha: 0.10).cgColor,
      NSColor(white: 1.0, alpha: 0.04).cgColor,
    ]
    rim.locations = [0.0, 0.5, 1.0]
    rim.startPoint = CGPoint(x: 0.5, y: 1)
    rim.endPoint = CGPoint(x: 0.5, y: 0)
    rimMask.fillColor = nil
    rimMask.strokeColor = NSColor.white.cgColor
    rimMask.lineWidth = 1.0
    rim.mask = rimMask
    let off: [String: CAAction] = [
      "position": NSNull(), "bounds": NSNull(), "path": NSNull(), "hidden": NSNull(),
      "backgroundColor": NSNull(), "frame": NSNull(),
    ]
    rim.actions = off
    rimMask.actions = off
    layer?.actions = off
    layer?.addSublayer(rim)
    refresh()
  }

  override func layout() {
    super.layout()
    refresh()
  }

  private func refresh() {
    guard let layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    layer.backgroundColor =
      NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.059, alpha: baseAlpha).cgColor
    rim.isHidden = !specularRim
    guard specularRim, bounds.size != rimSize else { return }
    rimSize = bounds.size
    rim.frame = bounds
    rimMask.frame = bounds
    let radius = bounds.height / 2.0
    rimMask.path = CGPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius - 0.5,
      cornerHeight: radius - 0.5, transform: nil)
  }
}
