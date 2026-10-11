// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import AppKit
import AudioToolbox
import Carbon
import CoreAudio
import Foundation
import IOKit
import Network
import SQLite3
import XCTest

@testable import StokEngine

final class LiveRecoveryRegressionTests: XCTestCase {
  func testReferenceFixtures() throws {
    // Transport callbacks are controlled without opening a network connection.

    let startupProbe = LiveWriteProbe()
    let startupClient = SarvamLiveClient(apiKey: "")
    startupClient.recoveryFixture(startupProbe)
    startupClient.startNewTurn()
    startupClient.sendAudioChunk(Data([1, 2]))
    startupClient.sendAudioChunk(Data([3, 4]))
    startupClient.recoveryDrain()
    check(startupProbe.sent.isEmpty, "startup audio waits for setup")
    check(
      startupClient.recoveryPending == 3 && !startupClient.recoveryGap,
      "entire startup prefix retained")
    startupClient.recoveryConnectionFailure()
    check(
      !startupClient.recoveryGap && startupClient.recoveryPending == 3,
      "unsent prefix survives setup failure")
    startupClient.recoveryReady()
    check(
      startupProbe.sent.count == 1 && startupProbe.sent[0].contains("speech_start"),
      "speech_start precedes replay")
    startupProbe.finish(0)
    startupClient.recoveryDrain()
    check(
      startupProbe.sent.count == 2 && startupProbe.sent[1].contains("AQI="),
      "first startup audio ordered")
    startupProbe.finish(1)
    startupClient.recoveryDrain()
    check(
      startupProbe.sent.count == 3 && startupProbe.sent[2].contains("AwQ="),
      "second startup audio ordered")
    var recoveryCommitResults = 0
    startupClient.commitTurn { _ in recoveryCommitResults += 1 }
    startupClient.recoveryDrain()
    check(startupProbe.sent.count == 3, "commit waits for final audio send completion")
    startupProbe.finish(2)
    startupClient.recoveryDrain()
    check(
      startupProbe.sent.count == 4 && startupProbe.sent[3].contains("speech_end"),
      "commit begins after replay with the documented end signal")
    startupClient.disconnect()
    check(
      recoveryCommitResults == 1 && startupClient.recoveryPending == 0,
      "disconnect settles once and releases writes")
    startupProbe.finish(3)
    startupClient.recoveryDrain()
    check(recoveryCommitResults == 1, "late write callback cannot settle twice")

    let boundedClient = SarvamLiveClient(apiKey: "")
    boundedClient.startNewTurn()
    boundedClient.recoverySend(String(repeating: "x", count: 256 * 1024))
    check(
      boundedClient.recoveryGap && boundedClient.recoveryPending == 0,
      "overflow rejects incomplete Live turn")
    boundedClient.startNewTurn()
    check(
      !boundedClient.recoveryGap && boundedClient.recoveryPending == 1,
      "next turn clears failed backlog")
    boundedClient.recoveryExpire()
    check(
      boundedClient.recoveryGap && boundedClient.recoveryPending == 0,
      "startup timeout releases backlog")
    boundedClient.abandonTurn()

    let failureProbe = LiveWriteProbe()
    let failureClient = SarvamLiveClient(apiKey: "")
    failureClient.recoveryFixture(failureProbe)
    failureClient.startNewTurn()
    failureClient.recoveryReady()
    failureClient.sendAudioChunk(Data([8]))
    failureClient.recoveryDrain()
    let pendingCommitFinished = DispatchSemaphore(value: 0)
    var pendingCommitCount = 0
    failureClient.commitTurn { result in
      if case .success = result { XCTFail("incomplete stream succeeded") }
      pendingCommitCount += 1
      pendingCommitFinished.signal()
    }
    failureProbe.finish(0, error: NSError(domain: "fixture", code: 1))
    failureClient.recoveryDrain()
    check(
      pendingCommitFinished.wait(timeout: .now() + 1) == .success && pendingCommitCount == 1,
      "pending commit fails once on send error")
    check(
      failureClient.recoveryGap && failureClient.recoveryPending == 0,
      "transport failure invalidates whole stream")
    failureClient.startNewTurn()
    failureProbe.finish(0)
    failureClient.recoveryDrain()
    check(
      !failureClient.recoveryGap && failureClient.recoveryPending == 1,
      "stale callback cannot consume next turn")
    failureClient.disconnect()

    // A final that lands before speech_end is acknowledged waits for it, then settles.
    let endingProbe = LiveWriteProbe()
    let endingClient = SarvamLiveClient(apiKey: "")
    endingClient.recoveryFixture(endingProbe)
    endingClient.startNewTurn()
    endingClient.recoveryReady()
    endingProbe.finish(0)
    endingClient.recoveryDrain()
    endingClient.fixturePartial("Complete words", utterance: 0)
    let endingSettled = DispatchSemaphore(value: 0)
    let endingLock = NSLock()
    var endingResults = 0
    var endingText = ""
    endingClient.commitTurn { result in
      endingLock.lock()
      endingResults += 1
      if case .success(let value) = result { endingText = value.text }
      endingLock.unlock()
      endingSettled.signal()
    }
    endingClient.recoveryDrain()
    endingClient.recoveryForceSettleAge()
    check(
      endingResults == 0 && endingClient.recoveryPending == 1,
      "timer cannot settle while speech_end is pending")
    endingClient.fixtureFinal("Complete words.", utterance: 0)
    check(
      endingResults == 0 && endingClient.recoveryPending == 1,
      "an early final waits for speech_end without dropping it")
    endingProbe.finish(1)
    endingClient.recoveryDrain()
    check(endingSettled.wait(timeout: .now() + 2) == .success, "the turn settles after speech_end")
    endingLock.lock()
    check(
      endingResults == 1 && endingText == "Complete words.",
      "early final retained until speech_end is on the wire")
    endingLock.unlock()
    endingProbe.finish(1)
    endingClient.recoveryDrain()
    endingLock.lock()
    check(endingResults == 1, "duplicate terminal callback cannot settle twice")
    endingLock.unlock()
    endingClient.disconnect()

    let expiredEndProbe = LiveWriteProbe()
    let expiredEndClient = SarvamLiveClient(apiKey: "")
    expiredEndClient.recoveryFixture(expiredEndProbe)
    expiredEndClient.startNewTurn()
    expiredEndClient.recoveryReady()
    expiredEndProbe.finish(0)
    expiredEndClient.recoveryDrain()
    expiredEndClient.fixturePartial("Never paste this partial turn.", utterance: 0)
    var expiredEndResults = 0
    expiredEndClient.commitTurn { result in
      if case .success = result { XCTFail("expired terminator succeeded") }
      expiredEndResults += 1
    }
    expiredEndClient.recoveryDrain()
    expiredEndClient.fixtureFinal("Never paste this partial turn.", utterance: 0)
    expiredEndClient.recoveryExpire()
    check(
      expiredEndResults == 1 && expiredEndClient.recoveryGap,
      "expired terminator fails even after an early final")
    expiredEndProbe.finish(1)
    expiredEndClient.recoveryDrain()
    check(expiredEndResults == 1, "expired terminator late callback does not settle twice")
    expiredEndClient.disconnect()

  }
}
