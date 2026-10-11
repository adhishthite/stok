// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The primary call to action on Stok's art-moment screens: an ink capsule with a light
/// label (16:1 in light mode, 13:1 on the lifted navy in dark mode). Dimmed, not
/// recoloured, when disabled.
struct InkButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.medium))
      .foregroundStyle(StokColor.onInk)
      .padding(.horizontal, 18).padding(.vertical, 7)
      // Two fills instead of a stroke: the 1 pt edge is the outer capsule showing around
      // the inner one.
      .background(StokColor.ink, in: .capsule)
      .padding(1)
      .background(StokColor.inkEdge, in: .capsule)
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
      .contentShape(.capsule)
  }
}
