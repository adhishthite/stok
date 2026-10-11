// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import QuartzCore

/// The HUD's voice orb: a soft, living gradient sphere. Saffron and periwinkle drift inside
/// it while Stok listens, its edge swells with the voice, and a bright core grows with the
/// level. Each state also carries a shape, so the orb never relies on colour alone: a plain
/// sphere while listening, a bright crescent circling the rim while processing, a drawn
/// check on success, an exclamation mark with a shake on failure, and a padlock while a
/// hold is locked.
///
/// The orb is a layer composition the render server draws. Ambient motion (the drifting
/// pools, the orbiting mask lobes, the breathing, the crescent's spin) is a set of
/// repeating Core Animation animations installed once per state, so it costs the main
/// thread nothing per frame. The display link only feeds what the voice and the state
/// springs decide: about eight layer properties per listening frame, with implicit
/// animations off and no paths built. Under Reduce Motion no ambient animation runs and
/// every spring snaps, so each state is one static frame.
final class OrbView: NSView {

  var state: OrbState = .listening {
    didSet {
      guard state != oldValue else { return }
      retarget()
    }
  }

  /// Normalized voice level, 0...1. Drives the swell through a spring, so the orb answers
  /// the voice with weight instead of jitter.
  var audioLevel: CGFloat = 0.0 {
    didSet {
      level.target = max(0.0, min(1.0, audioLevel))
      if reduceMotion {
        level.snap()
        render()
      }
    }
  }

  /// Set by FloatingHUD. Snaps every transition and stops ambient motion.
  var reduceMotion = false {
    didSet {
      guard reduceMotion != oldValue else { return }
      if reduceMotion { snap() }
      installAmbientMotion()
    }
  }

  /// True while a transition is still travelling; the HUD keeps ticking until it settles.
  var settled: Bool {
    blend.settled && glyph.settled && level.settled && scale.settled && shake.settled
  }

  private var level = SpringChannel(value: 0, target: 0, stiffness: 140, dampingRatio: 0.62)
  private var blend = SpringChannel(value: 1, target: 1, stiffness: 300, dampingRatio: 1.0)
  private var glyph = SpringChannel(value: 0, target: 0, stiffness: 220, dampingRatio: 0.9)
  private var scale = SpringChannel(value: 1, target: 1, stiffness: 260, dampingRatio: 0.55)
  // Horizontal shake on failure, in points: a kicked, lightly damped spring.
  private var shake = SpringChannel(value: 0, target: 0, stiffness: 900, dampingRatio: 0.18)
  private var from = OrbColors.listening
  private var to = OrbColors.listening
  private var paintedBlend: CGFloat = -1
  private var paintedCenter = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
  // The last values written, so an unchanged frame writes nothing.
  private var paintedVoice: CGFloat = -1
  private var paintedFactor: CGFloat = -1
  private var paintedGlyph: CGFloat = -1
  private var paintedRingScale: CGFloat = -1

  private let halo = CAGradientLayer()
  // Everything inside the sphere is laid out once at the resting radius; the sphere layer's
  // transform scales it all for the voice and the state pop.
  private let sphere = CALayer()
  private let sphereMask = CALayer()
  // The mask: a centre disc and three lobes on rotating arms. The lobes reach out with the
  // voice, so the outline breathes organically.
  private let centreLobe = CALayer()
  private let arms = [CALayer(), CALayer(), CALayer()]
  private let lobes = [CALayer(), CALayer(), CALayer()]
  private let base = CAGradientLayer()
  private let pools = [CAGradientLayer(), CAGradientLayer(), CAGradientLayer()]
  private let rimShade = CAGradientLayer()
  private let gleam = CAGradientLayer()
  private let core = CAGradientLayer()
  private let ring = CALayer()
  private let comet = CAShapeLayer()
  private let cometGlow = CAShapeLayer()
  private let mark = CAShapeLayer()
  private let lockBody = CAShapeLayer()
  private var builtBounds: CGRect = .null
  private var markState: OrbState?

  private var allLayers: [CALayer] {
    [
      halo, sphere, sphereMask, centreLobe, base, rimShade, gleam, core, ring, comet, cometGlow,
      mark, lockBody,
    ] + pools + arms + lobes
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    build()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    build()
  }

