// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import XCTest

@testable import StokEngine

final class DeadlineTests: XCTestCase {
  func testReferenceDeadlineBounds() {
    for timeout in [-10.0, 0, 2.5, 4, 100] {
      let budget = TurnDeadline.budget(fallbackTimeout: timeout)
      XCTAssertGreaterThanOrEqual(budget, TurnDeadline.minimumSeconds)
      XCTAssertGreaterThan(budget, max(0, timeout) + SarvamRestClient.requestTimeout)
      for elapsed in [0.0, 2, 15, 40] {
        XCTAssertEqual(
          TurnDeadline.remaining(budget: budget, elapsed: elapsed), max(0, budget - elapsed))
      }
    }
  }

  func testTurnsOfOneWaveShareOneDeadline() {
    for timeout in [0.1, 4, 30] {
      XCTAssertEqual(
        TurnDeadline.budget(fallbackTimeout: timeout, audioBytes: 29 * 32_000),
        TurnDeadline.budget(fallbackTimeout: timeout))
    }
    // The default fallback delay, one wave with its 429 retry, and the margin.
    XCTAssertEqual(TurnDeadline.budget(fallbackTimeout: 4, audioBytes: 10 * 32_000), 43)
  }

  func testLongRecordingsGetTimeForEveryRestWave() {
    // A ten-minute dictation goes to REST as 21 or more pieces, four at a time. A deadline
    // sized for one request would cancel the fallback and discard the whole transcript.
    let tenMinutes = 600 * 32_000
    let pieces = RestAudioPlan.maxPieceCount(audioBytes: tenMinutes)
    XCTAssertGreaterThanOrEqual(pieces, RestAudioPlan.pieces(of: Data(count: tenMinutes)).count)
    let waves =
      (pieces + RestTranscriptAssembler.maxConcurrent - 1) / RestTranscriptAssembler.maxConcurrent
    XCTAssertEqual(
      TurnDeadline.budget(fallbackTimeout: 4, audioBytes: tenMinutes),
      4 + Double(waves) * TurnDeadline.secondsPerWave + TurnDeadline.marginSeconds)
    // Two minutes is six pieces: two waves.
    XCTAssertEqual(TurnDeadline.budget(fallbackTimeout: 4, audioBytes: 120 * 32_000), 81)
  }

  func testEveryWaveGetsAWholeRequestTimeoutAfterTheFallbackDelay() {
    // The REST hedge starts after the fallback delay, and each wave of pieces may take a
    // full request timeout.
    for (seconds, waves) in [(10, 1), (120, 2), (600, 8)] {
      let budget = TurnDeadline.budget(fallbackTimeout: 4, audioBytes: seconds * 32_000)
      XCTAssertGreaterThan(
        budget, 4 + Double(waves) * SarvamRestClient.requestTimeout, "\(seconds) s")
    }
    XCTAssertGreaterThan(
      TurnDeadline.budget(fallbackTimeout: 30, audioBytes: 10 * 32_000),
      30 + SarvamRestClient.requestTimeout)
  }

  func testEveryWaveGetsTimeForA429BackoffAndTheRetriedRequest() {
    // A piece may wait a full request timeout for a 429, back off for up to maxRetryDelay,
    // and retry once with another full request timeout.
    let perWave = 2 * SarvamRestClient.requestTimeout + SarvamRestClient.maxRetryDelay
    for (seconds, waves) in [(10, 1), (120, 2), (600, 8)] {
      XCTAssertGreaterThanOrEqual(
        TurnDeadline.budget(fallbackTimeout: 4, audioBytes: seconds * 32_000),
        4 + Double(waves) * perWave, "\(seconds) s")
    }
  }
}
