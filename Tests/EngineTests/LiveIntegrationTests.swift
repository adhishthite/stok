// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import StokEngine

final class LiveIntegrationTests: XCTestCase {
  private func inputs() throws -> (EngineConfiguration, Data, URL) {
    guard ProcessInfo.processInfo.environment["STOK_LIVE_TESTS"] == "1" else {
      throw XCTSkip("Run the StokLiveChecks scheme to authorize real API calls.")
    }
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STOK_PROJECT_ROOT"]!)
    let content = try String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8)
    var values: [String: String] = [:]
    for line in content.components(separatedBy: .newlines) {
      let line = line.trimmingCharacters(in: .whitespaces)
      guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
      let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
      var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      if value.count >= 2,
        (value.hasPrefix("\"") && value.hasSuffix("\""))
          || (value.hasPrefix("'") && value.hasSuffix("'"))
      {
        value = String(value.dropFirst().dropLast())
      }
      values[key] = value
    }
    let config = EngineConfiguration.load(values: values)
    XCTAssertFalse(config.sarvamApiKey.isEmpty, "API key must be present")
    Log.configure(delegate: nil, apiKey: config.sarvamApiKey, privacyMode: true)
    let pcm = try Data(contentsOf: root.appendingPathComponent("build/fixtures/english.pcm"))
    XCTAssertGreaterThan(pcm.count, 32000)
    return (config, pcm, root)
  }

  func testThreeLiveTurns() throws {
    let (config, pcm, root) = try inputs()
    let client = SarvamLiveClient(
      apiKey: config.sarvamApiKey, model: config.liveModel,
      mode: config.transcriptionMode, language: config.language,
      keyterms: config.recognitionVocabulary)
    defer { client.disconnect() }
    client.connect()
    var rows: [[String: Any]] = []
    for repetition in 1...3 {
      let setupDeadline = ProcessInfo.processInfo.systemUptime + 15
      while !client.isReady, ProcessInfo.processInfo.systemUptime < setupDeadline {
        Thread.sleep(forTimeInterval: 0.02)
      }
      guard client.isReady else {
        XCTFail("Live handshake did not become ready within 15 seconds")
        return
      }
      client.startNewTurn()
      client.sendAudioChunk(Data(count: config.preRollMs * 32))
      let started = ProcessInfo.processInfo.systemUptime
      for offset in stride(from: 0, to: pcm.count, by: config.chunkMs * 32) {
        let end = min(pcm.count, offset + config.chunkMs * 32)
        let remaining = Double(end) / 32000 - (ProcessInfo.processInfo.systemUptime - started)
        if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        client.sendAudioChunk(pcm.subdata(in: offset..<end))
      }
      let released = ProcessInfo.processInfo.systemUptime
      if config.silenceFlushMs > 0 {
        client.sendAudioChunk(Data(count: config.silenceFlushMs * 32))
      }
      let done = DispatchSemaphore(value: 0)
      var row: [String: Any] = ["repetition": repetition]
      client.commitTurn { result in
        defer { done.signal() }
        let elapsed = (ProcessInfo.processInfo.systemUptime - released) * 1000
        row["audio_end_to_settle_ms"] = elapsed
        row["settle_path"] = client.lastSettlePath ?? "unknown"
        switch result {
        case .success(let payload):
          row["success"] = true
          let normalized = payload.text.lowercased().filter { $0.isLetter || $0.isWhitespace }
          XCTAssertEqual(normalized, "please send the revised architecture report by friday")
        case .failure(let error):
          row["success"] = false
          row["error_code"] = (error as NSError).code
          XCTFail("Live transcription failed with code \((error as NSError).code)")
        }
      }
      XCTAssertEqual(done.wait(timeout: .now() + 15), .success)
      rows.append(row)
      Thread.sleep(forTimeInterval: 0.3)
    }
    let data = try JSONSerialization.data(
      withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: root.appendingPathComponent("build/live-api-results.json"), options: .atomic)
  }

  func testRESTFallbackTranscribesSpeech() throws {
    let (config, pcm, _) = try inputs()
    let done = DispatchSemaphore(value: 0)
    let request = SarvamRestClient.transcribe(
      pcmData: pcm, apiKey: config.sarvamApiKey,
      model: config.restModel, language: config.language,
      mode: config.transcriptionMode
    ) { result in
      defer { done.signal() }
      switch result {
      case .success(let payload):
        XCTAssertEqual(
          payload.text.lowercased().filter { $0.isLetter || $0.isWhitespace },
          "please send the revised architecture report by friday")
      case .failure(let error):
        XCTFail("REST transcription failed with code \((error as NSError).code)")
      }
    }
    defer { request.cancel() }
    XCTAssertEqual(done.wait(timeout: .now() + 30), .success)
  }

  func testRESTFallbackTranscribesARecordingPastThirtySecondsInPieces() throws {
    let (config, pcm, _) = try inputs()
    // Ten repetitions with a 600 ms pause between them: about 40 seconds of audio, past the
    // REST endpoint's 30-second limit, so the client must split it.
    var long = Data()
    for _ in 0..<10 {
      long.append(pcm)
      long.append(Data(count: 600 * 32))
    }
    XCTAssertGreaterThan(Double(long.count) / 32_000, SarvamAPI.restMaxAudioSeconds)
    XCTAssertGreaterThan(RestAudioPlan.pieces(of: long).count, 1)
    let done = DispatchSemaphore(value: 0)
    let request = SarvamRestClient.transcribe(
      pcmData: long, apiKey: config.sarvamApiKey, model: config.restModel,
      language: config.language, mode: config.transcriptionMode
    ) { result in
      defer { done.signal() }
      switch result {
      case .success(let payload):
        let count = payload.text.lowercased().components(separatedBy: "architecture").count - 1
        XCTAssertGreaterThanOrEqual(count, 9, "every repetition is transcribed once")
        XCTAssertLessThanOrEqual(count, 10)
      case .failure(let error):
        XCTFail("Long REST transcription failed with code \((error as NSError).code)")
      }
    }
    defer { request.cancel() }
    XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
  }

  func testServiceProbeAcceptsTheKeyAndNamesABadOne() async throws {
    var (config, _, _) = try inputs()
    try await ServiceProbe.validate(configuration: config)
    config.sarvamApiKey = "stok-invalid-key-for-live-check"
    do {
      try await ServiceProbe.validate(configuration: config)
      XCTFail("A bogus key must not validate.")
    } catch {
      XCTAssertEqual(
        error.localizedDescription, "The API key was rejected. Check the key and try again.")
    }
  }

  func testRejectedKeyStopsTheLiveClientAfterThreeAttempts() throws {
    _ = try inputs()
    let client = SarvamLiveClient(apiKey: "stok-invalid-key-for-live-check")
    defer { client.shutdown() }
    let rejected = DispatchSemaphore(value: 0)
    client.onAuthRejected = { rejected.signal() }
    client.connect(reason: "startup")
    // Three attempts with 2 s and 4 s reconnect backoff between them.
    XCTAssertEqual(rejected.wait(timeout: .now() + 20), .success)
    XCTAssertFalse(client.isReady)
  }

  /// Paired check of stream_type on the real client: alternating fast and simulated turns on
  /// two open sessions. Gated separately because it streams about four minutes of audio:
  /// `TEST_RUNNER_STOK_PAIRED_CHECK=1` with the StokLiveChecks scheme. Writes
  /// build/stream-type-paired.json.
  func testPairedStreamTypes() throws {
    guard ProcessInfo.processInfo.environment["STOK_PAIRED_CHECK"] == "1" else {
      throw XCTSkip("Set TEST_RUNNER_STOK_PAIRED_CHECK=1 to run the paired stream_type check.")
    }
    let (config, pcm, root) = try inputs()
    let turnsPerArm = Int(ProcessInfo.processInfo.environment["STOK_PAIRED_TURNS"] ?? "") ?? 30
    var clients: [String: SarvamLiveClient] = [:]
    for arm in ["fast", "simulated"] {
      let client = SarvamLiveClient(
        apiKey: config.sarvamApiKey, model: config.liveModel, mode: config.transcriptionMode,
        language: config.language, keyterms: config.recognitionVocabulary, streamType: arm)
      client.connect()
      clients[arm] = client
    }
    defer { for client in clients.values { client.shutdown() } }
    var rows: [[String: Any]] = []
    for pair in 0..<turnsPerArm {
      let order = pair % 2 == 0 ? ["fast", "simulated"] : ["simulated", "fast"]
      for arm in order {
        let client = clients[arm]!
        let setupDeadline = ProcessInfo.processInfo.systemUptime + 15
        while !client.isReady, ProcessInfo.processInfo.systemUptime < setupDeadline {
          Thread.sleep(forTimeInterval: 0.02)
        }
        guard client.isReady else {
          XCTFail("\(arm) session did not become ready")
          return
        }
        client.startNewTurn()
        client.sendAudioChunk(Data(count: config.preRollMs * 32))
        let started = ProcessInfo.processInfo.systemUptime
        for offset in stride(from: 0, to: pcm.count, by: config.chunkMs * 32) {
          let end = min(pcm.count, offset + config.chunkMs * 32)
          let remaining = Double(end) / 32000 - (ProcessInfo.processInfo.systemUptime - started)
          if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
          client.sendAudioChunk(pcm.subdata(in: offset..<end))
        }
        let released = ProcessInfo.processInfo.systemUptime
        if config.silenceFlushMs > 0 {
          client.sendAudioChunk(Data(count: config.silenceFlushMs * 32))
        }
        // The engine makes the early-hedge decision at this point, from the same signal.
        let held = Double(config.preRollMs * 32 + pcm.count) / 32_000
        let hedge = DictationEngine.shouldHedgeEarly(
          duration: held, liveSignalAgeSeconds: client.liveSignalAgeSeconds)
        let done = DispatchSemaphore(value: 0)
        var row: [String: Any] = ["arm": arm, "pair": pair, "hedge": hedge, "held_s": held]
        client.commitTurn { result in
          defer { done.signal() }
          row["audio_end_to_settle_ms"] = (ProcessInfo.processInfo.systemUptime - released) * 1000
          row["settle_path"] = client.lastSettlePath ?? "unknown"
          if case .success(let payload) = result {
            row["success"] = true
            row["exact"] =
              payload.text.lowercased().filter { $0.isLetter || $0.isWhitespace }
              == "please send the revised architecture report by friday"
          } else {
            row["success"] = false
          }
        }
        XCTAssertEqual(done.wait(timeout: .now() + 15), .success)
        rows.append(row)
        Thread.sleep(forTimeInterval: 0.3)
      }
    }
    let data = try JSONSerialization.data(
      withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
    try data.write(
      to: root.appendingPathComponent("build/stream-type-paired.json"), options: .atomic)
    XCTAssertTrue(rows.allSatisfy { ($0["hedge"] as? Bool) == false }, "no hedge on healthy turns")
  }
}
