// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import XCTest

@testable import StokEngine

/// The settle-to-paste path's focus guard, synchronous as shipped. No real clipboard,
/// Accessibility, or Cmd-V: the engine's PasteEnvironment answers for the system.
final class PastePathTests: XCTestCase {
  private final class Recorder: @unchecked Sendable {
    let lock = NSLock()
    var frontmost: PasteEnvironment.App?
    var switchDuringInject: PasteEnvironment.App?
    var injected: [String] = []
    var dispatchAllowed: [Bool] = []
    var copied: [String] = []
    let done = DispatchSemaphore(value: 0)

    func with<T>(_ body: () -> T) -> T {
      lock.lock()
      defer { lock.unlock() }
      return body()
    }
  }

  private func engine(_ recorder: Recorder) -> DictationEngine {
    var config = EngineConfiguration()
    config.historyEnabled = false
    config.soundFeedback = false
    config.restoreClipboard = true
    config.enableLiveWebSocket = false
    let engine = DictationEngine(config: config)
    engine.paste = PasteEnvironment(
      isAccessibilityTrusted: { true },
      isSecureInputActive: { false },
      frontmostApp: { recorder.with { recorder.frontmost } },
      awaitPreparedClipboard: { $0(true) },
      inject: { text, _, _, _, shouldDispatch in
        recorder.with {
          if let next = recorder.switchDuringInject { recorder.frontmost = next }
        }
        let allowed = shouldDispatch()
        recorder.with {
          recorder.injected.append(text)
          recorder.dispatchAllowed.append(allowed)
        }
        recorder.done.signal()
        return TextInjector.InjectionResult(
          outcome: allowed ? .dispatched : .dispatchCancelled, latencyMs: 0)
      },
      copyOnly: { text, _ in
        recorder.with { recorder.copied.append(text) }
        recorder.done.signal()
        return true
      })
    return engine
  }

  private func settle(_ engine: DictationEngine, _ recorder: Recorder) {
    let now = ProcessInfo.processInfo.systemUptime
    engine.sessionQueue.async {
      engine.isProcessing = true
      engine.settle(
        turnId: 0, route: "fixture",
        outcome: .success(
          text: "hello", transport: "fixture", firstTokenMs: 0, roundtripMs: 0, audioDuration: 1,
          keyUpTime: now, captureFinalizeMs: 0, fallbackReason: nil, isLiveRoute: true))
    }
    XCTAssertEqual(recorder.done.wait(timeout: .now() + 2), .success, "the paste path finished")
    engine.sessionQueue.sync {}
  }

  func testSameAppPastes() {
    let recorder = Recorder()
    recorder.frontmost = PasteEnvironment.App(pid: 4242, name: "Notes")
    let engine = engine(recorder)
    engine.turnFrontmostPID = 4242
    settle(engine, recorder)
    XCTAssertEqual(recorder.with { recorder.injected }, ["hello"])
    XCTAssertEqual(recorder.with { recorder.dispatchAllowed }, [true])
    XCTAssertEqual(recorder.with { recorder.copied }, [])
  }

  func testAppSwitchBetweenSettleAndPasteCopiesInstead() {
    let recorder = Recorder()
    recorder.frontmost = PasteEnvironment.App(pid: 5151, name: "Slack")
    let engine = engine(recorder)
    engine.turnFrontmostPID = 4242
    settle(engine, recorder)
    XCTAssertEqual(recorder.with { recorder.injected }, [], "never paste into a different app")
    XCTAssertEqual(recorder.with { recorder.copied }, ["hello"])
  }

  func testAppSwitchDuringInjectCancelsTheKeystroke() {
    let recorder = Recorder()
    recorder.frontmost = PasteEnvironment.App(pid: 4242, name: "Notes")
    recorder.switchDuringInject = PasteEnvironment.App(pid: 5151, name: "Slack")
    let engine = engine(recorder)
    engine.turnFrontmostPID = 4242
    settle(engine, recorder)
    XCTAssertEqual(
      recorder.with { recorder.dispatchAllowed }, [false],
      "the check right before the keystroke sees the switch")
  }
}

/// TextInjector's synchronous keystroke: Cmd-V down, a 10 ms hold, Cmd-V up, the commit cue,
/// all before inject returns. The hooks keep every write on a private pasteboard and every
/// key event in a log; they are restored only after inject has returned, so nothing can reach
/// the real HID event tap.
final class KeystrokeTests: XCTestCase {
  private final class Events: @unchecked Sendable {
    let lock = NSLock()
    var log: [(name: String, at: Double)] = []
    func add(_ name: String) {
      lock.lock()
      log.append((name, ProcessInfo.processInfo.systemUptime))
      lock.unlock()
    }
    var snapshot: [(name: String, at: Double)] {
      lock.lock()
      defer { lock.unlock() }
      return log
    }
  }

  private var savedPasteboard: NSPasteboard!
  private var savedPost: ((CGEvent) -> Void)!
  private var savedSound: (() -> Void)!
  private let events = Events()

  override func setUp() {
    savedPasteboard = TextInjector.pasteboard
    savedPost = TextInjector.postKeyEvent
    savedSound = TextInjector.playCommitSound
    TextInjector.pasteboard = NSPasteboard(
      name: NSPasteboard.Name("com.adhishthite.stok.tests.\(UUID().uuidString)"))
    let events = self.events
    TextInjector.postKeyEvent = { events.add($0.type == .keyDown ? "down" : "up") }
    TextInjector.playCommitSound = { events.add("sound") }
  }

  override func tearDown() {
    TextInjector.pasteboard.releaseGlobally()
    TextInjector.pasteboard = savedPasteboard
    TextInjector.postKeyEvent = savedPost
    TextInjector.playCommitSound = savedSound
  }

  func testKeystrokeCompletesBeforeInjectReturns() {
    let result = TextInjector.inject(
      text: "hi", restorePreviousClipboard: false, completionSound: true, appendSpace: true)
    let log = events.snapshot
    XCTAssertEqual(result.outcome, .dispatched)
    XCTAssertEqual(log.map(\.name), ["down", "up", "sound"])
    if log.count == 3 {
      XCTAssertGreaterThanOrEqual(log[1].at - log[0].at, 0.009, "a 10 ms Cmd-V hold")
    }
    // Only the pasted payload gets the trailing space.
    XCTAssertEqual(TextInjector.pasteboard.string(forType: .string), "hi ")
  }

  func testBackToBackPastesNeverInterleave() {
    _ = TextInjector.inject(text: "one", restorePreviousClipboard: false, completionSound: false)
    _ = TextInjector.inject(text: "two", restorePreviousClipboard: false, completionSound: false)
    XCTAssertEqual(events.snapshot.map(\.name), ["down", "up", "down", "up"])
  }

  func testCancelledDispatchPostsNoKeystroke() {
    let result = TextInjector.inject(
      text: "hi", restorePreviousClipboard: false, completionSound: true,
      shouldDispatch: { false })
    XCTAssertEqual(result.outcome, .dispatchCancelled)
    XCTAssertEqual(events.snapshot.map(\.name), [])
  }
}
