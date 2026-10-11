// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import QuartzCore

enum Palette {
  static let p3ColorSpace =
    CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

  // Stok's HUD tokens. The pill is always near-black (#0B0B0F), so every token is tuned for
  // that surface; the contrast against it is noted beside each one. Warm means "hearing
  // you", cool means "working on it": listening glows saffron, processing glows indigo.
  // A state is never told by color alone: each one also has its own glyph and eyebrow word.

  /// Saffron #F97316, 7.0:1. Listening light, the live caret, the hold sweep.
  static let saffron = rgb(0xF9, 0x73, 0x16)
  /// Soft saffron #EE7944, 7.0:1. The second listening anchor.
  static let saffronSoft = rgb(0xEE, 0x79, 0x44)
  /// Warm white #FFFBFA, 19:1. The quiet passage between the warm and cool anchors.
  static let warmWhite = rgb(0xFF, 0xFB, 0xFA)
  /// Periwinkle #A5B4FC, 9.9:1. Processing eyebrow and glyph.
  static let periwinkle = rgb(0xA5, 0xB4, 0xFC)
  /// Indigo #818CF8, 6.6:1. Processing light.
  static let indigo = rgb(0x81, 0x8C, 0xF8)
  /// Deep indigo #556ADC, 4.2:1. Glow depth only, never text.
  static let indigoDeep = rgb(0x55, 0x6A, 0xDC)
  /// Magenta #E879A0, 7.2:1. One orb lobe, between saffron and indigo.
  static let magenta = rgb(0xE8, 0x79, 0xA0)
  /// Green #7DB443, 8.0:1. Success: a checkmark and the word "Done".
  static let success = rgb(0x7D, 0xB4, 0x43)
  /// Coral #F87171, 7.1:1. Failure: a triangle and the word "Error".
  static let error = rgb(0xF8, 0x71, 0x71)
  /// Orb shading for success and failure: a lit top and a deep rim around the main token.
  static let successLight = rgb(0xC5, 0xE6, 0x9C)
  static let successDeep = rgb(0x49, 0x6D, 0x21)
  static let errorLight = rgb(0xFF, 0xC2, 0xB8)
  static let errorDeep = rgb(0xB0, 0x3A, 0x3A)
  /// A locked hold: the closed rim. Warm white, 19:1; the padlock itself is white.
  static let locked = warmWhite

