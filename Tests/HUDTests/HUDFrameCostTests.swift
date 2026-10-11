// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import QuartzCore
import XCTest

@testable import StokHUD

/// Main-thread cost of HUD animation frames, as the display link would run them: the
/// entrance spring travelling, the hold-to-lock rim sweeping, and a voice that varies and
/// then holds steady. Levels arrive every 12th frame: the capture engine throttles them to
/// 10 Hz and the display link runs at 120 Hz. Each frame commits its transaction as the run
/// loop would. Synchronous drawing counts; the render server's compositing runs in another process and does not.
/// Allocations are main-thread only, with the top allocating call sites printed.
@MainActor
final class HUDFrameCostTests: XCTestCase {
  private struct Scenario {
    let name: String
    let frames: Int
    let db: (Int) -> Double
  }

  func testListeningFrameCost() throws {
    _ = NSApplication.shared
    let hud = FloatingHUD(reduceMotion: { false }, increaseContrast: { false })
    defer {
      hud.hostPanel.orderOut(nil)
      hud.notchPanel.orderOut(nil)
      hud.stopTick()
    }
    hud.showListening(lockAfter: 15)
    hud.updateLiveText("मेरी meeting 3 बजे है, please add it to the calendar")
    let scenarios = [
      Scenario(name: "entrance+varying voice", frames: 240) { -40 + 30 * sin(Double($0) * 1.3) },
      Scenario(name: "varying voice", frames: 240) { -40 + 30 * sin(Double($0) * 1.3) },
      Scenario(name: "steady voice", frames: 240) { _ in -30 },
      // Everything settled: the display link would have stopped; this is what a frame
      // would cost if it had not.
      Scenario(name: "at rest", frames: 240) { _ in -30 },
    ]
    for scenario in scenarios {
      var durations: [Double] = []
      durations.reserveCapacity(scenario.frames)
      let result = AllocationCounter.measure {
        for frame in 0..<scenario.frames {
          let begin = CACurrentMediaTime()
          if frame % 12 == 0 { hud.updateAudioLevel(db: scenario.db(frame / 12)) }
          hud.advanceAnimation(dt: 1.0 / 120.0)
          CATransaction.flush()
          durations.append((CACurrentMediaTime() - begin) * 1000)
        }
      }
      let sorted = durations.sorted()
      let mean = durations.reduce(0, +) / Double(durations.count)
      print(
        String(
          format:
            "HUD frame [%@] main-thread ms mean=%.3f p95=%.3f max=%.3f allocations/frame=%.1f",
          scenario.name, mean, sorted[Int(Double(sorted.count) * 0.95)], sorted[sorted.count - 1],
          Double(result?.count ?? -1) / Double(scenario.frames)))
      for (site, count) in result?.sites ?? [] {
        print("  HUD alloc site [\(scenario.name)] \(count)x \(site)")
      }
      // A generous ceiling that still catches a regression back to per-frame bitmap redraws.
      XCTAssertLessThan(mean, 4.0)
    }
  }

  func testReleasedHUDDeallocatesWhileTicking() {
    _ = NSApplication.shared
    weak var released: FloatingHUD?
    autoreleasepool {
      let hud = FloatingHUD(reduceMotion: { false }, increaseContrast: { false })
      hud.showListening()
      XCTAssertTrue(hud.isTicking)
      hud.hostPanel.orderOut(nil)
      hud.notchPanel.orderOut(nil)
      released = hud
    }
    XCTAssertNil(released, "the display link must not keep a released HUD alive")
  }
}
