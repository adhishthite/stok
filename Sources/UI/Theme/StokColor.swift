// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

/// Stok's app-side color tokens. Each token resolves per appearance: light, dark, and the
/// two Increase Contrast variants. Text tokens hold at least 4.5:1 on their surface in
/// every variant, and at least 7:1 under Increase Contrast. Glow tokens are decoration
/// only and never carry text or meaning. Settings keep the system accent on purpose.
enum StokColor {
  /// Indigo: links, selection, and the brand accent. From the asset catalog, so the
  /// Increase Contrast variants come from there. 6.1:1 on warm white, 8.9:1 on dark.
  static let accent = Color("StokAccent")
  /// Text-safe saffron. 5.9:1 on warm white, 5.9:1 on dark.
  static let saffron = dynamic(
    light: 0xA5460F, dark: 0xEE7944, lightHigh: 0x7F350A, darkHigh: 0xF8A57C)
  /// Text-safe green for "ready" and "sent". 5.9:1 on warm white, 6.7:1 on dark.
  static let green = dynamic(
    light: 0x496D21, dark: 0x7DB443, lightHigh: 0x3A5719, darkHigh: 0xA6D27A)
  /// Primary ink: the filled call-to-action button. White label on it is 16:1.
  static let ink = dynamic(light: 0x1E2033, dark: 0x2A2E48, lightHigh: 0x000000, darkHigh: 0x1E2033)
  /// Label color on an `ink` fill.
  static let onInk = dynamic(
    light: 0xFFFFFF, dark: 0xFFFFFF, lightHigh: 0xFFFFFF, darkHigh: 0xFFFFFF)
  /// A 1 pt edge that keeps the navy ink button distinct on a dark window.
  static let inkEdge = dynamic(
    light: 0x1E2033, dark: 0x5A6080, lightHigh: 0x000000, darkHigh: 0xC7D2FE)
  /// Warm white page for the setup and About art moments.
  static let surface = dynamic(
    light: 0xFFFBFA, dark: 0x17181F, lightHigh: 0xFFFFFF, darkHigh: 0x000000)
  /// Hairlines and line ornament on `surface`.
  static let hairline = dynamic(
    light: 0xD9D4E4, dark: 0x3A3F5C, lightHigh: 0x6E6A7C, darkHigh: 0x9AA0BF)
  /// The two halves of the hero glow: saffron bleeding into periwinkle.
  static let glowSaffron = dynamic(
    light: 0xF97316, dark: 0xF08A55, lightHigh: 0xF97316, darkHigh: 0xF08A55)
  static let glowPeriwinkle = dynamic(
    light: 0xA5BBFC, dark: 0x6A7FE6, lightHigh: 0xA5BBFC, darkHigh: 0x6A7FE6)

  /// Pastel chip fills. Ink text on each is at least 11:1; in dark mode the fill is a deep
  /// tint of the same hue and the text is light.
  static let chipSaffron = dynamic(
    light: 0xFEEDE6, dark: 0x3A2418, lightHigh: 0xFEEDE6, darkHigh: 0x3A2418)
  static let chipIndigo = dynamic(
    light: 0xE8EFFC, dark: 0x22284A, lightHigh: 0xE8EFFC, darkHigh: 0x22284A)
  static let chipGreen = dynamic(
    light: 0xE7F1DA, dark: 0x1F2B14, lightHigh: 0xE7F1DA, darkHigh: 0x1F2B14)
  static let chipText = dynamic(
    light: 0x1E2033, dark: 0xE8EFFC, lightHigh: 0x000000, darkHigh: 0xFFFFFF)

  private static func dynamic(light: Int, dark: Int, lightHigh: Int, darkHigh: Int) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
          .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ])
        switch match {
        case .darkAqua: return rgb(dark)
        case .accessibilityHighContrastAqua: return rgb(lightHigh)
        case .accessibilityHighContrastDarkAqua: return rgb(darkHigh)
        default: return rgb(light)
        }
      })
  }

  private static func rgb(_ hex: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
  }
}
