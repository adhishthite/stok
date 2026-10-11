// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The menu-bar item: the Stok lotus while ready, a system symbol for every other state
/// so a glance tells listening, working, paused, and trouble apart by shape.
struct MenuBarLabel: View {
  @Environment(DictationStore.self) private var store
  var body: some View {
    Group {
      if store.status == .ready {
        Image(nsImage: StokGlyph.ready)
      } else {
        Image(systemName: store.status.symbol)
      }
    }
    .accessibilityLabel("Stok, \(store.status.rawValue)")
  }
}
