// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import QuartzCore

final class HoldRingView: NSView {
  override func makeBackingLayer() -> CALayer {
    let shape = CAShapeLayer()
    shape.fillColor = nil
    shape.lineCap = .round
    shape.strokeEnd = 0.0
    shape.opacity = 0.0
    // No layer shadow: a shadow without a shadowPath renders offscreen every frame while
    // the stroke sweeps. The rim's opacity carries the emphasis instead.
    shape.actions = [
      "path": NSNull(), "strokeEnd": NSNull(), "opacity": NSNull(), "lineWidth": NSNull(),
      "strokeColor": NSNull(), "bounds": NSNull(), "position": NSNull(),
    ]
    return shape
  }

  private var shape: CAShapeLayer? { layer as? CAShapeLayer }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    wantsLayer = true
  }

  // Every setter skips an unchanged value, so a resting ring writes nothing.
  var path: CGPath? {
    didSet { if path !== oldValue { shape?.path = path } }
  }
  var progress: CGFloat = 0.0 {
    didSet { if progress != oldValue { shape?.strokeEnd = progress } }
  }
  var lineWidth: CGFloat = 2.5 {
    didSet { if lineWidth != oldValue { shape?.lineWidth = lineWidth } }
  }
  var strength: Float = 0.0 {
    didSet { if strength != oldValue { shape?.opacity = strength } }
  }
  var color: CGColor = NSColor.white.cgColor {
    didSet { if color !== oldValue { shape?.strokeColor = color } }
  }

  /// Sweeps the rim from `start` to closed over `duration` seconds, in the render server:
  /// the stroke advances, the hue walks from saffron toward the lock's warm white, and the
  /// last 15% comes up to full strength so the closing moment reads as imminent. The model
  /// values land on the closed state, so nothing jumps when the animation ends.
  func sweep(from start: CGFloat, duration: CFTimeInterval) {
    guard let shape, duration > 0 else { return }
    stopSweep()
    let begin = max(0, min(1, start))
    let end = CAKeyframeAnimation(keyPath: "strokeEnd")
    end.values = [begin, 1]
    end.duration = duration
    end.calculationMode = .linear
    let hue = CAKeyframeAnimation(keyPath: "strokeColor")
    hue.values = Palette.holdColorStops(from: begin)
    hue.duration = duration
    let strength = CAKeyframeAnimation(keyPath: "opacity")
    let closingStart = max(0, (0.85 - begin) / max(0.0001, 1 - begin))
    strength.values = [0.85, 0.85, 1.0]
    strength.keyTimes = [0, NSNumber(value: Double(closingStart)), 1]
    strength.duration = duration
    for animation in [end, hue, strength] {
      animation.fillMode = .forwards
      animation.isRemovedOnCompletion = false
      shape.add(animation, forKey: "sweep.\(animation.keyPath ?? "")")
    }
  }

  func stopSweep() {
    guard let shape else { return }
    for key in ["sweep.strokeEnd", "sweep.strokeColor", "sweep.opacity"] {
      shape.removeAnimation(forKey: key)
    }
  }
}