  private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
  }

  // MARK: OKLCH interpolation (Ottosson's OKLab, pure math - no dependencies)
  //
  // The chromatic loop interpolates in OKLCH rather than raw P3 RGB: straight RGB lerps
  // between distant hues dip through darker, muddier midpoints, while OKLCH holds perceived
  // lightness and chroma constant and swings hue along the shortest arc - the gradient stays
  // equally luminous the whole way around. Anchors remain authored as Display P3 values.

  private static func srgbToLinear(_ c: CGFloat) -> CGFloat {
    let sign: CGFloat = c < 0 ? -1 : 1
    let v = abs(c)
    return sign * (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4))
  }

  private static func linearToSrgb(_ c: CGFloat) -> CGFloat {
    let sign: CGFloat = c < 0 ? -1 : 1
    let v = abs(c)
    return sign * (v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055)
  }

  private static func signedCbrt(_ v: CGFloat) -> CGFloat {
    v < 0 ? -pow(-v, 1.0 / 3.0) : pow(v, 1.0 / 3.0)
  }

  // Wide-gamut anchors are carried through extended sRGB (components may leave 0...1),
  // which the OKLab linear algebra handles without gamut clipping.
  static func toOKLCh(_ color: NSColor) -> OKLCh {
    let c = color.usingColorSpace(.extendedSRGB) ?? color
    let r = srgbToLinear(c.redComponent)
    let g = srgbToLinear(c.greenComponent)
    let b = srgbToLinear(c.blueComponent)

    let l = signedCbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = signedCbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = signedCbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

    let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

    return OKLCh(lightness: lightness, chroma: sqrt(a * a + bb * bb), h: atan2(bb, a))
  }

  static func fromOKLCh(_ lch: OKLCh) -> NSColor {
    let a = lch.chroma * cos(lch.h)
    let bb = lch.chroma * sin(lch.h)

    let l = pow(lch.lightness + 0.3963377774 * a + 0.2158037573 * bb, 3)
    let m = pow(lch.lightness - 0.1055613458 * a - 0.0638541728 * bb, 3)
    let s = pow(lch.lightness - 0.0894841775 * a - 1.2914855480 * bb, 3)

    let r = linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
    let g = linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
    let b = linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)

    return NSColor(colorSpace: .extendedSRGB, components: [r, g, b, 1.0], count: 4)
  }

  // Anchor stops converted once; orbColor below is pure math per call.
  private static let spectrumAnchors: [OKLCh] = [saffron, magenta, indigo, periwinkle].map(
    toOKLCh)

  // Saffron fades through warm white into periwinkle and indigo and back, the way a
  // dusk sky turns. The white passages keep the swing from crossing the coral error hue.
  private static let listeningAnchors: [OKLCh] = [
    saffron, saffronSoft, warmWhite, periwinkle, indigo, warmWhite,
  ].map(toOKLCh)

  private static let processingAnchors: [OKLCh] = [indigo, periwinkle, indigoDeep, periwinkle]
    .map(toOKLCh)

  private static let holdAnchors: [OKLCh] = [saffron, locked].map(toOKLCh)

  // Listening tint for the aura. Each anchor holds for most of its segment, then eases
  // into the next. This is deliberately the opposite of orbColor, which spreads all hues
  // across space at once; here the colors are distributed across time.
  static func listeningColor(at t: CGFloat) -> NSColor {
    cycle(listeningAnchors, at: t)
  }

  // Processing tint: the cool half of the palette only, so "working" never looks like
  // "listening" even in a glance at the aura.
  static func processingColor(at t: CGFloat) -> NSColor {
    cycle(processingAnchors, at: t)
  }

  // The hold-to-lock rim walks from saffron to the warm white of the locked rim, so the
  // closing moment hands straight into the lock without a hue jump.
  static func holdColor(at progress: CGFloat) -> NSColor {
    let f = max(0.0, min(1.0, progress))
    return mix(holdAnchors[0], holdAnchors[1], f)
  }

  /// The hold sweep's colours from `start` to closed, as keyframe values: 16 stops sampled
  /// once from a precomputed table, so starting a sweep makes no colours.
  static func holdColorStops(from start: CGFloat) -> [CGColor] {
    let first = Int((max(0, min(1, start)) * CGFloat(holdTable.count - 1)).rounded())
    let span = holdTable.count - 1 - first
    guard span > 0 else { return [holdTable[holdTable.count - 1]] }
    return (0...16).map { holdTable[first + span * $0 / 16] }
  }

  private static let holdTable: [CGColor] = (0...64).map {
    holdColor(at: CGFloat($0) / 64).cgColor
  }

  /// The locked rim's colour, made once.
  static let lockedRim: CGColor = locked.cgColor

  private static func cycle(_ anchors: [OKLCh], at t: CGFloat) -> NSColor {
    let wrapped = t.truncatingRemainder(dividingBy: 1.0)
    let count = anchors.count
    let pos = (wrapped < 0 ? wrapped + 1.0 : wrapped) * CGFloat(count)
    let seg = Int(pos) % count
    var frac = pos - CGFloat(Int(pos))

    let dwell: CGFloat = 0.60
    if frac <= dwell {
      frac = 0
    } else {
      let f = (frac - dwell) / (1.0 - dwell)
      frac = f * f * (3 - 2 * f)  // smoothstep: no visible seam at either end of the fade
    }

    return mix(anchors[seg], anchors[(seg + 1) % count], frac)
  }

  /// Blends two colours through OKLCh, so a hue change never passes through grey.
  static func blend(_ a: NSColor, _ b: NSColor, _ frac: CGFloat) -> NSColor {
    mix(toOKLCh(a), toOKLCh(b), frac)
  }

  private static func mix(_ c1: OKLCh, _ c2: OKLCh, _ frac: CGFloat) -> NSColor {
    // White is achromatic, so its stored hue is numerically arbitrary; borrow the
    // chromatic endpoint's hue so the fade is a pure desaturation, not a hue swing.
    var h1 = c1.h
    var h2 = c2.h
    if c1.chroma < 0.02 { h1 = h2 }
    if c2.chroma < 0.02 { h2 = h1 }
    var dh = h2 - h1
    if dh > .pi { dh -= 2 * .pi }
    if dh < -.pi { dh += 2 * .pi }

    return fromOKLCh(
      OKLCh(
        lightness: c1.lightness + (c2.lightness - c1.lightness) * frac,
        chroma: c1.chroma + (c2.chroma - c1.chroma) * frac,
        h: h1 + dh * frac
      ))
  }

  static func orbColor(at t: CGFloat) -> NSColor {
    let wrapped = t.truncatingRemainder(dividingBy: 1.0)
    let pos = (wrapped < 0 ? wrapped + 1.0 : wrapped) * 4.0
    let seg = Int(pos) % 4
    let frac = pos - CGFloat(Int(pos))

    let c1 = spectrumAnchors[seg]
    let c2 = spectrumAnchors[(seg + 1) % 4]

    // Shortest-arc hue interpolation keeps the loop from detouring through the far
    // side of the hue wheel between adjacent anchors.
    var dh = c2.h - c1.h
    if dh > .pi { dh -= 2 * .pi }
    if dh < -.pi { dh += 2 * .pi }

    return fromOKLCh(
      OKLCh(
        lightness: c1.lightness + (c2.lightness - c1.lightness) * frac,
        chroma: c1.chroma + (c2.chroma - c1.chroma) * frac,
        h: c1.h + dh * frac
      ))
  }
}
