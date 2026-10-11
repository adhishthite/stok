// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import XCTest

@testable import StokEngine

/// Headless paste-path timing, gated: `TEST_RUNNER_STOK_PASTE_BENCH=1` with StokLiveChecks.
/// Writes build/paste-bench-<label>.json (label from STOK_PASTE_BENCH_LABEL). No real
/// clipboard or Cmd-V: TextInjector writes a private pasteboard and records its key events,
/// and the engine's paste environment answers as an accessible app that stays frontmost,
/// read through the live main.sync frontmost check. Every wait is bounded.
final class PasteBenchmarkTests: XCTestCase {
  private static let samples = 200

  private static func summary(_ values: [Double]) -> [String: Double] {
    let sorted = values.sorted()
    func at(_ q: Double) -> Double { sorted[Int((Double(sorted.count - 1) * q).rounded())] }
    return [
      "n": Double(sorted.count), "median_ms": at(0.5), "p90_ms": at(0.9), "p99_ms": at(0.99),
      "max_ms": sorted.last ?? 0,
    ]
  }

  func testPasteBenchmark() throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["STOK_PASTE_BENCH"] == "1" else {
      throw XCTSkip("Set TEST_RUNNER_STOK_PASTE_BENCH=1 to run the paste benchmark.")
    }
    let root = URL(fileURLWithPath: try XCTUnwrap(environment["STOK_PROJECT_ROOT"]))
    let label = environment["STOK_PASTE_BENCH_LABEL"] ?? "run"

    // Hooks for the whole benchmark; inject is synchronous, so restoring them after the last
    // call returns cannot leave a keystroke behind.
    let savedBoard = TextInjector.pasteboard
    let savedPost = TextInjector.postKeyEvent
    let savedSound = TextInjector.playCommitSound
    TextInjector.pasteboard = NSPasteboard(
      name: NSPasteboard.Name("com.adhishthite.stok.bench.\(UUID().uuidString)"))
    TextInjector.postKeyEvent = { _ in }
    TextInjector.playCommitSound = {}
    defer {
      TextInjector.pasteboard.releaseGlobally()
      TextInjector.pasteboard = savedBoard
      TextInjector.postKeyEvent = savedPost
      TextInjector.playCommitSound = savedSound
    }

    // 1. TextInjector.inject (what inject_ms records).
    var inject: [Double] = []
    for _ in 0..<Self.samples {
      let result = TextInjector.inject(
        text: "Benchmark dictation text.", restorePreviousClipboard: false, completionSound: true,
        appendSpace: true)
      XCTAssertEqual(result.outcome, .dispatched)
      inject.append(result.latencyMs)
    }

    // 2. settle() to the moment the paste decision is made (the inject call), through
    // handleTranscribedText and its main.sync frontmost checks.
    let idle = try settleToInject(mainBusy: false)
    let busy = try settleToInject(mainBusy: true)

    XCTAssertEqual(inject.count, Self.samples)
    XCTAssertEqual(idle.count, Self.samples)
    XCTAssertEqual(busy.count, Self.samples)
    let report: [String: Any] = [
      "label": label,
      "inject_ms": Self.summary(inject),
      "settle_to_inject_main_idle_ms": Self.summary(idle),
      "settle_to_inject_main_busy_ms": Self.summary(busy),
    ]
    let data = try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: root.appendingPathComponent("build/paste-bench-\(label).json"))
  }

  /// One sample per settled turn. The main thread keeps turning (this test runs on it), and
  /// with `mainBusy` it is occupied 8 ms of every 16 ms, like a HUD frame.
  private func settleToInject(mainBusy: Bool) throws -> [Double] {
    var config = EngineConfiguration()
    config.historyEnabled = false
    config.soundFeedback = false
    config.restoreClipboard = true
    config.enableLiveWebSocket = false
    let engine = DictationEngine(config: config)
    let lock = NSLock()
    var started = 0.0
    var samples: [Double] = []
    let reached = DispatchSemaphore(value: 0)
    let frontmost = PasteEnvironment.App(pid: 4242, name: "Fixture")
    engine.paste = PasteEnvironment(
      isAccessibilityTrusted: { true }, isSecureInputActive: { false },
      // The live check's cost (a main.sync), with a fixed answer so the guard always passes.
      frontmostApp: {
        DispatchQueue.main.sync {}
        return frontmost
      },
      awaitPreparedClipboard: { $0(true) },
      inject: { _, _, _, _, shouldDispatch in
        _ = shouldDispatch()
        lock.lock()
        samples.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
        lock.unlock()
        reached.signal()
        return TextInjector.InjectionResult(outcome: .dispatched, latencyMs: 0)
      },
      copyOnly: { _, _ in
        reached.signal()
        return true
      })
    engine.turnFrontmostPID = frontmost.pid

    var busy = mainBusy
    func frame() {
      guard busy else { return }
      Thread.sleep(forTimeInterval: 0.008)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { frame() }
    }
    if mainBusy { DispatchQueue.main.async { frame() } }
    defer { busy = false }

    let deadline = ProcessInfo.processInfo.systemUptime + 60
    for _ in 0..<Self.samples {
      engine.sessionQueue.async {
        engine.currentTurnId += 1
        engine.turnSettled = false
        engine.isProcessing = true
        lock.lock()
        started = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        engine.settle(
          turnId: engine.currentTurnId, route: "bench",
          outcome: .success(
            text: "Benchmark dictation text.", transport: "bench", firstTokenMs: 0,
            roundtripMs: 0, audioDuration: 1, keyUpTime: ProcessInfo.processInfo.systemUptime,
            captureFinalizeMs: 0, fallbackReason: nil, isLiveRoute: true))
      }
      // Keep main turning so the path's main.sync can run; never wait without a bound.
      while reached.wait(timeout: .now()) == .timedOut {
        guard ProcessInfo.processInfo.systemUptime < deadline else {
          throw XCTSkip("benchmark exceeded its 60 s bound")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.001))
      }
      engine.sessionQueue.sync {}
    }
    lock.lock()
    defer { lock.unlock() }
    return samples
  }
}
