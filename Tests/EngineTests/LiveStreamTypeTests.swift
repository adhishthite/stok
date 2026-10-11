// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import StokEngine

/// stream_type and the live-route health signal. "fast" sends partials for the overlay;
/// "simulated" sends finals only and settles sooner, so it is used whenever nothing would be
/// shown. Simulated sends nothing during a turn unless asked (verified 2026-10-07), so the
/// early REST hedge cannot use partials as its proof that the live route is alive.
final class LiveStreamTypeTests: XCTestCase {
  func testStreamTypeFollowsLiveWordsAndPrivacy() {
    XCTAssertEqual(EngineConfiguration.load(values: [:]).liveStreamType, "fast")
    XCTAssertEqual(
      EngineConfiguration.load(values: ["LIVE_WORDS": "false"]).liveStreamType, "simulated")
    // Hidden words on screen: nothing is shown, so partials are never worth their latency.
    XCTAssertEqual(
      EngineConfiguration.load(values: ["PRIVACY_MODE": "true"]).liveStreamType, "simulated")
    XCTAssertEqual(
      EngineConfiguration.load(values: ["PRIVACY_MODE": "true", "LIVE_WORDS": "true"])
        .liveStreamType, "simulated")
    let setting = SettingCatalog.all.first { $0.key == "LIVE_WORDS" }
    XCTAssertEqual(setting?.defaultValue, "true")
    XCTAssertEqual(setting?.restartsEngine, false, "applied by reconnecting the socket")
  }

  func testSessionURLCarriesTheStreamType() {
    let url = SarvamLiveClient.sessionURL(
      model: "saaras:v4", mode: .transcribe, language: "en-IN", keyterms: [],
      streamType: "simulated")
    let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertEqual(items.first { $0.name == "stream_type" }?.value, "simulated")
  }

  func testChangingStreamTypeReconnectsWhenIdleAndAfterAnOpenTurn() {
    // config.update cannot switch to or from simulated mid-session (verified), so a change
    // needs a new session: at once when idle, after the turn when one is open.
    let idle = SarvamLiveClient(apiKey: "fixture-key")
    var idleKinds: [String] = []
    idle.onConnectionEvent = { kind, _, _ in idleKinds.append(kind) }
    idle.setStreamType("fast")
    XCTAssertEqual(idleKinds, [], "the same stream type changes nothing")
    idle.setStreamType("simulated")
    XCTAssertEqual(idleKinds, ["connect_reconnect"])
    idle.shutdown()

    let busy = SarvamLiveClient(apiKey: "fixture-key")
    var busyKinds: [String] = []
    busy.onConnectionEvent = { kind, _, _ in busyKinds.append(kind) }
    busy.fixtureOpen()
    busy.setStreamType("simulated")
    XCTAssertEqual(busyKinds, [], "an open turn keeps its session")
    busy.fixtureCompletion { _ in }
    busy.fixtureFinal("Done.", utterance: 0)
    XCTAssertEqual(busyKinds, ["connect_reconnect"], "the new session opens after the turn")
    busy.shutdown()
  }

  /// Streams `chunks` 100 ms frames in real time through `probe`, acknowledging every write.
  private func streamedTurn(chunks: Int, answerPings: Bool) -> (SarvamLiveClient, LiveWriteProbe) {
    let probe = LiveWriteProbe()
    let client = SarvamLiveClient(apiKey: "", streamType: "simulated")
    client.recoveryFixture(probe)
    client.recoveryReady()
    client.startNewTurn()
    var acknowledged = 0
    func acknowledge() {
      client.recoveryDrain()
      while acknowledged < probe.sent.count {
        let message = probe.sent[acknowledged]
        probe.finish(acknowledged)
        acknowledged += 1
        client.recoveryDrain()
        if answerPings, message.contains("\"ping\"") { client.fixtureEvent(["event": "pong"]) }
      }
    }
    acknowledge()
    for _ in 0..<chunks {
      client.sendAudioChunk(Data(count: 3_200))
      acknowledge()
      Thread.sleep(forTimeInterval: 0.1)
    }
    return (client, probe)
  }

  func testHealthySimulatedTurnProvesItselfAliveWithoutPartials() {
    let (client, probe) = streamedTurn(chunks: 25, answerPings: true)
    defer { client.disconnect() }
    XCTAssertTrue(
      probe.sent.contains { $0.contains("\"ping\"") }, "the turn asks the server for a pong")
    let age = client.liveSignalAgeSeconds
    XCTAssertNotNil(age)
    XCTAssertFalse(
      DictationEngine.shouldHedgeEarly(duration: 2.5, liveSignalAgeSeconds: age),
      "no REST hedge on a healthy simulated turn")
  }

  func testDeadLiveRouteStillHedgesEarly() {
    let (client, _) = streamedTurn(chunks: 25, answerPings: false)
    defer { client.disconnect() }
    XCTAssertNil(client.liveSignalAgeSeconds)
    XCTAssertTrue(
      DictationEngine.shouldHedgeEarly(
        duration: 2.5, liveSignalAgeSeconds: client.liveSignalAgeSeconds))
  }

  func testHedgeRuleUsesTheAgeOfTheLastSignal() {
    XCTAssertFalse(DictationEngine.shouldHedgeEarly(duration: 1.5, liveSignalAgeSeconds: nil))
    XCTAssertFalse(DictationEngine.shouldHedgeEarly(duration: 2.5, liveSignalAgeSeconds: 0.3))
    XCTAssertTrue(DictationEngine.shouldHedgeEarly(duration: 2.5, liveSignalAgeSeconds: nil))
    // A route that answered early in the hold and then went silent is dead now.
    XCTAssertTrue(DictationEngine.shouldHedgeEarly(duration: 6, liveSignalAgeSeconds: 5))
  }
}