  override var wantsUpdateLayer: Bool { true }

  private static let noActions: [String: CAAction] = [
    "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "opacity": NSNull(),
    "colors": NSNull(), "path": NSNull(), "strokeEnd": NSNull(), "lineWidth": NSNull(),
    "contents": NSNull(), "frame": NSNull(), "hidden": NSNull(), "fillColor": NSNull(),
    "strokeColor": NSNull(), "cornerRadius": NSNull(), "sublayerTransform": NSNull(),
    "anchorPoint": NSNull(),
  ]

  private func build() {
    wantsLayer = true
    guard let root = layer else { return }
    root.masksToBounds = false
    for gradient in [halo, base, rimShade, gleam, core] + pools {
      gradient.type = .radial
      gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
      gradient.endPoint = CGPoint(x: 1, y: 1)
    }
    rimShade.colors = [NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 0.30).cgColor]
    rimShade.locations = [0.62, 1.0]
    gleam.colors = [NSColor(white: 1, alpha: 0.55).cgColor, NSColor(white: 1, alpha: 0).cgColor]
    // The voice core: a bright centre whose size and brightness follow the level, so a
    // quiet, soft, or loud voice reads apart without colour.
    core.colors = [
      NSColor(white: 1, alpha: 0.95).cgColor, NSColor(white: 1, alpha: 0.45).cgColor,
      NSColor(white: 1, alpha: 0).cgColor,
    ]
    core.locations = [0, 0.35, 1]
    for lobe in [centreLobe] + lobes { lobe.backgroundColor = NSColor.white.cgColor }
    sphereMask.addSublayer(centreLobe)
    for (arm, lobe) in zip(arms, lobes) {
      arm.addSublayer(lobe)
      sphereMask.addSublayer(arm)
    }
    sphere.mask = sphereMask
    sphere.addSublayer(base)
    for pool in pools { sphere.addSublayer(pool) }
    sphere.addSublayer(rimShade)
    sphere.addSublayer(gleam)
    sphere.addSublayer(core)

    // Processing: a bright crescent riding the rim. The only waiting state, so it is the
    // clearest mark the orb draws: 3 pt at full strength over a wider, faint glow stroke.
    for (arc, width, opacity) in [(cometGlow, CGFloat(8), Float(0.32)), (comet, 3, 1)] {
      arc.fillColor = nil
      arc.lineWidth = width
      arc.lineCap = .round
      arc.strokeStart = 0
      arc.strokeEnd = 0.30
      arc.strokeColor = Palette.periwinkle.cgColor
      arc.opacity = opacity
      ring.addSublayer(arc)
    }

    mark.fillColor = nil
    mark.strokeColor = NSColor.white.cgColor
    mark.lineCap = .round
    mark.lineJoin = .round
    lockBody.fillColor = NSColor.white.cgColor

