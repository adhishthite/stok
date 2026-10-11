// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import QuartzCore

extension OrbView {
  /// The orb's paint for one state: a lit base gradient, three drifting pools, the halo it
  /// casts on the pill, and an accent for state marks such as the processing comet.
  struct OrbColors {
    var core: NSColor
    var mid: NSColor
    var rim: NSColor
    var pools: [NSColor]
    var halo: NSColor
    var accent: NSColor

    // Warm voice: saffron glowing into periwinkle.
    static let listening = OrbColors(
      core: Palette.warmWhite, mid: Palette.saffron, rim: Palette.indigoDeep,
      pools: [Palette.saffron, Palette.periwinkle, Palette.saffronSoft], halo: Palette.saffron,
      accent: Palette.saffron)
    // Cool work: the indigo half only.
    static let processing = OrbColors(
      core: Palette.periwinkle, mid: Palette.indigo, rim: Palette.indigoDeep,
      pools: [Palette.indigo, Palette.periwinkle, Palette.indigoDeep], halo: Palette.indigo,
      accent: Palette.periwinkle)
    static let success = OrbColors(
      core: Palette.successLight, mid: Palette.success, rim: Palette.successDeep,
      pools: [Palette.successLight, Palette.success, Palette.successDeep], halo: Palette.success,
      accent: Palette.success)
    static let error = OrbColors(
      core: Palette.errorLight, mid: Palette.error, rim: Palette.errorDeep,
      pools: [Palette.errorLight, Palette.error, Palette.errorDeep], halo: Palette.error,
      accent: Palette.error)

    static func of(_ state: OrbState) -> OrbColors {
      switch state {
      case .listening, .locked: listening
      case .processing: processing
      case .success: success
      case .error: error
      }
    }

    static func mix(_ a: OrbColors, _ b: OrbColors, _ f: CGFloat) -> OrbColors {
      guard f < 1 else { return b }
      guard f > 0 else { return a }
      return OrbColors(
        core: lerp(a.core, b.core, f), mid: lerp(a.mid, b.mid, f), rim: lerp(a.rim, b.rim, f),
        pools: zip(a.pools, b.pools).map { lerp($0, $1, f) }, halo: lerp(a.halo, b.halo, f),
        accent: lerp(a.accent, b.accent, f))
    }

    private static func lerp(_ a: NSColor, _ b: NSColor, _ f: CGFloat) -> NSColor {
      Palette.blend(a, b, f)
    }
  }
}
