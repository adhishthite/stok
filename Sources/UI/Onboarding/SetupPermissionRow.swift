// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// One permission in setup: what it is for, and either Allow or a granted check that
/// bounces once when it arrives (no bounce under Reduce Motion).
struct SetupPermissionRow: View {
  let name: String
  let purpose: String
  let symbol: String
  let tint: TileTint
  let granted: Bool
  let allow: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 10) {
      IconTile(symbol: symbol, tint: tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
        Text(purpose).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if granted {
        Label("Allowed", systemImage: "checkmark.circle.fill")
          .labelStyle(.titleAndIcon)
          .foregroundStyle(StokColor.green)
          .symbolEffect(.bounce, value: reduceMotion ? false : granted)
      } else {
        Button("Allow…", action: allow).accessibilityLabel("Allow \(name)")
      }
    }
    .accessibilityElement(children: .contain)
  }
}