    for sublayer in [halo, sphere, ring, mark, lockBody] { root.addSublayer(sublayer) }
    for sublayer in allLayers {
      sublayer.actions = Self.noActions
      sublayer.contentsScale = 2
    }
    retarget()
  }

  override func layout() {
    super.layout()
    render()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    let scale = window?.backingScaleFactor ?? 2
    for sublayer in allLayers { sublayer.contentsScale = scale }
  }

  // Driven per display frame by FloatingHUD's display link while the HUD animates. Only
  // the springs advance here; ambient motion runs in the render server.
  func advance(dt: CGFloat) {
    level.step(dt: dt)
    blend.step(dt: dt)
    glyph.step(dt: dt)
    scale.step(dt: dt)
    shake.step(dt: dt)
    render()
  }

  private func retarget() {
    from = currentColors
    to = OrbColors.of(state)
    blend.value = 0
    blend.velocity = 0
    blend.target = 1
    glyph.value = 0
    glyph.velocity = 0
    glyph.target = state.hasGlyph ? 1 : 0
    // Outcomes cut straight to their colour: a hue walk from saffron to green or coral
    // would pass through tones that read as another state. Motion carries the change:
    // a pop to about 1.12 and back, and on failure a short shake.
    scale.target = 1
    switch state {
    case .success, .error:
      blend.snap()
      scale.value = 1
      scale.velocity = 3.2
      if state == .error {
        shake.value = 0
        shake.velocity = 140
      }
    case .processing: scale.value = 1.06
    default: break
    }
    paintedBlend = -1
    if reduceMotion { snap() } else { render() }
    installAmbientMotion()
  }

  private func snap() {
    blend.snap()
    glyph.snap()
    scale.snap()
    level.snap()
    shake.snap()
    paintedBlend = -1
    render()
  }

  private var currentColors: OrbColors {
    OrbColors.mix(from, to, blend.settled ? blend.target : max(0.0, min(1.0, blend.value)))
  }

  /// The sphere's resting radius: everything is laid out for it once, then scaled.
  private var restRadius: CGFloat { min(bounds.width, bounds.height) * 0.27 }

  // MARK: Ambient motion (render server)

  private static let ambientKeys = ["drift", "orbit", "breath", "spin"]

  // Repeating animations for the current state. Installed on state change and on a
  // Reduce Motion change, never per frame.
  private func installAmbientMotion() {
    for layer in pools + arms + [sphere, ring] {
      for key in Self.ambientKeys { layer.removeAnimation(forKey: key) }
    }
    guard !reduceMotion, builtBounds.width > 0 else { return }
    let rest = restRadius
    let centre = CGPoint(x: rest * 1.6, y: rest * 1.6)
    switch state {
    case .listening, .locked:
      addDrift(rest: rest, centre: centre, period: 34)
      for (index, arm) in arms.enumerated() {
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = (index % 2 == 0 ? 1.0 : -1.0) * 2.0 * Double.pi
        turn.isAdditive = true
        turn.duration = [3.7, 4.9, 6.1][index]
        turn.repeatCount = .infinity
        arm.add(turn, forKey: "orbit")
      }
      let breath = CABasicAnimation(keyPath: "transform.scale")
      breath.fromValue = -0.025
      breath.toValue = 0.025
      breath.isAdditive = true
      breath.autoreverses = true
      breath.duration = 2.2
      breath.repeatCount = .infinity
      breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      sphere.add(breath, forKey: "breath")
    case .processing:
      addDrift(rest: rest, centre: centre, period: 12)
      let spin = CABasicAnimation(keyPath: "transform.rotation.z")
      spin.fromValue = 0
      spin.toValue = -2.0 * Double.pi
      spin.isAdditive = true
      spin.duration = 0.9
      spin.repeatCount = .infinity
      ring.add(spin, forKey: "spin")
    case .success, .error:
      break
    }
  }

  // Each pool wanders a Lissajous loop inside the sphere.
  private func addDrift(rest: CGFloat, centre: CGPoint, period: CFTimeInterval) {
    for (index, pool) in pools.enumerated() {
      let orbit = rest * (0.30 + 0.12 * CGFloat(index))
      let path = CGMutablePath()
      let steps = 240
      for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 20.0 * .pi + CGFloat(index) * 2.1
        let point = CGPoint(
          x: centre.x + orbit * cos(angle), y: centre.y + orbit * sin(angle * 1.3 + CGFloat(index)))
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      let drift = CAKeyframeAnimation(keyPath: "position")
      drift.path = path
      drift.calculationMode = .paced
      drift.duration = period * (1.0 + 0.15 * CFTimeInterval(index))
      drift.repeatCount = .infinity
      pool.add(drift, forKey: "drift")
    }
  }

  // MARK: Layer state

  private func render() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    rebuildIfNeeded()
    let rest = restRadius
    guard rest > 0 else { return }

    let shift = reduceMotion ? 0 : shake.value
    let center = CGPoint(x: bounds.midX + shift, y: bounds.midY)
    let voice = max(0.0, level.value)
    // The sphere keeps one size in every pill; the voice drives the core, the halo, and the
    // lobes, never the base radius.
    let factor = scale.value
    let glyphProgress = max(0.0, min(1.0, glyph.value))
    let blendNow = blend.settled ? blend.target : max(0.0, min(1.0, blend.value))
    guard
      voice != paintedVoice || factor != paintedFactor || glyphProgress != paintedGlyph
        || center != paintedCenter || blendNow != paintedBlend || markState != state
    else { return }
    paintedVoice = voice
    paintedFactor = factor
    paintedGlyph = glyphProgress

    // Colours change only while a transition travels; a settled blend is exactly its
    // target, so a resting orb never re-blends.
    let mix = blend.settled ? blend.target : max(0.0, min(1.0, blend.value))
    if mix != paintedBlend {
      paintedBlend = mix
      let colors = currentColors
      halo.colors = [colors.halo.cgColor, colors.halo.withAlphaComponent(0).cgColor]
      base.colors = [colors.core.cgColor, colors.mid.cgColor, colors.rim.cgColor]
      for (layer, color) in zip(pools, colors.pools) {
        layer.colors = [color.withAlphaComponent(0.7).cgColor, color.withAlphaComponent(0).cgColor]
      }
    }
    if center != paintedCenter {
      paintedCenter = center
      halo.position = center
      sphere.position = center
      ring.position = center
      mark.position = center
      lockBody.position = center
    }

    // Halo: the sphere's light on the pill, wider and brighter with the voice.
    let haloRadius = min(bounds.width / 2.0, rest * factor * (1.55 + 0.25 * voice))
    halo.transform = CATransform3DMakeScale(haloRadius / (rest * 1.8), haloRadius / (rest * 1.8), 1)
    halo.opacity = Float(0.30 + 0.30 * voice)

    // Sphere: one transform scales base, pools, shading, and mask together.
    sphere.transform = CATransform3DMakeScale(factor, factor, 1)
    if state == .listening || state == .locked {
      // Lobes reach out from the centre with the voice; their arms turn in the render server.
      let reach = reduceMotion ? 0 : rest * 0.15 * voice
      for lobe in lobes { lobe.position = CGPoint(x: rest * 1.6 + reach, y: rest * 1.6) }
      // A ramp, not a switch: quiet is a faint ember, soft a small glow, speaking a bright
      // wide core.
      let coreScale = (0.20 + 0.58 * voice) / 0.78
      core.transform = CATransform3DMakeScale(coreScale, coreScale, 1)
      core.opacity = Float(0.15 + 0.80 * voice)
    }

    if markState != state { placeMarks() }
    let ringScale = (rest * factor + 3.5) / (rest + 3.5)
    if !ring.isHidden, ringScale != paintedRingScale {
      paintedRingScale = ringScale
      ring.transform = CATransform3DMakeScale(ringScale, ringScale, 1)
    }
    guard !mark.isHidden || !lockBody.isHidden else { return }
    let progress = max(0.0, min(1.0, glyph.value))
    let markScale = CATransform3DMakeScale(factor, factor, 1)
    if mark.isHidden {
      lockBody.transform = markScale
      lockBody.opacity = Float(progress)
    } else {
      mark.transform = markScale
      mark.strokeEnd = progress
    }
  }

  // Bounds, resting geometry, and paths. Runs when the view size changes, never per frame.
  private func rebuildIfNeeded() {
    guard bounds != builtBounds, bounds.width > 0 else { return }
    builtBounds = bounds
    let rest = restRadius
    let box = rest * 1.6
    let centre = CGPoint(x: box, y: box)
    func lay(_ layer: CALayer, at point: CGPoint, radius: CGFloat, round: Bool = false) {
      layer.transform = CATransform3DIdentity
      layer.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
      layer.position = point
      if round { layer.cornerRadius = radius }
    }
    lay(halo, at: CGPoint(x: bounds.midX, y: bounds.midY), radius: rest * 1.8)
    sphere.bounds = CGRect(x: 0, y: 0, width: box * 2, height: box * 2)
    sphereMask.frame = sphere.bounds
    lay(centreLobe, at: centre, radius: rest, round: true)
    // Arms rest a third of a turn apart; the orbit animation adds to that.
    for (index, (arm, lobe)) in zip(arms, lobes).enumerated() {
      arm.transform = CATransform3DIdentity
      arm.frame = sphere.bounds
      arm.transform = CATransform3DMakeRotation(CGFloat(index) * 2.0 * .pi / 3.0, 0, 0, 1)
      lay(lobe, at: centre, radius: rest * 0.86, round: true)
    }
    lay(base, at: CGPoint(x: centre.x - rest * 0.35, y: centre.y + rest * 0.40), radius: rest * 1.9)
    // Pools rest spread apart, so a still frame (Reduce Motion) is balanced.
    for (index, pool) in pools.enumerated() {
      let orbit = rest * (0.30 + 0.12 * CGFloat(index))
      let angle = CGFloat(index) * 2.1
      let point = CGPoint(
        x: centre.x + orbit * cos(angle), y: centre.y + orbit * sin(angle * 1.3 + CGFloat(index)))
      lay(pool, at: point, radius: rest * 0.85)
    }
    lay(rimShade, at: centre, radius: rest * 1.02)
    lay(
      gleam, at: CGPoint(x: centre.x - rest * 0.38, y: centre.y + rest * 0.46), radius: rest * 0.55)
    lay(core, at: centre, radius: rest * 0.78)
    let ringRadius = rest + 3.5
    let ringBox = CGRect(x: 0, y: 0, width: ringRadius * 2, height: ringRadius * 2)
    ring.bounds = ringBox
    let ringPath = CGPath(ellipseIn: ringBox, transform: nil)
    for arc in [comet, cometGlow] {
      arc.frame = ringBox
      arc.path = ringPath
    }
    for layer in [mark, lockBody] {
      layer.bounds = CGRect(x: -rest, y: -rest, width: rest * 2, height: rest * 2)
    }
    paintedCenter = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    paintedRingScale = -1
    markState = nil
    installAmbientMotion()
  }

  // Visibility and mark paths for the current state, built at the resting radius.
  private func placeMarks() {
    markState = state
    let listening = state == .listening || state == .locked
    core.isHidden = !listening
    ring.isHidden = state != .processing
    paintedRingScale = -1
    mark.isHidden = !(state == .success || state == .error)
    lockBody.isHidden = state != .locked
    let s = restRadius / 13.0
    switch state {
    case .success:
      mark.path = checkPath(s: s)
      mark.lineWidth = 2.4 * s
    case .error:
      mark.path = exclamationPath(s: s)
      mark.lineWidth = 2.6 * s
    case .locked:
      lockBody.path = lockPath(s: s)
    default:
      break
    }
  }

  private func checkPath(s: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -5.5 * s, y: 0.2 * s))
    path.addLine(to: CGPoint(x: -1.6 * s, y: -4.0 * s))
    path.addLine(to: CGPoint(x: 6.0 * s, y: 4.6 * s))
    return path
  }

  // The bar draws down first; the dot is the last stretch of the stroke.
  private func exclamationPath(s: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 5.5 * s))
    path.addLine(to: CGPoint(x: 0, y: -1.5 * s))
    path.move(to: CGPoint(x: 0, y: -5.0 * s))
    path.addLine(to: CGPoint(x: 0, y: -5.01 * s))
    return path
  }

  private func lockPath(s: CGFloat) -> CGPath {
    let body = CGRect(x: -4.6 * s, y: -5.2 * s, width: 9.2 * s, height: 6.8 * s)
    let path = CGMutablePath()
    path.addRoundedRect(in: body, cornerWidth: 1.6 * s, cornerHeight: 1.6 * s)
    let shackle = CGMutablePath()
    shackle.move(to: CGPoint(x: -2.9 * s, y: body.maxY))
    shackle.addLine(to: CGPoint(x: -2.9 * s, y: body.maxY + 1.6 * s))
    shackle.addArc(
      center: CGPoint(x: 0, y: body.maxY + 1.6 * s), radius: 2.9 * s, startAngle: .pi,
      endAngle: 0, clockwise: true)
    shackle.addLine(to: CGPoint(x: 2.9 * s, y: body.maxY))
    path.addPath(
      shackle.copy(strokingWithWidth: 1.8 * s, lineCap: .round, lineJoin: .round, miterLimit: 1))
    return path
  }
}
