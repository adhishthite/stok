// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import QuartzCore

struct SpringChannel {
  var value: CGFloat
  var velocity: CGFloat = 0.0
  var target: CGFloat
  var stiffness: CGFloat
  var dampingRatio: CGFloat
  // Settle threshold in the channel's own units (a 0-1 progress and a width in points
  // need different scales).
  var epsilon: CGFloat = 0.001

  /// Exactly at rest: the value is the target and nothing moves. A step does nothing.
  var atRest: Bool { value == target && velocity == 0.0 }

  // Once within epsilon the channel snaps to rest, so a settled spring stops producing new
  // values. Without this its value drifts by tiny amounts forever and every consumer that
  // compares values (frame state, layer writes) sees a change each frame.
  mutating func step(dt: CGFloat) {
    guard !atRest else { return }
    defer { if settled { snap() } }
    let damping = 2.0 * sqrt(stiffness) * dampingRatio
    let substeps = max(1, Int(ceil(dt / (1.0 / 120.0))))
    let h = dt / CGFloat(substeps)
    for _ in 0..<substeps {
      velocity += (-stiffness * (value - target) - damping * velocity) * h
      value += velocity * h
    }
  }

  var settled: Bool {
    abs(value - target) < epsilon && abs(velocity) < epsilon * 25.0
  }

  mutating func snap() {
    value = target
    velocity = 0.0
  }
}
