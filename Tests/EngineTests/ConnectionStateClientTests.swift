// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import StokEngine

/// Connection state, hedge, and round-trip split, at the SarvamLiveClient level:
/// the key-down readiness accessor, the per-turn reconnect/loss flag, the commit round-trip
/// split, and the connect-reason-to-connection_events-kind mapping.
final class ConnectionStateClientTests: XCTestCase {
  func testSocketStateAtKeydownTracksReadinessTransitions() {
    let probe = LiveWriteProbe()
    let client = SarvamLiveClient(apiKey: "")
    check(client.socketStateAtKeydown.state == "closed", "never connected reads as closed")
    check(client.socketStateAtKeydown.ageMs == nil, "closed has no session age")
    client.recoveryFixture(probe)
    check(
      client.socketStateAtKeydown.state == "connecting",
      "a socket exists but the handshake has not completed")
    client.recoveryReady()
    check(client.socketStateAtKeydown.state == "ready", "setupComplete makes the session ready")
    check(
      client.socketStateAtKeydown.ageMs != nil && client.socketStateAtKeydown.ageMs! >= 0,
      "a ready session reports its age")
    client.disconnect()
    check(client.socketStateAtKeydown.state == "closed", "disconnect returns to closed")
  }

  func testConnectionChangedDuringTurnResetsPerTurnAndTracksLoss() {
    let probe = LiveWriteProbe()
    let client = SarvamLiveClient(apiKey: "")
    client.recoveryFixture(probe)
    client.startNewTurn()
    check(
      !client.lastConnectionChangedDuringTurn,
      "a freshly started turn has seen no connection change yet")
    client.recoveryConnectionFailure()
    check(
      client.lastConnectionChangedDuringTurn,
      "a lost connection during the turn is recorded")
    client.startNewTurn()
    check(
      !client.lastConnectionChangedDuringTurn, "the next turn starts with a clean flag again")
  }

  func testRoundTripFirstMessageFinalAndTurnCompleteAreCaptured() {
    let client = SarvamLiveClient(apiKey: "")
    client.startNewTurn()
    check(client.lastRoundTrip.firstMsgMs == nil, "nothing is captured before commit")
    client.fixtureCompletion { _ in }
    client.fixtureEvent(["event": "pong"])
    check(
      client.lastRoundTrip.firstMsgMs != nil,
      "the first post-commit message is recorded even when it carries no text")
    check(client.lastRoundTrip.finalMs == nil, "no transcription message has arrived yet")
    client.fixturePartial("Hel", utterance: 0)
    check(
      client.lastRoundTrip.finalMs != nil,
      "a transcription message sets commit_to_final_ms")
    check(client.lastRoundTrip.turnCompleteMs == nil, "no terminal final has arrived yet")
    client.fixtureFinal("Hello.", utterance: 0)
    check(
      client.lastRoundTrip.turnCompleteMs != nil,
      "the final that answers speech_end is recorded as the turn's completion")
  }

  func testRoundTripLastSendMsCapturedWhenTerminatorsFlush() {
    let probe = LiveWriteProbe()
    // One terminal write: speech_end.
    let client = SarvamLiveClient(apiKey: "")
    client.recoveryFixture(probe)
    client.startNewTurn()
    client.recoveryReady()
    probe.finish(0)
    client.recoveryDrain()
    check(client.lastRoundTrip.lastSendMs == nil, "no round trip before commit")
    client.commitTurn { _ in }
    client.recoveryDrain()
    check(client.recoveryPending == 1, "speech_end is queued")
    check(client.lastRoundTrip.lastSendMs == nil, "still waiting on speech_end")
    probe.finish(1)
    client.recoveryDrain()
    check(
      client.lastRoundTrip.lastSendMs != nil,
      "commit_to_last_send_ms lands once speech_end is on the wire")
    client.disconnect()
  }

  func testConnectReasonMapsToConnectionEventKind() {
    let client = SarvamLiveClient(apiKey: "fixture-key")
    var kinds: [String] = []
    client.onConnectionEvent = { kind, _, _ in kinds.append(kind) }
    client.connect(reason: "startup")
    client.connect(reason: "wake")
    client.connect(reason: "reconnect")
    client.connect(reason: "anything else")
    client.shutdown()
    check(
      kinds == [
        "connect_startup", "connect_wake", "connect_reconnect", "connect_reconnect",
        "closed_by_client",
      ],
      "each connect reason maps to its own connection_events kind, and shutdown reports "
        + "closed_by_client: \(kinds)")
  }

  func testConnectionFailureReasonMapsToLostErrorOrLostKeepalive() {
    let probe = LiveWriteProbe()
    let client = SarvamLiveClient(apiKey: "")
    client.recoveryFixture(probe)
    var kinds: [String] = []
    client.onConnectionEvent = { kind, _, _ in kinds.append(kind) }
    client.connectionFailed(epoch: 0, error: NSError(domain: "fixture", code: 1))
    check(kinds.last == "lost_error", "the default reason reports lost_error")
    client.recoveryFixture(probe)
    client.connectionFailed(
      epoch: 0, error: NSError(domain: "fixture", code: 2), reason: "keepalive")
    check(kinds.last == "lost_keepalive", "a keepalive-tagged failure reports lost_keepalive")
  }
}
