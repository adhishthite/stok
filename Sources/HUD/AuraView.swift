// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import QuartzCore

final class AuraView: NSView {

  var notchRect: NSRect = .zero {
    didSet { if notchRect != oldValue { renderLayers() } }
  }
  /// Voice level, 0...1. The aura answers it directly, at the rate levels arrive, so it
  /// needs no display-link frames of its own.
  var audioLevel: CGFloat = 0.0 {
    didSet {
      guard audioLevel != oldValue else { return }
      renderLayers()
      updateEmitter()
    }
  }
  // State changes land immediately, even when the shared display tick is stopped (static
  // success and error frames, Reduce Motion).
  var state: GlowState = .idle {
    didSet {
      renderLayers()
      updateEmitter()
    }
  }
  /// Set by FloatingHUD. No colour cycle runs under Reduce Motion.
  var reduceMotion = false {
    didSet {
      guard reduceMotion != oldValue else { return }
      paintedState = nil
      renderLayers()
    }
  }
  // Displays without a hardware notch have no bezel to illuminate; the aura rings
  // the floating pill instead. pillSize tracks the pill's live width as it expands.
  var pillMode: Bool = false {
    didSet { if pillMode != oldValue { renderLayers() } }
  }
  var pillSize: CGSize = .zero {
    didSet { if pillSize != oldValue { renderLayers() } }
  }

