// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The art-moment backdrop: a saffron pool bleeding into periwinkle at the top, settling
/// into the warm surface below so text there sits on a calm ground. Decoration only.
struct HeroGlow: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var systemContrast
  @Environment(\.forceIncreasedContrast) private var forcedContrast
  private var increased: Bool { systemContrast == .increased || forcedContrast }

  var body: some View {
    let strength: Double = increased ? 0.4 : (colorScheme == .dark ? 0.62 : 0.85)
    ZStack {
      StokColor.surface
      RadialGradient(
        colors: [StokColor.glowSaffron.opacity(strength), .clear],
        center: UnitPoint(x: 0.22, y: -0.1),
        startRadius: 0, endRadius: 300)
      RadialGradient(
        colors: [
          StokColor.glowPeriwinkle.opacity(strength),
          StokColor.glowPeriwinkle.opacity(strength * 0.4), .clear,
        ],
        center: UnitPoint(x: 0.74, y: 0.05), startRadius: 0, endRadius: 400)
      LinearGradient(
        colors: [.clear, StokColor.surface], startPoint: UnitPoint(x: 0.5, y: 0.35),
        endPoint: .bottom)
    }
    .accessibilityHidden(true)
  }
}
