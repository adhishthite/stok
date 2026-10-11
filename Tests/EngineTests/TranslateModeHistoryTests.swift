// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import XCTest

@testable import StokEngine

/// Translate mode: the live overlay streams the spoken language, but the final the service
/// returns is English, and that English is what Stok pastes and what history keeps.
final class TranslateModeHistoryTests: XCTestCase {
  func testTranslateModePastesAndRecordsTheEnglishFinal() {
    var config = EngineConfiguration.load(values: [
      "TRANSCRIPTION_MODE": "translate", "LANGUAGE": "hi-IN",
    ])
    config.historyEnabled = false
    config.soundFeedback = false
    config.enableLiveWebSocket = false
    config.restoreClipboard = false
    config.trailingSpace = true
    var delivered: [String] = []
    // A sink delivery never touches the clipboard or synthesizes a paste.
    let engine = DictationEngine(config: config, delivery: .sink { delivered.append($0) })
    let recorder = EngineEventRecorder()
    engine.delegate = recorder
    engine.sessionQueue.sync {
      engine.isProcessing = true
      engine.settle(
        turnId: 0, route: "WS",
        outcome: .success(
          text: "My meeting is at 3:00.", transport: "fixture", firstTokenMs: 0, roundtripMs: 0,
          audioDuration: 1, keyUpTime: ProcessInfo.processInfo.systemUptime,
          captureFinalizeMs: 0, fallbackReason: nil, isLiveRoute: true))
    }
    let done = expectation(description: "turn settled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
    wait(for: [done], timeout: 2)
    let record = recorder.events.compactMap { event -> TurnRecord? in
      if case .turnSettled(let record) = event { return record }
      return nil
    }.first
    XCTAssertEqual(record?.text, "My meeting is at 3:00.", "history keeps the clean English")
    XCTAssertEqual(record?.languageCodes, "hi-IN")
    XCTAssertEqual(delivered, ["My meeting is at 3:00. "], "only the paste gets the space")
  }
}