  // Ambient light-dust beneath the notch while listening: a CAEmitterLayer (GPU-composited,
  // no per-frame CPU draw) whose birth rate breathes with the voice. The motes stay white
  // on purpose - they read as dust catching whatever light the aura is currently casting.
  var particlesEnabled: Bool = true
  private var emitterLayer: CAEmitterLayer?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    self.wantsLayer = true
    self.layer?.masksToBounds = false
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    self.wantsLayer = true
    self.layer?.masksToBounds = false
  }

  // Stop independent GPU motion too: stopping the display tick does not remove
  // already emitted particles or an in-flight success ripple.
  func stopMotion() {
    emitterLayer?.removeFromSuperlayer()
    emitterLayer = nil
    for child in layer?.sublayers ?? [] where child.animation(forKey: "successRipple") != nil {
      child.removeAllAnimations()
      child.removeFromSuperlayer()
    }
  }

  // MARK: Particle motes

  // CAEmitterCell needs a bitmap; build one soft 12px radial disc once.
  private static let moteImage: CGImage? = {
    let size = 12
    guard
      let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray
    guard
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])
    else { return nil }
    let center = CGPoint(x: 6, y: 6)
    ctx.drawRadialGradient(
      gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 6, options: [])
    return ctx.makeImage()
  }()

  private func ensureEmitter() -> CAEmitterLayer? {
    if let existing = emitterLayer { return existing }
    guard let hostLayer = layer, let image = Self.moteImage else { return nil }

    let cell = CAEmitterCell()
    cell.contents = image
    cell.birthRate = 10.0
    cell.lifetime = 1.4
    cell.lifetimeRange = 0.4
    cell.velocity = 26.0
    cell.velocityRange = 12.0
    cell.emissionLongitude = -.pi / 2.0  // straight down (layer coords are y-up)
    cell.emissionRange = 0.35
    cell.yAcceleration = -28.0
    cell.scale = 0.30
    cell.scaleRange = 0.15
    cell.alphaSpeed = -0.8
    cell.color = NSColor.white.withAlphaComponent(0.55).cgColor

    let emitter = CAEmitterLayer()
    emitter.frame = bounds
    emitter.emitterShape = .line
    emitter.emitterCells = [cell]
    emitter.birthRate = 0.0
    hostLayer.addSublayer(emitter)
    emitterLayer = emitter
    return emitter
  }

  // Runs on state changes and every display tick: re-derives geometry (screen layout can
  // change under us) and breathes the birth rate with the voice. The layer-level birthRate
  // multiplies the cell's, so 0 silences emission without tearing the layer down.
  private func updateEmitter() {
    let active =
      particlesEnabled && state == .listening
      && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    guard active, let emitter = ensureEmitter() else {
      emitterLayer?.birthRate = 0.0
      return
    }
    // Geometry rarely changes; only the birth rate breathes per frame.
    let position: CGPoint
    let size: CGSize
    if pillMode {
      guard pillSize.width > 0 else {
        emitter.birthRate = 0.0
        return
      }
      position = CGPoint(x: bounds.midX, y: bounds.midY - pillSize.height / 2.0 - 4.0)
      size = CGSize(width: pillSize.width * 0.7, height: 2.0)
    } else {
      position = CGPoint(x: bounds.midX, y: bounds.height - notchRect.height - 4.0)
      size = CGSize(width: notchRect.width * 0.8, height: 2.0)
    }
    if emitter.frame != bounds { emitter.frame = bounds }
    if emitter.emitterPosition != position { emitter.emitterPosition = position }
    if emitter.emitterSize != size { emitter.emitterSize = size }
    // Quantized, so a steady voice does not touch the emitter every frame.
    let rate = Float(((0.35 + 0.65 * audioLevel) * 20).rounded() / 20)
    if emitter.birthRate != rate { emitter.birthRate = rate }
  }

  // outset dilates the path beyond the hardware cutout: a stroke centered on the exact
  // notch outline loses its inner half inside the cutout (those pixels don't exist),
  // which reads as a thin hard line with clipped corners. Pushed outward, the full
  // stroke width and its blur land on real wallpaper. Radii grow by the same amount
  // so the dilated path stays parallel to the bezel curve.
  private func createNotchPath(in bounds: NSRect, outset: CGFloat = 0.0) -> CGPath {
    let path = CGMutablePath()
    let cornerRadius: CGFloat = 14.0 + outset
    let outerCornerRadius: CGFloat = 6.0 + outset

    let topY = bounds.height
    let bottomY = bounds.height - notchRect.height - outset
    let leftX = (bounds.width - notchRect.width) / 2.0 - outset
    let rightX = leftX + notchRect.width + 2.0 * outset

    path.move(to: CGPoint(x: leftX - outerCornerRadius, y: topY))
    path.addQuadCurve(
      to: CGPoint(x: leftX, y: topY - outerCornerRadius),
      control: CGPoint(x: leftX, y: topY))
    path.addLine(to: CGPoint(x: leftX, y: bottomY + cornerRadius))
    path.addQuadCurve(
      to: CGPoint(x: leftX + cornerRadius, y: bottomY),
      control: CGPoint(x: leftX, y: bottomY))
    path.addLine(to: CGPoint(x: rightX - cornerRadius, y: bottomY))
    path.addQuadCurve(
      to: CGPoint(x: rightX, y: bottomY + cornerRadius),
      control: CGPoint(x: rightX, y: bottomY))
    path.addLine(to: CGPoint(x: rightX, y: topY - outerCornerRadius))
    path.addQuadCurve(
      to: CGPoint(x: rightX + outerCornerRadius, y: topY),
      control: CGPoint(x: rightX, y: topY))

    return path
  }

  // MARK: Light layers
  //
  // The aura is a layer composition the render server blurs and composites: a radial pool
  // under the notch, two halo layers whose shadowPath is the stroked bezel (or capsule)
  // outline, and a thin rim stroke. Each frame only sets tint, opacity, radius and width on
  // the main thread; paths change only when the geometry does. Pill mode adds a wider,
  // dropped spread pass and an inner bleed, and an even-odd mask keeps every photon off
  // the pill face.

  private let glowRoot = CALayer()
  private let glowMask = CAShapeLayer()
  private let poolClip = CALayer()
  private let pool = CAGradientLayer()
  private let haloWide = CALayer()
  private let haloTight = CALayer()
  private let spread = CALayer()
  private let rim = CAShapeLayer()
  private let bleedClip = CALayer()
  private let bleedClipMask = CAShapeLayer()
  private let bleed = CALayer()
  private var builtLayers = false

  private func buildLayers() {
    guard !builtLayers, let host = layer else { return }
    builtLayers = true
    pool.type = .radial
    pool.startPoint = CGPoint(x: 0.5, y: 0.5)
    pool.endPoint = CGPoint(x: 1, y: 1)
    pool.locations = [0.0, 0.45, 1.0]
    poolClip.masksToBounds = true
    poolClip.addSublayer(pool)
    for shadow in [haloWide, haloTight, spread, bleed] {
      shadow.shadowOffset = .zero
      shadow.shadowOpacity = 1
    }
    rim.fillColor = nil
    rim.lineCap = .round
    rim.lineJoin = .round
    glowMask.fillRule = .evenOdd
    bleedClip.mask = bleedClipMask
    bleedClip.addSublayer(bleed)
    for sublayer in [poolClip, spread, haloWide, haloTight, rim] { glowRoot.addSublayer(sublayer) }
    host.insertSublayer(glowRoot, at: 0)
    host.insertSublayer(bleedClip, above: glowRoot)
    let off: [String: CAAction] = [
      "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "opacity": NSNull(),
      "shadowPath": NSNull(), "shadowRadius": NSNull(), "shadowColor": NSNull(),
      "shadowOpacity": NSNull(), "shadowOffset": NSNull(), "path": NSNull(), "colors": NSNull(),
      "strokeColor": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(), "mask": NSNull(),
    ]
    for sublayer in [
      glowRoot, glowMask, poolClip, pool, haloWide, haloTight, spread, rim, bleedClip,
      bleedClipMask, bleed,
    ] {
      sublayer.actions = off
    }
  }

  override func layout() {
    super.layout()
    renderLayers()
  }

  private func renderLayers() {
    buildLayers()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    let idle = state == .idle
    if glowRoot.isHidden != idle { glowRoot.isHidden = idle }
    if bleedClip.isHidden != (idle || !pillMode) { bleedClip.isHidden = idle || !pillMode }
    guard !idle else {
      paintedState = nil
      return
    }
    let geometryChanged = rebuildGeometryIfNeeded()
    guard geometryReady else {
      glowRoot.isHidden = true
      bleedClip.isHidden = true
      return
    }
    let stateChanged = state != paintedState
    if stateChanged || geometryChanged {
      paintedState = state
      applyTint()
    }

    // Voice gives the light its breath: a quiet floor so the glow never dies, headroom so
    // speech visibly brightens and lengthens the spill. Quantized to 1/64, so a steady
    // voice writes nothing.
    let raw: CGFloat = (state == .listening) ? (0.30 + 0.70 * audioLevel) : 0.55
    let energy = (raw * 64).rounded() / 64
    guard energy != paintedEnergy || stateChanged || geometryChanged else { return }
    paintedEnergy = energy
    let width = 6.0 + 6.0 * energy
    let blur = 22.0 + 16.0 * energy

    setHalo(
      haloWide, cache: &haloPaths, outline: outline, width: width, blur: blur,
      alpha: 0.40 + 0.25 * energy)
    setHalo(
      haloTight, cache: &haloPaths, outline: outline, width: width, blur: blur * 0.5,
      alpha: 0.50 + 0.25 * energy)
    if pillMode {
      rim.lineWidth = 1.0
      rim.opacity = Float(0.55 + 0.30 * energy)
      setHalo(
        spread, cache: &spreadPaths, outline: spreadOutline, width: 8.0 + 6.0 * energy,
        blur: 30.0 + 14.0 * energy, alpha: 0.28 + 0.22 * energy)
      bleed.shadowOpacity = Float(min(1.0, (0.22 + 0.18 * energy) * 1.3))
    } else {
      rim.lineWidth = width * 0.35
      rim.opacity = Float(0.25 + 0.15 * energy)
      // Downward light spill: a wide, shallow pool under the notch, as if the bezel were
      // backlit; clipped so no light paints above the bezel line. Its depth follows the
      // voice by transform, so the gradient never re-rasterizes.
      let dropRadius: CGFloat = 38.0 + 28.0 * energy
      pool.transform = CATransform3DMakeScale(1, dropRadius / Self.maxDropRadius, 1)
      pool.opacity = Float(0.26 + 0.30 * energy)
    }
  }

  private static let maxDropRadius: CGFloat = 66
  private var paintedState: GlowState?
  private var paintedEnergy: CGFloat = -1

  // The tint for the current state. Success and error are one colour; listening and
  // processing cycle through their tables as keyframe animations the render server runs,
  // so the colour cycle costs the main thread nothing per frame. Processing takes the cool
  // half of the palette, so "working" never reads as "listening".
  private func applyTint() {
    let tintLayers: [CALayer] = [haloWide, haloTight, spread, bleed]
    for layer in tintLayers + [rim, pool] { layer.removeAnimation(forKey: "tint") }
    let still: AuraTint
    switch state {
    case .success: still = AuraTint.success
    case .error: still = AuraTint.error
    case .processing: still = AuraTint.processing(at: 0)
    default: still = AuraTint.listening(at: 0)
    }
    for layer in tintLayers { layer.shadowColor = still.color }
    rim.strokeColor = still.color
    pool.colors = still.poolColors
    guard !reduceMotion, state == .listening || state == .processing else { return }
    // One full loop takes ~14 s while listening (each hue holds ~1.4 s, fades ~0.9 s);
    // processing triples the tempo so the wait reads as activity.
    let cycle = state == .processing ? AuraTint.processingCycle : AuraTint.listeningCycle
    let period: CFTimeInterval = state == .processing ? 1 / 0.216 : 1 / 0.072
    func animation(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
      let tint = CAKeyframeAnimation(keyPath: keyPath)
      tint.values = values
      tint.duration = period
      tint.repeatCount = .infinity
      tint.calculationMode = .linear
      return tint
    }
    let colors = cycle.map(\.color)
    for layer in tintLayers { layer.add(animation("shadowColor", colors), forKey: "tint") }
    rim.add(animation("strokeColor", colors), forKey: "tint")
    pool.add(animation("colors", cycle.map(\.poolColors)), forKey: "tint")
  }

  // Tuned against the earlier Core Graphics renders: a layer shadow needs about 0.6 of the
  // CG blur value and a little more alpha for the same falloff. The stroked shadow path is
  // cached per half point of width, so a frame swaps in an existing path.
  private func setHalo(
    _ layer: CALayer, cache: inout [Int: CGPath], outline: CGPath?, width: CGFloat,
    blur: CGFloat, alpha: CGFloat
  ) {
    guard let outline else { return }
    let key = Int((width * 2).rounded())
    let path: CGPath
    if let cached = cache[key] {
      path = cached
    } else {
      path = outline.copy(
        strokingWithWidth: CGFloat(key) / 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
      cache[key] = path
    }
    if layer.shadowPath !== path { layer.shadowPath = path }
    layer.shadowRadius = blur * 0.62
    layer.shadowOpacity = Float(min(1.0, alpha * 1.3))
  }

  private var laidOutBounds: CGRect = .null
  private var laidOutNotch: CGRect = .null
  private var laidOutPill: CGSize = .zero
  private var laidOutPillMode: Bool?
  private var geometryReady = false
  private var outline: CGPath?
  private var spreadOutline: CGPath?
  private var haloPaths: [Int: CGPath] = [:]
  private var spreadPaths: [Int: CGPath] = [:]
  private var paintedPoolTint = -1

  // Everything that depends only on geometry: outlines, masks, clips, the rim path. Runs
  // when the bounds, notch, pill size, or mode change, never per frame otherwise.
  @discardableResult
  private func rebuildGeometryIfNeeded() -> Bool {
    guard
      bounds != laidOutBounds || notchRect != laidOutNotch || pillSize != laidOutPill
        || pillMode != laidOutPillMode
    else { return false }
    laidOutBounds = bounds
    laidOutNotch = notchRect
    laidOutPill = pillSize
    laidOutPillMode = pillMode
    haloPaths.removeAll(keepingCapacity: true)
    spreadPaths.removeAll(keepingCapacity: true)
    glowRoot.frame = bounds
    for layer in [haloWide, haloTight, spread, rim] { layer.frame = bounds }
    if pillMode {
      poolClip.isHidden = true
      let w = pillSize.width
      let h = pillSize.height
      geometryReady = w > 0 && h > 0
      guard geometryReady else { return true }
      let rect = CGRect(
        x: (bounds.width - w) / 2.0, y: (bounds.height - h) / 2.0, width: w, height: h)
      let capsule = CGPath(
        roundedRect: rect, cornerWidth: h / 2.0, cornerHeight: h / 2.0, transform: nil)
      outline = capsule
      // Even-odd mask: everything outside the capsule.
      let mask = CGMutablePath()
      mask.addRect(bounds)
      mask.addPath(capsule)
      glowMask.frame = bounds
      glowMask.path = mask
      glowRoot.mask = glowMask
      // Hairline 0.5 pt outside the capsule, so its full width survives the mask.
      let rimRect = rect.insetBy(dx: -0.5, dy: -0.5)
      rim.path = CGPath(
        roundedRect: rimRect, cornerWidth: h / 2.0 + 0.5, cornerHeight: h / 2.0 + 0.5,
        transform: nil)
      // Flank-and-underside spread: wider and softer, dropped a few points, so the light
      // pools to the sides and beneath the pill. Its reach must stay inside the panel margin.
      let reach: CGFloat = 13.0
      let spreadRect = rect.insetBy(dx: -reach, dy: -reach * 0.4)
      spreadOutline = CGPath(
        roundedRect: spreadRect, cornerWidth: spreadRect.height / 2.0,
        cornerHeight: spreadRect.height / 2.0, transform: nil)
      spread.isHidden = false
      spread.shadowOffset = CGSize(width: 0, height: -8)
      // Inner bleed: the same light inside the capsule, so the black edge dissolves into
      // the glow over a few points.
      bleedClip.frame = bounds
      bleedClipMask.frame = bounds
      bleedClipMask.path = capsule
      bleed.frame = bounds
      bleed.shadowPath = capsule.copy(
        strokingWithWidth: 2.0, lineCap: .round, lineJoin: .round, miterLimit: 10)
      bleed.shadowRadius = 5.0 * 0.62
    } else {
      geometryReady = notchRect.width > 0
      glowRoot.mask = nil
      spread.isHidden = true
      poolClip.isHidden = false
      let path = createNotchPath(in: bounds, outset: 2.5)
      outline = path
      rim.path = path
      poolClip.frame = CGRect(
        x: 0, y: 0, width: bounds.width, height: bounds.height - notchRect.height)
      let halfSpan = notchRect.width / 2.0 + 46.0
      pool.transform = CATransform3DIdentity
      pool.bounds = CGRect(x: 0, y: 0, width: halfSpan * 2, height: Self.maxDropRadius * 2)
      pool.position = CGPoint(x: bounds.midX, y: bounds.height - notchRect.height)
    }
    paintedEnergy = -1
    return true
  }

  // One-shot success punctuation: a stroked copy of the halo path expands outward and fades.
  // Runs as its own CAAnimation so it needs no display-tick frames (success freezes the tick).
  func emitSuccessRipple() {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    guard wantsLayer, let hostLayer = self.layer else { return }

    // Start/end paths share the same construction (createNotchPath, or the capsule math
    // drawPillAura uses) so Core Animation interpolates between them element-for-element
    // instead of cross-fading two unrelated shapes.
    let startPath: CGPath
    let endPath: CGPath
    if pillMode {
      let w = pillSize.width
      let h = pillSize.height
      guard w > 0, h > 0 else { return }
      let rect = CGRect(
        x: (bounds.width - w) / 2.0, y: (bounds.height - h) / 2.0, width: w, height: h)
      startPath = CGPath(
        roundedRect: rect, cornerWidth: h / 2.0, cornerHeight: h / 2.0, transform: nil)
      let outerRect = rect.insetBy(dx: -18.0, dy: -18.0)
      let outerRadius = h / 2.0 + 18.0
      endPath = CGPath(
        roundedRect: outerRect, cornerWidth: outerRadius, cornerHeight: outerRadius, transform: nil)
    } else {
      startPath = createNotchPath(in: bounds, outset: 2.5)
      endPath = createNotchPath(in: bounds, outset: 22.0)
    }

    let shapeLayer = CAShapeLayer()
    shapeLayer.frame = bounds
    // Shape layers rasterize at contentsScale (default 1.0) - inherit the host's so the
    // ring stays crisp on Retina.
    shapeLayer.contentsScale = hostLayer.contentsScale
    shapeLayer.fillColor = NSColor.clear.cgColor
    shapeLayer.strokeColor = Palette.success.cgColor
    shapeLayer.lineCap = .round
    shapeLayer.lineJoin = .round
    // Model values land on the END state before the animation is added, so removing
    // the layer after the animation finishes shows no flash back to the start frame.
    shapeLayer.path = endPath
    shapeLayer.opacity = 0.0
    shapeLayer.lineWidth = 1.0
    hostLayer.addSublayer(shapeLayer)

    let pathAnim = CABasicAnimation(keyPath: "path")
    pathAnim.fromValue = startPath
    pathAnim.toValue = endPath

    let opacityAnim = CABasicAnimation(keyPath: "opacity")
    opacityAnim.fromValue = 0.9
    opacityAnim.toValue = 0.0

    let lineWidthAnim = CABasicAnimation(keyPath: "lineWidth")
    lineWidthAnim.fromValue = 3.0
    lineWidthAnim.toValue = 1.0

    let group = CAAnimationGroup()
    group.animations = [pathAnim, opacityAnim, lineWidthAnim]
    group.duration = 0.55
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)

    CATransaction.begin()
    CATransaction.setCompletionBlock {
      shapeLayer.removeFromSuperlayer()
    }
    shapeLayer.add(group, forKey: "successRipple")
    CATransaction.commit()
  }
}
