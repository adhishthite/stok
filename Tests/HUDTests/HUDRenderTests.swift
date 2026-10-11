// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import QuartzCore
import XCTest

@testable import StokHUD

/// Renders each HUD state over a light and a dark wallpaper for visual review. Runs only
/// when /tmp/stok-ui exists, so a normal test run writes nothing.
@MainActor
final class HUDRenderTests: XCTestCase {
  private let directory = URL(fileURLWithPath: "/tmp/stok-ui", isDirectory: true)

  func testRenderHUDStates() throws {
    try XCTSkipUnless(
      FileManager.default.fileExists(atPath: directory.path), "Create /tmp/stok-ui to render.")
    _ = NSApplication.shared
    let states: [(String, (FloatingHUD) -> Void)] = [
      (
        "listening",
        { hud in
          hud.showListening()
          hud.updateAudioLevel(db: -18)
          hud.updateLiveText("मेरी meeting 3 बजे है, please add it to the calendar")
        }
      ),
      ("listening-idle", { hud in hud.showListening() }),
      (
        "speaking",
        { hud in
          hud.showListening()
          hud.updateAudioLevel(db: -12)
          hud.updateLiveText("Kal subah ki standup meeting 10 baje shift kar do")
        }
      ),
      (
        "processing",
        { hud in
          hud.showListening()
          hud.updateLiveText("मेरी meeting 3 बजे है")
          hud.showProcessing()
        }
      ),
      (
        "success",
        { hud in
          hud.showListening()
          hud.showSuccess(text: "My meeting is at 3:00.")
        }
      ),
      ("error", { hud in hud.showError(message: "No internet connection. Text was not pasted.") }),
      (
        "locked",
        { hud in
          hud.showListening(lockAfter: 15)
          hud.showLocked()
        }
      ),
    ]
    for (name, apply) in states {
      for dark in [false, true] {
        let hud = FloatingHUD(reduceMotion: { false }, increaseContrast: { false })
        apply(hud)
        try write(hud, to: "hud-\(name)-\(dark ? "dark" : "light").png", dark: dark)
      }
    }
    // Increase Contrast: the opaque plate.
    let contrast = FloatingHUD(reduceMotion: { true }, increaseContrast: { true })
    contrast.showError(message: "Microphone unavailable. Check System Settings.")
    try write(contrast, to: "hud-error-contrast.png", dark: false)
  }

  /// A frame strip of the orb alone, 3x, showing each state and the transitions between
  /// them over time: the frames are 1/40 s glow ticks apart unless noted.
  func testRenderOrbStrip() throws {
    try XCTSkipUnless(
      FileManager.default.fileExists(atPath: directory.path), "Create /tmp/stok-ui to render.")
    _ = NSApplication.shared
    let orb = OrbView(frame: NSRect(x: 0, y: 0, width: 60, height: 56))
    var frames: [(String, NSBitmapImageRep)] = []
    func capture(_ label: String, ticks: Int) {
      for _ in 0..<ticks { orb.advance(dt: 1.0 / 40.0) }
      orb.display()
      if let rep = orb.bitmapImageRepForCachingDisplay(in: orb.bounds) {
        orb.cacheDisplay(in: orb.bounds, to: rep)
        frames.append((label, rep))
      }
    }
    orb.state = .listening
    orb.audioLevel = 0
    capture("quiet", ticks: 40)
    orb.audioLevel = 0.9
    capture("speak +0.1s", ticks: 4)
    capture("speak +0.3s", ticks: 8)
    capture("speak +0.6s", ticks: 12)
    orb.audioLevel = 0.2
    capture("soft", ticks: 20)
    orb.state = .locked
    capture("locked", ticks: 20)
    orb.audioLevel = 0
    orb.state = .processing
    capture("proc +0.1s", ticks: 4)
    capture("proc +0.4s", ticks: 12)
    capture("proc +0.8s", ticks: 16)
    orb.state = .success
    capture("done +0.05s", ticks: 2)
    capture("done +0.15s", ticks: 4)
    capture("done +0.5s", ticks: 14)
    orb.state = .error
    capture("error +0.1s", ticks: 4)
    capture("error +0.5s", ticks: 16)
    let scale: CGFloat = 3
    let cell = NSSize(width: 60 * scale, height: 56 * scale + 34)
    let size = NSSize(width: cell.width * CGFloat(frames.count), height: cell.height)
    let rep = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.059, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    for (index, frame) in frames.enumerated() {
      let x = CGFloat(index) * cell.width
      frame.1.draw(
        in: NSRect(x: x, y: 34, width: 60 * scale, height: 56 * scale), from: .zero,
        operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      (frame.0 as NSString).draw(
        at: NSPoint(x: x + 10, y: 10),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor(white: 1, alpha: 0.7),
        ])
    }
    NSGraphicsContext.restoreGraphicsState()
    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    try png.write(to: directory.appendingPathComponent("hud-orb-strip.png"))
  }

  // The hardware notch: the panel has no pixels there, so it is drawn over the aura.
  private func notch(over aura: NSView, auraFrame: NSRect, union: NSRect) {
    guard let glow = aura as? AuraView, !glow.pillMode else { return }
    let size = glow.notchRect.size
    let rect = NSRect(
      x: auraFrame.midX - size.width / 2 - union.minX,
      y: auraFrame.maxY - union.minY - size.height, width: size.width, height: size.height + 20)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
  }

  private func write(_ hud: FloatingHUD, to name: String, dark: Bool) throws {
    hud.hideWorkItem?.cancel()
    hud.presence.snap()
    hud.widthSpring.snap()
    hud.applyFrame()
    hud.hostView.alphaValue = 1
    let aura = try XCTUnwrap(hud.notchPanel.contentView)
    aura.alphaValue = 1
    // A few glow frames so the colour cycle sits mid-way, not on its first anchor.
    for case let orb as OrbView in hud.hostView.descendants {
      for _ in 0..<45 { orb.advance(dt: 1.0 / 40.0) }
      orb.displayIfNeeded()
    }

    let auraFrame = hud.notchPanel.frame
    let hostFrame = hud.hostPanel.frame
    let joined = auraFrame.union(hostFrame)
    let union = NSRect(
      x: joined.minX - 40, y: joined.minY - 10, width: joined.width + 80, height: joined.height + 10
    )
    let scale: CGFloat = 2
    let rep = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(union.width * scale),
        pixelsHigh: Int(union.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0))
    rep.size = union.size
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let wallpaper = NSGradient(
      starting: dark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.97, alpha: 1),
      ending: dark
        ? NSColor(srgbRed: 0.12, green: 0.13, blue: 0.20, alpha: 1)
        : NSColor(srgbRed: 0.91, green: 0.93, blue: 0.99, alpha: 1))
    wallpaper?.draw(in: NSRect(origin: .zero, size: union.size), angle: -90)
    for (view, frame) in [(aura, auraFrame), (hud.hostView, hostFrame)] {
      let origin = NSPoint(x: frame.minX - union.minX, y: frame.minY - union.minY)
      let snapshot = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: snapshot)
      snapshot.draw(
        in: NSRect(origin: origin, size: frame.size), from: .zero, operation: .sourceOver,
        fraction: 1, respectFlipped: true, hints: nil)
      if view === aura { notch(over: aura, auraFrame: auraFrame, union: union) }
    }
    NSGraphicsContext.restoreGraphicsState()
    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    try png.write(to: directory.appendingPathComponent(name))
    hud.hostPanel.orderOut(nil)
    hud.notchPanel.orderOut(nil)
    hud.stopTick()
  }
}
