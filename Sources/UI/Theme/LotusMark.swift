// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Stok's lotus, filled, for brand moments: the setup header and About. Same petals as the
/// app icon, drawn outer to inner; each petal cuts a transparent hairline gap into the ones
/// beneath it, so the mark sits on any background. Scales with Dynamic Type when given a
/// scaled size.
struct LotusMark: View {
  var size: CGFloat = 40

  // (angle in degrees, length, width) in icon units; outer petals first.
  private static let petals: [(Double, CGFloat, CGFloat)] = [
    (-72, 300, 250), (72, 300, 250), (-38, 430, 300), (38, 430, 300), (0, 540, 320),
  ]

  var body: some View {
    let fill = LinearGradient(
      colors: [StokColor.glowPeriwinkle, StokColor.accent, StokColor.glowSaffron],
      startPoint: .top, endPoint: .bottom)
    ZStack {
      ForEach(Self.petals.indices, id: \.self) { index in
        let petal = Petal(petal: Self.petals[index])
        petal.stroke(.black, lineWidth: max(1.2, size / 30)).blendMode(.destinationOut)
        petal.fill(fill)
      }
    }
    .compositingGroup()
    .frame(width: size, height: size * 0.82)
    .accessibilityHidden(true)
  }
}

/// One lotus petal fitted into the mark's box, base at the bottom centre.
private struct Petal: Shape {
  let petal: (Double, CGFloat, CGFloat)

  func path(in rect: CGRect) -> Path {
    let unit = rect.height / 600
    let base = CGPoint(x: rect.midX, y: rect.maxY - 20 * unit)
    let l = petal.1 * unit
    let w = petal.2 * unit / 2
    var path = Path()
    path.move(to: .zero)
    path.addCurve(
      to: CGPoint(x: 0, y: -l), control1: CGPoint(x: w * 1.45, y: -l * 0.30),
      control2: CGPoint(x: w * 0.95, y: -l * 0.86))
    path.addCurve(
      to: .zero, control1: CGPoint(x: -w * 0.95, y: -l * 0.86),
      control2: CGPoint(x: -w * 1.45, y: -l * 0.30))
    path.closeSubpath()
    return path.applying(
      CGAffineTransform(translationX: base.x, y: base.y).rotated(by: petal.0 * .pi / 180))
  }
}
