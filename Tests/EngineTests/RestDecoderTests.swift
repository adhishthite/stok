// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import StokEngine

final class RestDecoderTests: XCTestCase {
  private func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }

  func testMultipartRequestCarriesTheDocumentedFieldsAndTheKeyOnlyInTheHeader() throws {
    let wav = WAVEncoder.encode(from: Data([1, 0, 2, 0]), sampleRate: 16000, channels: 1)
    let request = SarvamRestClient.makeRequest(
      wav: wav, apiKey: "fixture-key",
      fields: SarvamRestClient.Fields(
        model: "saaras:v4", mode: "transcribe", languageCode: "hi-IN",
        keyterms: ["Kubernetes", "New Delhi"]),
      boundary: "B")
    XCTAssertEqual(request.url?.absoluteString, "https://api.sarvam.ai/speech-to-text")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "api-subscription-key"), "fixture-key")
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=B")
    let body = try XCTUnwrap(request.httpBody)
    let text = String(decoding: body, as: UTF8.self)
    for part in [
      "--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nsaaras:v4\r\n",
      "--B\r\nContent-Disposition: form-data; name=\"mode\"\r\n\r\ntranscribe\r\n",
      "--B\r\nContent-Disposition: form-data; name=\"language_code\"\r\n\r\nhi-IN\r\n",
      "--B\r\nContent-Disposition: form-data; name=\"keyterms\"\r\n\r\n[\"Kubernetes\",\"New Delhi\"]\r\n",
      "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF",
    ] {
      XCTAssertTrue(text.contains(part), part)
    }
    XCTAssertTrue(text.hasSuffix("\r\n--B--\r\n"))
    XCTAssertFalse(text.contains("fixture-key"))
  }

  func testDetectionAndEmptyVocabularyOmitTheirFields() {
    let request = SarvamRestClient.makeRequest(
      wav: Data(), apiKey: "k",
      fields: SarvamRestClient.Fields(
        model: "saaras:v4", mode: "verbatim", languageCode: nil, keyterms: []),
      boundary: "B")
    let text = String(decoding: request.httpBody!, as: UTF8.self)
    XCTAssertFalse(text.contains("language_code"))
    XCTAssertFalse(text.contains("keyterms"))
    XCTAssertNil(SpeechLanguage.restCode(for: "auto"))
    XCTAssertEqual(SpeechLanguage.restCode(for: "mr-IN"), "mr-IN")
  }

  /// The multipart body the REST client builds carries the chosen mode and the REST
  /// spelling of the language. Verified live 2026-10-07: REST accepts only od-IN for Odia.
  func testRequestCarriesTheModeAndTheRESTLanguageSpelling() throws {
    for mode in TranscriptionMode.allCases {
      XCTAssertEqual(
        SarvamRestClient.fields(model: "saaras:v4", mode: mode, language: "auto", keyterms: [])
          .mode, mode.rawValue)
    }
    let fields = SarvamRestClient.fields(
      model: "saaras:v4", mode: .translate, language: "or-IN", keyterms: ["Stok"])
    let request = SarvamRestClient.makeRequest(
      wav: Data(), apiKey: "k", fields: fields, boundary: "B")
    let text = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
    XCTAssertTrue(text.contains("name=\"mode\"\r\n\r\ntranslate\r\n"))
    XCTAssertTrue(text.contains("name=\"language_code\"\r\n\r\nod-IN\r\n"))
    XCTAssertFalse(text.contains("or-IN"))
  }

  func testTranscriptDecodingSeparatesSilenceFromFailure() {
    let ok = SarvamRestClient.decodeTranscript(
      json(["request_id": "r", "transcript": "Hello.", "language_code": "en-IN"]), status: 200)
    XCTAssertEqual(try? ok.get(), "Hello.")
    // Verified: 100 ms of silence returns 200 with an empty transcript.
    let silence = SarvamRestClient.decodeTranscript(
      json(["request_id": "r", "transcript": "", "language_code": "en-IN"]), status: 200)
    XCTAssertEqual(try? silence.get(), "")
    let missing = SarvamRestClient.decodeTranscript(json(["request_id": "r"]), status: 200)
    XCTAssertThrowsError(try missing.get()) { XCTAssertEqual(($0 as NSError).code, -6) }
    // Verified: a bad key is 403 with invalid_api_key_error; audio past 30 s is 400.
    let rejected = SarvamRestClient.decodeTranscript(
      json(["error": ["message": "Private", "code": "invalid_api_key_error"]]), status: 403)
    XCTAssertThrowsError(try rejected.get()) {
      XCTAssertEqual(($0 as NSError).code, 403)
      XCTAssertEqual(($0 as NSError).domain, "SarvamAPI")
      XCTAssertFalse($0.localizedDescription.contains("Private"))
    }
  }

  func testShortRecordingIsOnePiece() {
    let pcm = Data(count: 10 * RestAudioPlan.bytesPerSecond)
    XCTAssertEqual(RestAudioPlan.pieces(of: pcm), [0..<pcm.count])
    XCTAssertEqual(RestAudioPlan.pieces(of: Data()), [])
  }

  func testLongRecordingIsCutUnderThirtySecondsAtTheQuietestFrame() {
    // 70 s of loud audio with a 250 ms pause at 25 s and another at 51 s.
    let seconds = 70
    var samples = [Int16](repeating: 8000, count: seconds * 16000)
    for start in [25 * 16000, 51 * 16000] {
      for index in start..<(start + 4000) { samples[index] = 0 }
    }
    let pcm = samples.withUnsafeBufferPointer { Data(buffer: $0) }
    let pieces = RestAudioPlan.pieces(of: pcm)
    XCTAssertEqual(pieces.count, 3)
    XCTAssertEqual(pieces.first?.lowerBound, 0)
    XCTAssertEqual(pieces.last?.upperBound, pcm.count)
    for (index, piece) in pieces.enumerated() {
      XCTAssertLessThanOrEqual(
        Double(piece.count) / Double(RestAudioPlan.bytesPerSecond), RestAudioPlan.maxPieceSeconds)
      XCTAssertEqual(piece.lowerBound % 2, 0, "pieces start on a sample boundary")
      if index > 0 { XCTAssertEqual(piece.lowerBound, pieces[index - 1].upperBound) }
    }
    // Each cut lands inside a pause, not in speech.
    XCTAssertTrue((25 * 32_000..<(25 * 32_000 + 8000)).contains(pieces[0].upperBound))
    XCTAssertTrue((51 * 32_000..<(51 * 32_000 + 8000)).contains(pieces[1].upperBound))
  }

  func testAssemblerJoinsPiecesInOrderWhateverOrderTheyFinish() {
    var pending: [(Int, (Result<String, Error>) -> Void)] = []
    var result: Result<String, Error>?
    let assembler = RestTranscriptAssembler(
      count: 6, start: { index, done in pending.append((index, done)) },
      completion: { result = $0 })
    assembler.run()
    XCTAssertEqual(
      pending.map(\.0), Array(0..<RestTranscriptAssembler.maxConcurrent),
      "concurrency is bounded")
    let texts = ["one", "two", "", "four", "five", "six"]
    while let next = pending.popLast() {
      next.1(.success(texts[next.0]))
    }
    XCTAssertEqual(try? result?.get(), "one two four five six")
  }

  func testAssemblerFailsOnceOnTheFirstFailure() {
    var pending: [(Int, (Result<String, Error>) -> Void)] = []
    var completions = 0
    var failure: NSError?
    let assembler = RestTranscriptAssembler(
      count: 3, start: { index, done in pending.append((index, done)) },
      completion: { result in
        completions += 1
        if case .failure(let error) = result { failure = error as NSError }
      })
    assembler.run()
    pending[1].1(.failure(RESTResponse.error(code: 429)))
    pending[0].1(.success("late"))
    pending[2].1(.failure(RESTResponse.error(code: 500)))
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(failure?.code, 429)
  }

  func testCancellingTheParentCancelsEveryPiece() {
    let parent = CancellableRequest()
    let first = parent.child()
    parent.cancel()
    XCTAssertTrue(first.isCancelled)
    XCTAssertTrue(parent.child().isCancelled, "a piece started after cancel never runs")
  }

  func testChatFinishReasonsMapToDistinctOutcomes() {
    func choice(_ content: Any, _ reason: Any) -> [String: Any] {
      [
        "choices": [
          ["message": ["role": "assistant", "content": content], "finish_reason": reason]
        ]
      ]
    }
    XCTAssertEqual(ChatCompletionDecoder.decode(choice("hello", "stop")), .text("hello"))
    XCTAssertEqual(ChatCompletionDecoder.decode(choice("", "stop")), .empty)
    // Verified: reasoning can use the whole max_tokens budget, leaving content null.
    XCTAssertEqual(ChatCompletionDecoder.decode(choice(NSNull(), "length")), .truncated)
    XCTAssertEqual(ChatCompletionDecoder.decode(choice("partial", "length")), .truncated)
    XCTAssertEqual(
      ChatCompletionDecoder.decode(choice("x", "content_filter")),
      .blocked(reason: "content_filter"))
    XCTAssertEqual(ChatCompletionDecoder.decode(choice("x", NSNull())), .truncated)
    XCTAssertEqual(ChatCompletionDecoder.decode(choice(NSNull(), NSNull())), .malformed)
    XCTAssertEqual(ChatCompletionDecoder.decode(choice("x", "tool_calls")), .truncated)
    XCTAssertEqual(ChatCompletionDecoder.decode(["usage": [:]]), .malformed)
  }

  func testChatUsageIsReadRawAndNeverSummed() {
    let usage = ChatCompletionDecoder.usage([
      "usage": [
        "prompt_tokens": 61, "completion_tokens": 20, "total_tokens": 81,
        "completion_tokens_details": ["reasoning_tokens": 19],
      ]
    ])
    XCTAssertEqual(
      usage,
      ChatCompletionDecoder.Usage(promptTokens: 61, completionTokens: 20, reasoningTokens: 19))
    let absent = ChatCompletionDecoder.usage([
      "usage": [
        "prompt_tokens": true, "completion_tokens": -1, "completion_tokens_details": NSNull(),
      ]
    ])
    XCTAssertEqual(absent, ChatCompletionDecoder.Usage())
  }
}
