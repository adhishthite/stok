// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A horizontal rule for Stok's art moments: 1 pt in the hairline token, 2 pt under
/// Increase Contrast so it still reads.
struct Hairline: View {
  var color: Color = StokColor.hairline
  @Environment(\.colorSchemeContrast) private var systemContrast
  @Environment(\.forceIncreasedContrast) private var forcedContrast

  var body: some View {
    let increased = systemContrast == .increased || forcedContrast
    Rectangle().fill(color).frame(height: increased ? 2 : 1)
      .accessibilityHidden(true)
  }
}
