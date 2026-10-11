// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Fills for icon tiles: a light-to-deep gradient of one palette hue. The white glyph on
/// the deep end clears 4.5:1 for every tint; Increase Contrast uses the deep end alone.
enum TileTint {
  case saffron, indigo, periwinkle, deepIndigo, green, pink, ink

  var colors: (top: Color, bottom: Color) {
    switch self {
    case .saffron: (Self.rgb(0xF2884F), Self.rgb(0xC2410C))
    case .indigo: (Self.rgb(0x6A88E2), Self.rgb(0x4250D5))
    case .periwinkle: (Self.rgb(0x8B96F6), Self.rgb(0x4F5FD0))
    case .deepIndigo: (Self.rgb(0x4250D5), Self.rgb(0x212191))
    case .green: (Self.rgb(0x7DB443), Self.rgb(0x496D21))
    case .pink: (Self.rgb(0xE879A0), Self.rgb(0xB83A6B))
    case .ink: (Self.rgb(0x5A6080), Self.rgb(0x1E2033))
    }
  }

  private static func rgb(_ hex: Int) -> Color {
    Color(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}
