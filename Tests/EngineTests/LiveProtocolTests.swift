// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import StokEngine

/// The realtime socket protocol, as verified against the live endpoint on 2026-10-07: query
/// parameters, the speech_start/audio_input/speech_end turn bracket, transcript events, and
/// how fatal errors and close codes are read. No network connection is opened.
final class LiveProtocolTests: XCTestCase {
  private func query(_ url: URL?) -> [String: String] {
    let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
  }

  func testSessionURLCarriesEveryOptionAndNeverTheKey() throws {
    let url = SarvamLiveClient.sessionURL(
      model: "saaras:v4", mode: .transcribe, language: "en-IN",
      keyterms: ["C++", "Kubernetes"])
    XCTAssertEqual(url?.host, "api.sarvam.ai")
    XCTAssertEqual(url?.path, "/speech-to-text-realtime/ws")
    let items = query(url)
    XCTAssertEqual(items["language_code"], "en-IN")
    XCTAssertEqual(items["model"], "saaras:v4")
    XCTAssertEqual(items["mode"], "transcribe")
    XCTAssertEqual(items["endpointing"], "manual")
    XCTAssertEqual(items["stream_type"], "fast")
    XCTAssertEqual(items["encoding"], "linear16")
    XCTAssertEqual(items["sample_rate"], "16000")
    XCTAssertEqual(items["return_timestamps"], "true")
    let keyterms = try XCTUnwrap(items["keyterms"])
    XCTAssertEqual(
      try JSONSerialization.jsonObject(with: Data(keyterms.utf8)) as? [String],
      ["C++", "Kubernetes"])
    // A raw "+" in a query reads as a space on the server.
    XCTAssertTrue(url!.absoluteString.contains("%2B%2B"))
    XCTAssertFalse(url!.absoluteString.contains("subscription"))
  }

  func testAutomaticDetectionAndOlderModelsSendNoKeyterms() {
    let items = query(
      SarvamLiveClient.sessionURL(
        model: "saaras:v3-realtime", mode: .verbatim, language: "auto", keyterms: ["Stok"]))
    XCTAssertEqual(items["language_code"], "auto")
    XCTAssertEqual(items["mode"], "verbatim")
    XCTAssertNil(items["keyterms"], "keyterms are a saaras:v4 feature; v3 rejects them")
  }

  func testSessionURLCarriesEveryModeAndTheRealtimeLanguageSpelling() {
    for mode in TranscriptionMode.allCases {
      let items = query(
        SarvamLiveClient.sessionURL(model: "saaras:v4", mode: mode, language: "hi-IN", keyterms: [])
      )
      XCTAssertEqual(items["mode"], mode.rawValue)
      XCTAssertEqual(items["language_code"], "hi-IN")
    }
    // Verified live 2026-10-07: the realtime socket accepts only or-IN for Odia.
    let odia = query(
      SarvamLiveClient.sessionURL(
        model: "saaras:v4", mode: .translate, language: "or-IN", keyterms: []))
    XCTAssertEqual(odia["language_code"], "or-IN")
    XCTAssertEqual(odia["mode"], "translate")
  }

