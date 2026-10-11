// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A four-point sparkle: four concave arcs meeting at sharp points. Decoration only.
struct Sparkle: Shape {
  func path(in rect: CGRect) -> Path {
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let rx = rect.width / 2
    let ry = rect.height / 2
    let k: CGFloat = 0.16
    var path = Path()
    path.move(to: CGPoint(x: c.x, y: c.y - ry))
    path.addQuadCurve(
      to: CGPoint(x: c.x + rx, y: c.y), control: CGPoint(x: c.x + rx * k, y: c.y - ry * k))
    path.addQuadCurve(
      to: CGPoint(x: c.x, y: c.y + ry), control: CGPoint(x: c.x + rx * k, y: c.y + ry * k))
    path.addQuadCurve(
      to: CGPoint(x: c.x - rx, y: c.y), control: CGPoint(x: c.x - rx * k, y: c.y + ry * k))
    path.addQuadCurve(
      to: CGPoint(x: c.x, y: c.y - ry), control: CGPoint(x: c.x - rx * k, y: c.y - ry * k))
    path.closeSubpath()
    return path
  }
}
