// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The top of setup: Stok's one art moment before the form. The lotus on a hairline rule
/// with two sparkles, and a serif line in New York, over the hero glow.
struct SetupHero: View {
  let shortcut: String
  @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 60

  var body: some View {
    VStack(spacing: 14) {
      ZStack {
        HStack(spacing: 0) {
          rule
          Color.clear.frame(width: markSize + 28)
          rule
        }
        LotusMark(size: markSize)
        Sparkle().fill(StokColor.glowSaffron).frame(width: 10, height: 10)
          .offset(x: -(markSize / 2 + 64), y: -16)
        Sparkle().fill(StokColor.glowSaffron).frame(width: 8, height: 8)
          .offset(x: markSize / 2 + 52, y: -22)
      }
      .accessibilityHidden(true)
      VStack(spacing: 6) {
        Text("Speak in your language.")
          .font(.system(size: 28, weight: .regular, design: .serif))
          .foregroundStyle(.primary)
          .accessibilityAddTraits(.isHeader)
        Text("Hold \(shortcut), talk, and let go. Stok types it where you are writing.")
          .font(.callout).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 20)
  }

  private var rule: some View {
    Hairline(color: .white.opacity(0.85))
  }
}
