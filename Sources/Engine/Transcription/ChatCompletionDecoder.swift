// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import CoreFoundation
import Foundation

/// One bounded reader for OpenAI-compatible chat completion envelopes from
/// `/v1/chat/completions`, shared by post-processing and vocabulary analysis. Sarvam models
/// reason before answering, and when reasoning uses the whole `max_tokens` budget the
/// answer arrives as `content: null` with `finish_reason: "length"`. That case, and any
/// other incomplete answer, must never pass as text.
enum ChatCompletionDecoder {
  enum Outcome: Equatable {
    /// The first choice's complete `content`.
    case text(String)
    /// A finished answer with no content.
    case empty
    /// The service withheld the answer. `reason` is its own finish reason.
    case blocked(reason: String)
    /// The answer stopped early, so any text on hand is incomplete and must not be used.
    case truncated
    /// No choices: not an envelope we can read.
    case malformed
  }

  /// Raw usage counts, each nil when absent. `completionTokens` already includes
  /// `reasoningTokens`; the two are recorded as reported, never added together.
  struct Usage: Equatable {
    var promptTokens: Int?
    var completionTokens: Int?
    var reasoningTokens: Int?
  }

  static func decode(_ json: [String: Any]) -> Outcome {
    guard let choice = (json["choices"] as? [[String: Any]])?.first else { return .malformed }
    let message = choice["message"] as? [String: Any]
    let text = (message?["content"] as? String) ?? ""
    let finishReason = (choice["finish_reason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    switch finishReason {
    case "stop":
      return text.isEmpty ? .empty : .text(text)
    case "length":
      return .truncated
    case "content_filter":
      return .blocked(reason: "content_filter")
    case nil:
      // Non-streaming calls always state a reason. No reason means the envelope is
      // incomplete, so its text must not be used.
      return text.isEmpty ? .malformed : .truncated
    default:
      // Any other stated reason (a tool call, for one) is a stop we do not model.
      return text.isEmpty ? .empty : .truncated
    }
  }

  static func usage(_ json: [String: Any]) -> Usage {
    guard let usage = json["usage"] as? [String: Any] else { return Usage() }
    let details = usage["completion_tokens_details"] as? [String: Any]
    return Usage(
      promptTokens: count(usage["prompt_tokens"]),
      completionTokens: count(usage["completion_tokens"]),
      reasoningTokens: count(details?["reasoning_tokens"]))
  }

  /// A non-negative integer count, or nil for anything else (including a JSON boolean,
  /// which Foundation also bridges to NSNumber).
  private static func count(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      let value = Int(exactly: number.doubleValue), value >= 0
    else { return nil }
    return value
  }
}
