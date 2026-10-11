// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Stok's one tile spec, used everywhere a row carries an icon: a white hierarchical symbol
/// on a 22 pt continuous-corner square filled with a palette gradient. Decorative; the
/// row's own text carries the meaning.
struct IconTile: View {
  let symbol: String
  let tint: TileTint
  private let size: CGFloat = 22
  @Environment(\.colorSchemeContrast) private var systemContrast
  @Environment(\.forceIncreasedContrast) private var forcedContrast
  private var increased: Bool { systemContrast == .increased || forcedContrast }

  var body: some View {
    let colors = tint.colors
    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
      .fill(
        increased
          ? AnyShapeStyle(colors.bottom)
          : AnyShapeStyle(
            LinearGradient(
              colors: [colors.top, colors.bottom], startPoint: .top, endPoint: .bottom))
      )
      .overlay {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
          .strokeBorder(.white.opacity(increased ? 0.5 : 0.18), lineWidth: increased ? 1 : 0.5)
      }
      .overlay {
        Image(systemName: symbol)
          .font(.system(size: size * 0.56, weight: .semibold))
          .foregroundStyle(.white)
          .symbolRenderingMode(.hierarchical)
      }
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}
