// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ServiceProbe {
  /// Sarvam has no free key-check endpoint, so the probe makes the two smallest calls the
  /// engine itself depends on: a REST transcription of 100 ms of silence (bills 0.1 s of audio
  /// and checks the key and the fallback model), then, when streaming is on, a realtime
  /// session that is closed as soon as it begins (no audio, nothing billed). A success is the
  /// same access a dictation needs, and each failure names the part that failed.
  static let timeoutSeconds = 10.0
  /// 100 ms of 16 kHz silence, the smallest clip the REST endpoint transcribes.
  static let probeAudioBytes = 3_200

  public static func validate(configuration: EngineConfiguration) async throws {
    guard !configuration.sarvamApiKey.isEmpty else {
      throw NSError(
        domain: "Stok.Setup", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Enter an API key first."])
    }
    // Key and fallback model first, so a bad key is reported as a bad key.
    let restStatus = try await restStatus(configuration: configuration)
    if let problem = message(forModel: configuration.restModel, status: restStatus) {
      throw failure(code: restStatus, message: problem)
    }
    // A REST-only configuration never opens a live session, so its live model is not checked.
    guard configuration.enableLiveWebSocket else { return }
    let outcome = try await liveOutcome(configuration: configuration)
    if let problem = message(forLive: outcome, model: configuration.liveModel) {
      throw failure(code: 6, message: problem)
    }
  }

  /// What the realtime socket said first: the session began, or it sent an error event.
  enum LiveOutcome: Equatable {
    case began
    case error(code: String, statusCode: Int?)
  }

  private static func restStatus(configuration: EngineConfiguration) async throws -> Int {
    let wav = WAVEncoder.encode(
      from: Data(count: probeAudioBytes), sampleRate: 16000, channels: 1)
    var request = SarvamRestClient.makeRequest(
      wav: wav, apiKey: configuration.sarvamApiKey,
      fields: SarvamRestClient.Fields(
        model: configuration.restModel, mode: "transcribe", languageCode: nil, keyterms: []),
      boundary: "StokProbe-\(UUID().uuidString)")
    request.timeoutInterval = timeoutSeconds
    // A cached answer from an earlier key would validate a key that was never sent.
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    let response: URLResponse
    do {
      (_, response) = try await URLSession.shared.data(for: request)
    } catch let error as URLError {
      try Task.checkCancellation()
      throw failure(code: 3, message: message(for: error))
    }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else {
      throw failure(code: 4, message: "Sarvam is unavailable right now.")
    }
    return http.statusCode
  }

  private static func liveOutcome(configuration: EngineConfiguration) async throws -> LiveOutcome {
    guard
      let url = SarvamLiveClient.sessionURL(
        model: configuration.liveModel, mode: configuration.transcriptionMode,
        language: configuration.language, keyterms: [], streamType: configuration.liveStreamType)
    else { throw failure(code: 5, message: "The live model name is not valid.") }
    var request = URLRequest(url: url)
    request.timeoutInterval = timeoutSeconds
    request.setValue(configuration.sarvamApiKey, forHTTPHeaderField: SarvamAPI.authHeader)
    let session = URLSession(configuration: .ephemeral)
    let task = session.webSocketTask(with: request)
    defer { session.invalidateAndCancel() }
    task.resume()
    do {
      return try await firstOutcome(
        timeout: timeoutSeconds,
        receive: {
          switch try await task.receive() {
          case .string(let text): return Data(text.utf8)
          case .data(let bytes): return bytes
          @unknown default: return Data()
          }
        },
        cancelSocket: { task.cancel(with: .normalClosure, reason: nil) })
    } catch let error as URLError {
      try Task.checkCancellation()
      throw failure(code: 3, message: message(for: error))
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // The socket closed without an event. Treat it as a transport problem.
      throw failure(code: 3, message: "Sarvam closed the live connection. Try again.")
    }
  }

  /// Reads messages until one decides the outcome, or throws URLError(.timedOut) after
  /// `timeout`. URLSessionWebSocketTask.receive() ignores task cancellation, and a task group
  /// waits for every child before it returns, so the socket itself is closed the moment the
  /// wait ends: on timeout, on cancellation of the caller, and on any answer. Closing makes
  /// the pending receive fail, which lets the group finish.
  static func firstOutcome(
    timeout: Double, receive: @escaping @Sendable () async throws -> Data,
    cancelSocket: @escaping @Sendable () -> Void
  ) async throws -> LiveOutcome {
    // The timeout is recorded before the socket is closed: closing wakes the pending receive,
    // whose cancellation error can reach the group first, and must not be mistaken for a
    // network failure.
    let timedOut = ProbeFlag()
    defer { cancelSocket() }
    do {
      return try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(of: LiveOutcome.self) { group in
          group.addTask {
            while true {
              if let outcome = liveOutcome(from: try await receive()) { return outcome }
            }
          }
          group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            timedOut.set()
            cancelSocket()
            throw URLError(.timedOut)
          }
          defer { cancelSocket() }
          let first = try await group.next()!
          group.cancelAll()
          return first
        }
      } onCancel: {
        cancelSocket()
      }
    } catch {
      if timedOut.isSet { throw URLError(.timedOut) }
      throw error
    }
  }

  /// The outcome one server message decides, or nil for a message that decides nothing.
  static func liveOutcome(from data: Data) -> LiveOutcome? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let event = json["event"] as? String
    else { return nil }
    switch event {
    case "session.begin": return .began
    case "error":
      return .error(
        code: (json["code"] as? String) ?? "unknown", statusCode: json["status_code"] as? Int)
    default: return nil
    }
  }

  /// nil means the live session began. A key error names the key; a rejected parameter
  /// names the live model and languages, the two settings that reach the socket.
  static func message(forLive outcome: LiveOutcome, model: String) -> String? {
    switch outcome {
    case .began: return nil
    case .error(let code, let statusCode):
      if SarvamLiveClient.errorIndicatesKeyRejection(code: code, statusCode: statusCode) {
        return "The API key was rejected. Check the key and try again."
      }
      if statusCode == 429 { return "Rate limited. Try again in a minute." }
      if let statusCode, (400...499).contains(statusCode) {
        return "The live model \"\(model)\" or the language setting was rejected."
      }
      return "Sarvam is unavailable right now."
    }
  }

  /// nil means the key works and the model exists. A 400 from the transcription call names
  /// the model, because a bad key comes back as 401 or 403.
  static func message(forModel model: String, status: Int) -> String? {
    switch status {
    case 200...299: return nil
    case 400, 404, 422: return "The model \"\(model)\" is not available for this key."
    default: return message(forStatus: status)
    }
  }

  /// nil means the key works. Every other status maps to one short, actionable line.
  static func message(forStatus status: Int) -> String? {
    switch status {
    case 200...299: return nil
    case 401, 403: return "The API key was rejected. Check the key and try again."
    case 429: return "Rate limited. Try again in a minute."
    case 500...599: return "Sarvam is unavailable right now."
    default: return "Sarvam could not verify the key. Try again."
    }
  }

  /// Transport failures are a local network problem far more often than a key problem, so
  /// they never accuse the key.
  static func message(for error: URLError) -> String {
    switch error.code {
    case .timedOut: return "Sarvam did not respond in time. Try again."
    default: return "No network connection."
    }
  }

  private static func failure(code: Int, message: String) -> NSError {
    NSError(domain: "Stok.Setup", code: code, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
