// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The REST transcription route: Sarvam's synchronous `POST /speech-to-text`, a multipart
/// upload of one WAV file. It backs up the live socket and is the only route when streaming
/// is off. The endpoint refuses audio past 30 seconds, so a longer recording is sent as
/// pieces (RestAudioPlan) and their transcripts are joined in order. The response carries no
/// usage counts, so this route reports none.
struct SarvamRestClient {
  static let requestTimeout = 15.0
  /// A 429 is retried once per piece, after its Retry-After (default `defaultRetryDelay`),
  /// but only when that wait is at most `maxRetryDelay`.
  static let defaultRetryDelay = 2.0
  static let maxRetryDelay = 8.0

  @discardableResult
  static func transcribe(
    pcmData: Data, apiKey: String, model: String,
    language: String = SpeechLanguage.automatic, keyterms: [String] = [],
    mode: TranscriptionMode = .standard,
    completion: @escaping (Result<(text: String, latencyMs: Double), Error>) -> Void
  ) -> CancellableRequest {
    let scope = CancellableRequest()
    let startTime = ProcessInfo.processInfo.systemUptime
    guard !apiKey.isEmpty else {
      completion(
        .failure(
          NSError(
            domain: "Stok", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Add a Sarvam API key in Stok Settings."])))
      return scope
    }
    let pieces = RestAudioPlan.pieces(of: pcmData)
    if pieces.count > 1 {
      Log.info("REST", "Recording sent as \(pieces.count) pieces of at most 30 seconds.")
    }
    let fields = Self.fields(model: model, mode: mode, language: language, keyterms: keyterms)
    let assembler = RestTranscriptAssembler(
      count: pieces.count,
      start: { index, done in
        let wav = WAVEncoder.encode(
          from: pcmData.subdata(in: pieces[index]), sampleRate: 16000, channels: 1)
        performPiece(
          wav: wav, apiKey: apiKey, fields: fields, isRetry: false, scope: scope.child(),
          completion: done)
      },
      completion: { result in
        guard !scope.isCancelled else { return }
        let elapsedMs = (ProcessInfo.processInfo.systemUptime - startTime) * 1000.0
        switch result {
        case .success(let text): completion(.success((text: text, latencyMs: elapsedMs)))
        case .failure(let error):
          // The turn has its answer; pieces still in flight are no longer needed.
          scope.cancel()
          completion(.failure(error))
        }
      })
    assembler.run()
    return scope
  }

  /// The form fields every piece of one recording carries.
  /// The form fields for one transcription: the mode's raw value, REST's spelling of the
  /// language (nil to detect), and keyterms only for saaras:v4, which alone accepts them.
  static func fields(
    model: String, mode: TranscriptionMode, language: String, keyterms: [String]
  ) -> Fields {
    Fields(
      model: model, mode: mode.rawValue, languageCode: SpeechLanguage.restCode(for: language),
      keyterms: model.hasPrefix("saaras:v4") ? keyterms : [])
  }

  struct Fields {
    let model: String
    let mode: String
    let languageCode: String?
    let keyterms: [String]
  }

  /// The multipart request for one WAV piece. The key goes only in the auth header.
  static func makeRequest(wav: Data, apiKey: String, fields: Fields, boundary: String)
    -> URLRequest
  {
    var request = URLRequest(url: SarvamAPI.speechToTextURL)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: SarvamAPI.authHeader)
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = requestTimeout
    var body = Data()
    func field(_ name: String, _ value: String) {
      body.append(Data("--\(boundary)\r\n".utf8))
      body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
      body.append(Data("\(value)\r\n".utf8))
    }
    field("model", fields.model)
    field("mode", fields.mode)
    // Omitted for detection: the endpoint picks the language itself.
    if let language = fields.languageCode { field("language_code", language) }
    if let keyterms = SarvamAPI.keytermsJSON(fields.keyterms) { field("keyterms", keyterms) }
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(
      Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
    body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
    body.append(wav)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    request.httpBody = body
    return request
  }

  /// Reads one piece's response. An empty transcript is a valid answer (silence); a body
  /// without the field is not.
  static func decodeTranscript(_ data: Data, status: Int) -> Result<String, Error> {
    guard (200...299).contains(status) else { return .failure(RESTResponse.error(code: status)) }
    do {
      let json = try RESTResponse.decode(data, status: status)
      guard let transcript = json["transcript"] as? String else {
        return .failure(RESTResponse.missingTranscriptError())
      }
      return .success(transcript)
    } catch {
      return .failure(error)
    }
  }

  private static func performPiece(
    wav: Data, apiKey: String, fields: Fields, isRetry: Bool, scope: CancellableRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    guard !scope.isCancelled else { return }
    let request = makeRequest(
      wav: wav, apiKey: apiKey, fields: fields, boundary: "StokBoundary-\(UUID().uuidString)")
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      scope.completedTask()
      guard !scope.isCancelled else { return }
      if let error {
        completion(.failure(error))
        return
      }
      let http = response as? HTTPURLResponse
      let status = http?.statusCode ?? -1
      // A per-minute throttle clears on its own: honor a short Retry-After once.
      if status == 429 {
        let delay =
          http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? defaultRetryDelay
        if !isRetry, delay <= maxRetryDelay {
          Log.warn(
            "REST", "429 rate limited - retrying once after \(String(format: "%.1f", delay))s.")
          scope.schedule(after: max(0, delay)) {
            performPiece(
              wav: wav, apiKey: apiKey, fields: fields, isRetry: true, scope: scope,
              completion: completion)
          }
          return
        }
      }
      completion(decodeTranscript(data ?? Data(), status: status))
    }
    scope.start(task)
  }
}
