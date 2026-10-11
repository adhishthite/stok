// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import StokEngine

final class LiveKeepaliveTests: XCTestCase {
  func testKeepaliveArmsOnSessionBeginAndStopsOnDisconnect() {
    let client = SarvamLiveClient(apiKey: "")
    XCTAssertFalse(client.fixtureKeepaliveArmed)
    client.fixtureSessionBegin()
    XCTAssertTrue(client.fixtureKeepaliveArmed)
    client.disconnect()
    XCTAssertFalse(client.fixtureKeepaliveArmed)
  }

  func testConnectionFailureStopsTheKeepalive() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureSessionBegin()
    XCTAssertTrue(client.fixtureKeepaliveArmed)
    client.recoveryConnectionFailure()
    XCTAssertFalse(client.fixtureKeepaliveArmed)
  }

  func testIdleKeepaliveSendsAPingEventWellInsideTheInactivityWindow() {
    // The server closes a session after 60 s without audio or a ping (close 1008).
    XCTAssertLessThan(
      SarvamLiveClient.keepaliveIntervalSeconds + SarvamLiveClient.pongTimeoutSeconds,
      SarvamAPI.realtimeInactivitySeconds)
    let probe = LiveWriteProbe()
    let client = SarvamLiveClient(apiKey: "")
    client.recoveryFixture(probe)
    client.recoveryReady()
    client.sendKeepalivePing(epoch: client.connectionID)
    XCTAssertEqual(probe.sent, ["{\"event\":\"ping\"}"])
    XCTAssertNotNil(client.pongDeadline, "a ping waits for its pong")
    client.fixtureEvent(["event": "pong"])
    XCTAssertNil(client.pongDeadline, "the pong proves the path")
    XCTAssertTrue(client.fixtureKeepaliveArmed, "the next ping is armed")
    client.disconnect()
  }

  func testMissingPongIsReportedAsALostKeepalive() {
    let probe = LiveWriteProbe()
    let client = SarvamLiveClient(apiKey: "")
    client.recoveryFixture(probe)
    client.recoveryReady()
    var kinds: [String] = []
    client.onConnectionEvent = { kind, _, _ in kinds.append(kind) }
    client.sendKeepalivePing(epoch: client.connectionID)
    client.pongDeadline?.perform()
    XCTAssertEqual(kinds, ["lost_keepalive"])
    XCTAssertFalse(client.isReady)
    client.disconnect()
  }

  func testAPingIsNotSentDuringATurn() {
    let probe = LiveWriteProbe()
    let client = SarvamLiveClient(apiKey: "")
    client.recoveryFixture(probe)
    client.recoveryReady()
    client.startNewTurn()
    client.recoveryDrain()
    let before = probe.sent.count
    client.sendKeepalivePing(epoch: client.connectionID)
    XCTAssertEqual(probe.sent.count, before, "turn audio is its own proof of life")
    XCTAssertNil(client.pongDeadline)
    client.disconnect()
  }
}