  func testTurnIsBracketedBySpeechStartAndSpeechEnd() throws {
    let probe = LiveWriteProbe()
    let client = SarvamLiveClient(apiKey: "")
    client.recoveryFixture(probe)
    client.recoveryReady()
    client.startNewTurn()
    client.sendAudioChunk(Data([1, 2]))
    client.recoveryDrain()
    probe.finish(0)
    client.recoveryDrain()
    client.commitTurn { _ in }
    client.recoveryDrain()
    probe.finish(1)
    client.recoveryDrain()
    let events = try probe.sent.map {
      try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String])
    }
    XCTAssertEqual(events.map { $0["event"] }, ["speech_start", "audio_input", "speech_end"])
    XCTAssertEqual(events[1]["audio"], "AQI=")
    client.disconnect()
  }

  func testFinalThatAnswersSpeechEndSettlesOnTheServerBoundary() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    client.fixturePartial("Hel", utterance: 0)
    var result: Result<(text: String, firstTokenMs: Double, totalMs: Double), Error>?
    client.fixtureCompletion { result = $0 }
    client.fixtureFinal("Hello.", utterance: 0)
    guard case .success(let payload) = result else {
      return XCTFail("the terminal final settles at once")
    }
    XCTAssertEqual(payload.text, "Hello.")
    XCTAssertEqual(client.lastSettlePath, "server_final")
    XCTAssertNotNil(client.lastRoundTrip.turnCompleteMs)
  }

  func testEmptyFinalAfterSpeechEndIsTheNoSpeechVerdict() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    var failure: NSError?
    client.fixtureCompletion { if case .failure(let error) = $0 { failure = error as NSError } }
    client.fixtureFinal("", utterance: 0)
    XCTAssertEqual(failure?.code, -2)
    XCTAssertEqual(client.lastSettlePath, "server_final")
  }

  func testSplitTurnSettlesOnTheFinalThatEndsTheTurn() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    // The server finalizes long speech in segments even with manual endpointing.
    client.fixtureFinal("Part one.", utterance: 0, endS: 20)
    client.fixturePartial("Part", utterance: 1)
    var text = ""
    client.fixtureCompletion { result in
      if case .success(let payload) = result { text = payload.text }
    }
    client.fixtureFinal("Part two.", utterance: 1, endS: 0)
    XCTAssertEqual(text, "Part one. Part two.")
    XCTAssertEqual(client.lastSettlePath, "server_final")
  }

  func testFinalBeforeSpeechEndIsOnTheWireDoesNotEndTheTurn() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    var results = 0
    client.fixtureCompletion { _ in results += 1 }
    client.commitWritesComplete = false
    client.fixtureFinal("Early.", utterance: 0)
    XCTAssertEqual(results, 0, "a final cannot answer an end signal that has not been sent")
  }

  func testLateEventsFromAnOldConnectionAreIgnored() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    client.fixtureFinal("Old connection", utterance: 0, oldConnection: true)
    XCTAssertTrue(client.fixtureText().isEmpty)
  }

  func testKeyRejectionStopsReconnectingAfterThreeFatalErrors() {
    let client = SarvamLiveClient(apiKey: "")
    var rejections = 0
    client.onAuthRejected = { rejections += 1 }
    for _ in 1...3 {
      client.recoveryFixture(LiveWriteProbe())
      // Verified shape: the upgrade succeeds, then this event, then close 1003.
      client.fixtureEvent([
        "event": "error", "code": "invalid_subscription_key", "is_fatal": true,
        "status_code": 401, "message": "Invalid subscription key.",
      ])
      // The cancelled task's receive failure takes this path in the app.
      client.connectionFailed(epoch: client.connectionID, error: URLError(.cancelled))
    }
    XCTAssertEqual(rejections, 1)
  }

  func testNonFatalErrorLeavesTheSessionOpen() {
    let client = SarvamLiveClient(apiKey: "")
    client.recoveryFixture(LiveWriteProbe())
    client.recoveryReady()
    client.fixtureEvent(["event": "error", "code": "transient", "is_fatal": false])
    XCTAssertTrue(client.isReady)
    client.disconnect()
  }

  func testOnlyACloseThatNamesTheKeyCountsAsARejection() {
    XCTAssertTrue(
      SarvamLiveClient.closeIndicatesKeyRejection(
        code: 1003,
        reason:
          "Invalid subscription key. Visit the API Dashboard to review and manage your subscription."
      ))
    // 1003 also covers rate limits and quota; 1008 is the inactivity timeout; 4000 is a
    // rejected parameter. None of them is a key verdict.
    XCTAssertFalse(SarvamLiveClient.closeIndicatesKeyRejection(code: 1003, reason: "Rate limit"))
    XCTAssertFalse(
      SarvamLiveClient.closeIndicatesKeyRejection(code: 1008, reason: "Inactivity timeout"))
    XCTAssertFalse(
      SarvamLiveClient.closeIndicatesKeyRejection(code: 4000, reason: "Invalid sample_rate"))
    XCTAssertTrue(
      SarvamLiveClient.errorIndicatesKeyRejection(code: "invalid_subscription_key", statusCode: 401)
    )
    XCTAssertFalse(
      SarvamLiveClient.errorIndicatesKeyRejection(code: "inactivity_timeout", statusCode: 408))
    XCTAssertFalse(
      SarvamLiveClient.errorIndicatesKeyRejection(code: "invalid_request", statusCode: 400))
  }

  func testKeytermsRespectTheServiceLimits() {
    let long = String(repeating: "x", count: SarvamAPI.maxKeytermLength + 1)
    let vocabulary = ["Stok", "stok", " ", long] + (1...60).map { "term\($0)" }
    let terms = SarvamAPI.keyterms(from: vocabulary)
    XCTAssertEqual(terms.count, SarvamAPI.maxKeyterms)
    XCTAssertEqual(terms.first, "Stok")
    XCTAssertFalse(terms.contains("stok"), "duplicates ignoring case are sent once")
    XCTAssertFalse(terms.contains(long), "a term past 64 characters is left out, not cut")
    XCTAssertEqual(terms.last, "term49")
    XCTAssertNil(SarvamAPI.keytermsJSON([]))
  }

  /// A long turn the server split into segments: the final for an earlier segment can
  /// arrive after speech_end, before any event for the later segment. The turn must wait.
  private func committedLongTurn(
    seconds: Int, probe: LiveWriteProbe, streamType: String = "fast",
    completion:
      @escaping (Result<(text: String, firstTokenMs: Double, totalMs: Double), Error>) -> Void
  ) -> SarvamLiveClient {
    let client = SarvamLiveClient(apiKey: "", streamType: streamType)
    client.recoveryFixture(probe)
    client.recoveryReady()
    client.startNewTurn()
    client.recoveryDrain()
    probe.finish(0)
    client.recoveryDrain()
    client.fixtureStreamAndCommit(seconds: seconds, probe: probe, completion: completion)
    return client
  }

  func testDelayedSegmentFinalWithTimestampsWaitsForTheTerminalFinal() {
    let probe = LiveWriteProbe()
    let lock = NSLock()
    var results: [String] = []
    let client = committedLongTurn(seconds: 41, probe: probe) { result in
      lock.lock()
      if case .success(let payload) = result { results.append(payload.text) }
      lock.unlock()
    }
    defer { client.disconnect() }
    // Verified shape: end_s counts audio seconds since the session began. The turn sent
    // 41 s, so a final ending at 20 s is an earlier segment, not the answer to speech_end.
    client.fixtureFinal("Segment one.", utterance: 0, endS: 20.0)
    lock.lock()
    XCTAssertEqual(results, [], "an earlier segment's final must not end the turn")
    lock.unlock()
    client.fixtureFinal("Segment two.", utterance: 1, endS: 41.0)
    lock.lock()
    XCTAssertEqual(results, ["Segment one. Segment two."])
    lock.unlock()
    XCTAssertEqual(client.lastSettlePath, "server_final")
  }

  func testDelayedSegmentFinalWithoutTimestampsIsNotTreatedAsTerminal() {
    let probe = LiveWriteProbe()
    let settled = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var results: [String] = []
    var failure: Int?
    let client = committedLongTurn(seconds: 41, probe: probe) { result in
      lock.lock()
      switch result {
      case .success(let payload): results.append(payload.text)
      case .failure(let error): failure = (error as NSError).code
      }
      lock.unlock()
      settled.signal()
    }
    defer { client.disconnect() }
    // Without end_s, a turn longer than the server's segment length cannot trust that any
    // final it sees after speech_end is the last one, so it never has confirmed coverage:
    // the timeout hands it to REST instead of pasting what arrived.
    client.fixtureFinal("Segment one.", utterance: 0)
    lock.lock()
    XCTAssertEqual(results, [], "a long turn's first final must not settle at once")
    lock.unlock()
    client.fixtureFinal("Segment two.", utterance: 1)
    XCTAssertEqual(settled.wait(timeout: .now() + 3), .success)
    lock.lock()
    XCTAssertEqual(results, [])
    XCTAssertEqual(failure, SarvamLiveClient.incompleteTranscriptError().code)
    lock.unlock()
  }

  func testShortTurnStillSettlesOnItsFirstFinalWithTimestamps() {
    let probe = LiveWriteProbe()
    var results: [String] = []
    let client = committedLongTurn(seconds: 3, probe: probe) { result in
      if case .success(let payload) = result { results.append(payload.text) }
    }
    defer { client.disconnect() }
    client.fixtureFinal("Short.", utterance: 0, endS: 3.0)
    XCTAssertEqual(results, ["Short."])
    XCTAssertEqual(client.lastSettlePath, "server_final")
  }

  /// Waits for one completion and returns its text and the elapsed seconds.
  private func awaitResult(
    _ setup: (
      @escaping (Result<(text: String, firstTokenMs: Double, totalMs: Double), Error>) -> Void
    )
      -> Void
  ) -> (text: String?, failureCode: Int?, seconds: Double) {
    let done = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var text: String?
    var failureCode: Int?
    let start = ProcessInfo.processInfo.systemUptime
    setup { result in
      lock.lock()
      switch result {
      case .success(let payload): text = payload.text
      case .failure(let error): failureCode = (error as NSError).code
      }
      lock.unlock()
      done.signal()
    }
    // A route that never answers must fail the test, not read as "no text".
    XCTAssertEqual(done.wait(timeout: .now() + 4), .success, "the turn must complete")
    lock.lock()
    defer { lock.unlock() }
    return (text, failureCode, ProcessInfo.processInfo.systemUptime - start)
  }

  func testLongTurnWithoutTimestampsWaitsPastTheGraceForALaterSegment() {
    let probe = LiveWriteProbe()
    var client: SarvamLiveClient?
    let result = awaitResult { completion in
      client = committedLongTurn(seconds: 41, probe: probe, completion: completion)
      client?.fixtureFinal("Segment one.", utterance: 0)
      // A later segment's final can trail by more than a short grace.
      waitInverted(0.4)
      client?.fixtureFinal("Segment two.", utterance: 1)
    }
    defer { client?.disconnect() }
    // No end_s means no confirmed coverage for a long turn, so the turn goes to REST.
    XCTAssertNil(result.text)
    XCTAssertEqual(result.failureCode, SarvamLiveClient.incompleteTranscriptError().code)
    XCTAssertGreaterThan(result.seconds, 2.0, "nothing settled at the short grace")
  }

  func testPartialsCannotSettleATimestampedTurnBeforeItsFinal() {
    let probe = LiveWriteProbe()
    var client: SarvamLiveClient?
    let result = awaitResult { completion in
      client = committedLongTurn(seconds: 3, probe: probe, completion: completion)
      client?.fixturePartial("Short", utterance: 0)
      // Past the partial quiet window (0.6 s) and the initial wait (0.9 s).
      waitInverted(1.0)
      client?.fixtureFinal("Short.", utterance: 0, endS: 3.0)
    }
    defer { client?.disconnect() }
    XCTAssertEqual(result.text, "Short.", "speculative partial text must not be pasted")
    XCTAssertEqual(client?.lastSettlePath, "server_final")
  }

  func testTerminalFinalBeforeSpeechEndIsAcknowledgedSettlesOnTheAcknowledgement() {
    let probe = LiveWriteProbe()
    let client = SarvamLiveClient(apiKey: "")
    defer { client.disconnect() }
    client.recoveryFixture(probe)
    client.recoveryReady()
    client.startNewTurn()
    client.recoveryDrain()
    probe.finish(0)
    client.recoveryDrain()
    let result = awaitResult { completion in
      client.fixtureStreamAndCommit(
        seconds: 3, probe: probe, acknowledgeSpeechEnd: false, completion: completion)
      // The server can answer before the send callback for speech_end runs.
      client.fixtureFinal("Done.", utterance: 0, endS: 3.0)
      probe.finish(probe.sent.count - 1)
      client.recoveryDrain()
    }
    XCTAssertEqual(result.text, "Done.")
    XCTAssertEqual(client.lastSettlePath, "server_final")
    XCTAssertLessThan(result.seconds, 1.0, "no wait for the 2.2 s timeout")
  }

  func testFinalizedUtterancesDoNotGrowAcrossTurns() {
    let client = SarvamLiveClient(apiKey: "")
    for index in 0..<50 {
      client.fixtureOpen()
      client.fixtureCompletion { _ in }
      client.fixtureFinal("Turn \(index).", utterance: index, endS: 0)
    }
    XCTAssertLessThanOrEqual(client.finalizedUtterances.count, 1)
    client.fixtureOpen()
    client.fixturePartial("stale", utterance: 3)
    client.fixtureFinal("stale", utterance: 49)
    XCTAssertEqual(client.fixtureText(), "", "events for settled utterances stay ignored")
  }

  func testTerminalFinalWaitsForAnEarlierSegmentFinalThatArrivesLater() {
    let probe = LiveWriteProbe()
    let lock = NSLock()
    var results: [String] = []
    let client = committedLongTurn(seconds: 41, probe: probe) { result in
      lock.lock()
      if case .success(let payload) = result { results.append(payload.text) }
      lock.unlock()
    }
    defer { client.disconnect() }
    // Segment 1 ends the turn, but segment 0's final has not arrived yet.
    client.fixtureFinal("Segment two.", utterance: 1, endS: 41.0)
    lock.lock()
    XCTAssertEqual(results, [], "the turn waits for every segment before the terminal one")
    lock.unlock()
    client.fixtureFinal("Segment one.", utterance: 0, endS: 20.0)
    lock.lock()
    XCTAssertEqual(results, ["Segment one. Segment two."])
    lock.unlock()
    XCTAssertEqual(client.lastSettlePath, "server_final")
  }

  func testMissingEarlierSegmentFailsTheLiveRouteAtTheTimeout() {
    let probe = LiveWriteProbe()
    let done = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var failure: NSError?
    let start = ProcessInfo.processInfo.systemUptime
    let client = committedLongTurn(seconds: 41, probe: probe) { result in
      lock.lock()
      if case .failure(let error) = result { failure = error as NSError }
      lock.unlock()
      done.signal()
    }
    defer { client.disconnect() }
    // Segment 0 only ever has a partial; segment 1's final ends the turn.
    client.fixturePartial("Segment one so far", utterance: 0)
    client.fixtureFinal("Segment two.", utterance: 1, endS: 41.0)
    XCTAssertEqual(done.wait(timeout: .now() + 4), .success)
    XCTAssertGreaterThan(
      ProcessInfo.processInfo.systemUptime - start, 2.0, "the 2.2 s backstop, not the final")
    lock.lock()
    XCTAssertEqual(failure?.code, SarvamLiveClient.incompleteTranscriptError().code)
    lock.unlock()
    XCTAssertEqual(client.lastSettlePath, "timeout")
  }

  /// Waits for the turn's result and returns its failure code, or nil for a success.
  private func timedOutFailureCode(
    seconds: Int, streamType: String, events: (SarvamLiveClient) -> Void
  ) -> (code: Int?, text: String?) {
    let probe = LiveWriteProbe()
    let done = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var code: Int?
    var text: String?
    let client = committedLongTurn(seconds: seconds, probe: probe, streamType: streamType) {
      result in
      lock.lock()
      switch result {
      case .success(let payload): text = payload.text
      case .failure(let error): code = (error as NSError).code
      }
      lock.unlock()
      done.signal()
    }
    defer { client.disconnect() }
    events(client)
    XCTAssertEqual(done.wait(timeout: .now() + 4), .success, "the 2.2 s ceiling settles the turn")
    lock.lock()
    defer { lock.unlock() }
    return (code, text)
  }

  func testStalledLongTurnFailsIntoRESTInEitherStreamType() {
    // Simulated sends no partials, so a 41 s turn whose first segment final (to 20 s) arrives
    // and then nothing more looks complete by every observed utterance. It is not.
    for streamType in ["fast", "simulated"] {
      let outcome = timedOutFailureCode(seconds: 41, streamType: streamType) { client in
        client.fixtureFinal("Segment one.", utterance: 0, endS: 20.0)
      }
      XCTAssertNil(outcome.text, "\(streamType): never paste a truncated transcript")
      XCTAssertEqual(
        outcome.code, SarvamLiveClient.incompleteTranscriptError().code, "\(streamType)")
    }
  }

  func testSilentTimeoutIsNotANoSpeechVerdict() {
    // No event at all is a stalled route, not the service saying the clip held no speech:
    // "no speech" would suppress REST for a real clip.
    for streamType in ["fast", "simulated"] {
      let outcome = timedOutFailureCode(seconds: 3, streamType: streamType) { _ in }
      XCTAssertEqual(
        outcome.code, SarvamLiveClient.incompleteTranscriptError().code, "\(streamType)")
    }
  }

  /// Lets `seconds` pass as an expectation that must not be fulfilled, instead of a sleep.
  private func waitInverted(_ seconds: Double) {
    let nothing = expectation(description: "time passes")
    nothing.isInverted = true
    wait(for: [nothing], timeout: seconds)
  }
}
