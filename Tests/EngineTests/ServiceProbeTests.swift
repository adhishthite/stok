// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import StokEngine

final class ServiceProbeTests: XCTestCase {
  func testEmptyKeyFailsBeforeAnyRequest() async {
    var configuration = EngineConfiguration()
    configuration.sarvamApiKey = ""
    do {
      try await ServiceProbe.validate(configuration: configuration)
      XCTFail("An empty key must not validate.")
    } catch {
      XCTAssertEqual((error as NSError).code, 1)
      XCTAssertEqual(error.localizedDescription, "Enter an API key first.")
    }
  }

  func testStatusMessagesSeparateKeyProblemsFromServiceProblems() {
    XCTAssertNil(ServiceProbe.message(forStatus: 200))
    for status in [401, 403] {
      XCTAssertEqual(
        ServiceProbe.message(forStatus: status),
        "The API key was rejected. Check the key and try again.")
    }
    XCTAssertEqual(ServiceProbe.message(forStatus: 429), "Rate limited. Try again in a minute.")
    XCTAssertEqual(ServiceProbe.message(forStatus: 503), "Sarvam is unavailable right now.")
    XCTAssertEqual(
      ServiceProbe.message(forStatus: 302), "Sarvam could not verify the key. Try again.")
  }

  func testTransportFailuresNeverAccuseTheKey() {
    XCTAssertEqual(
      ServiceProbe.message(for: URLError(.notConnectedToInternet)), "No network connection.")
    XCTAssertEqual(
      ServiceProbe.message(for: URLError(.cannotFindHost)), "No network connection.")
    XCTAssertEqual(
      ServiceProbe.message(for: URLError(.timedOut)), "Sarvam did not respond in time. Try again.")
  }

  func testRestProbeNamesTheModelForA400AndTheKeyForA403() {
    // Verified 2026-10-07: an unknown model is 400; a bad key is 403.
    XCTAssertEqual(
      ServiceProbe.message(forModel: "saaras:v9", status: 400),
      "The model \"saaras:v9\" is not available for this key.")
    XCTAssertEqual(
      ServiceProbe.message(forModel: "saaras:v4", status: 403),
      "The API key was rejected. Check the key and try again.")
    XCTAssertNil(ServiceProbe.message(forModel: "ok", status: 200))
    // A rate limit on the model call is still a service problem, not a model problem.
    XCTAssertEqual(
      ServiceProbe.message(forModel: "ok", status: 429), "Rate limited. Try again in a minute.")
    XCTAssertEqual(ServiceProbe.probeAudioBytes, 3_200, "100 ms of 16 kHz silence")
    XCTAssertEqual(ServiceProbe.timeoutSeconds, 10)
  }

  func testLiveProbeReadsTheFirstDecisiveEvent() {
    func outcome(_ value: [String: Any]) -> ServiceProbe.LiveOutcome? {
      ServiceProbe.liveOutcome(from: try! JSONSerialization.data(withJSONObject: value))
    }
    XCTAssertEqual(outcome(["event": "session.begin", "request_id": "r"]), .began)
    XCTAssertNil(outcome(["event": "pong"]))
    XCTAssertEqual(
      outcome(["event": "error", "code": "invalid_subscription_key", "status_code": 401]),
      .error(code: "invalid_subscription_key", statusCode: 401))
    XCTAssertNil(ServiceProbe.message(forLive: .began, model: "saaras:v4"))
    XCTAssertEqual(
      ServiceProbe.message(
        forLive: .error(code: "invalid_subscription_key", statusCode: 401), model: "saaras:v4"),
      "The API key was rejected. Check the key and try again.")
    // Verified: a rejected parameter is an invalid_request error with status 400.
    XCTAssertEqual(
      ServiceProbe.message(
        forLive: .error(code: "invalid_request", statusCode: 400), model: "saaras:v9"),
      "The live model \"saaras:v9\" or the language setting was rejected.")
    XCTAssertEqual(
      ServiceProbe.message(forLive: .error(code: "rate_limit", statusCode: 429), model: "m"),
      "Rate limited. Try again in a minute.")
  }

  func testTimeoutClosesASocketThatNeverAnswers() async {
    let socket = HangingSocket()
    // Releases the socket after 3 s so a regression fails this test instead of hanging it.
    let watchdog = Task {
      try await Task.sleep(nanoseconds: 3_000_000_000)
      socket.cancel()
    }
    defer { watchdog.cancel() }
    let start = ProcessInfo.processInfo.systemUptime
    do {
      _ = try await ServiceProbe.firstOutcome(
        timeout: 0.2, receive: { try await socket.receive() }, cancelSocket: { socket.cancel() })
      XCTFail("A silent socket must time out.")
    } catch {
      XCTAssertEqual((error as? URLError)?.code, .timedOut)
    }
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1.5)
  }

  func testCancellingTheProbeClosesASocketThatNeverAnswers() async {
    let socket = HangingSocket()
    let watchdog = Task {
      try await Task.sleep(nanoseconds: 3_000_000_000)
      socket.cancel()
    }
    defer { watchdog.cancel() }
    let start = ProcessInfo.processInfo.systemUptime
    let probe = Task {
      try await ServiceProbe.firstOutcome(
        timeout: 30, receive: { try await socket.receive() }, cancelSocket: { socket.cancel() })
    }
    try? await Task.sleep(nanoseconds: 100_000_000)
    probe.cancel()
    _ = try? await probe.value
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1.5)
  }

  func testTimeoutWinsEvenWhenTheClosedSocketAnswersFirst() async {
    let socket = HangingSocket()
    // Closing wakes the pending receive, which fails before the timeout path continues.
    socket.cancelHoldSeconds = 0.05
    do {
      _ = try await ServiceProbe.firstOutcome(
        timeout: 0.1, receive: { try await socket.receive() }, cancelSocket: { socket.cancel() })
      XCTFail("A silent socket must time out.")
    } catch {
      XCTAssertEqual((error as? URLError)?.code, .timedOut, "\(error)")
    }
  }
}
