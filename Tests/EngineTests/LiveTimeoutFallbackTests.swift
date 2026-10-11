// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import StokEngine

/// The live route's 2.2 s ceiling after speech_end. Partials are provisional: they skip the
/// output mode (in translate mode they are in the spoken language, verified 2026-10-07), so
/// a timeout that only has partial text for some utterance must hand the turn to REST,
/// which honors mode and language. Finals for every utterance still settle from the socket.
final class LiveTimeoutFallbackTests: XCTestCase {
  private struct Outcome {
    var delivered: [String] = []
    var restCalls = 0
  }

  /// Runs one committed live turn whose events are `events`, lets the live ceiling pass,
  /// and feeds the client's result to the engine's arbiter with a stubbed REST route.
  private func timedOutTurn(
    mode: TranscriptionMode, restText: String, events: (SarvamLiveClient) -> Void
  ) -> Outcome {
    let lock = NSLock()
    var outcome = Outcome()
    let delivered = DispatchSemaphore(value: 0)
    var config = EngineConfiguration()
    config.historyEnabled = false
    config.soundFeedback = false
    config.restoreClipboard = false
    config.enableLiveWebSocket = true
    config.sarvamApiKey = "fixture-key"
    config.transcriptionMode = mode
    let engine = DictationEngine(
      config: config,
      delivery: .sink { text in
        lock.lock()
        outcome.delivered.append(text.trimmingCharacters(in: .whitespaces))
        lock.unlock()
        delivered.signal()
      })
    engine.restTranscribe = { _, _, _, _, _, _, done in
      lock.lock()
      outcome.restCalls += 1
      lock.unlock()
      done(.success((text: restText, latencyMs: 5)))
      return CancellableRequest()
    }
    let client = SarvamLiveClient(apiKey: "", mode: mode)
    client.fixtureOpen()
    events(client)
    let now = ProcessInfo.processInfo.systemUptime
    client.fixtureCompletion { result in
      engine.sessionQueue.async {
        // Turn #0 of a fresh engine is live; the hedge timer has not fired yet.
        engine.isProcessing = true
        engine.wsCommitInFlight = true
        engine.pendingFallbackTimer = DispatchWorkItem {}
        engine.handleLiveCommitResult(
          result, turnId: 0, pcmData: Data(count: 32_000), duration: 1, keyUpTime: now,
          captureFinalizeMs: 0, speechFrames: 40, commitStartTime: now)
      }
    }
    client.recoveryForceSettleAge()
    XCTAssertEqual(delivered.wait(timeout: .now() + 3), .success, "the turn delivers once")
    engine.sessionQueue.sync {}
    lock.lock()
    defer { lock.unlock() }
    return outcome
  }

  func testTranslateModeNeverPastesPartialTextInTheSpokenLanguage() {
    let outcome = timedOutTurn(mode: .translate, restText: "Hello, how are you?") { client in
      client.fixturePartial("नमस्ते, आप कैसे हैं", utterance: 0)
    }
    XCTAssertEqual(outcome.delivered, ["Hello, how are you?"])
    XCTAssertEqual(outcome.restCalls, 1)
  }

  func testAPartialOnlyUtteranceHandsTheTurnToREST() {
    let outcome = timedOutTurn(mode: .transcribe, restText: "First. Second part.") { client in
      client.fixtureFinal("First.", utterance: 0)
      client.fixturePartial("second par", utterance: 1)
    }
    XCTAssertEqual(outcome.delivered, ["First. Second part."])
    XCTAssertEqual(outcome.restCalls, 1)
  }

  func testFinalsWithoutConfirmedTerminalCoverageGoToREST() {
    // Finals for every observed utterance, but none whose end_s proves it ended the turn:
    // a later segment may be missing, so REST settles the turn.
    let outcome = timedOutTurn(mode: .transcribe, restText: "First. Second. Third.") { client in
      client.fixtureFinal("First.", utterance: 0)
      client.fixtureFinal("Second.", utterance: 1)
    }
    XCTAssertEqual(outcome.delivered, ["First. Second. Third."])
    XCTAssertEqual(outcome.restCalls, 1)
  }
}
