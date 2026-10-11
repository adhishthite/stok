// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Error values for the REST transcription route. Descriptions are written here, never
/// copied from a response body, so no server text reaches the HUD or the log.
enum RESTResponse {
  static let domain = "SarvamAPI"

  /// Reads a Sarvam JSON body. An `error` envelope becomes a named failure for `status`.
  static func decode(_ data: Data, status: Int = 200) throws -> [String: Any] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw NSError(
        domain: domain, code: -5,
        userInfo: [
          NSLocalizedDescriptionKey: "Sarvam returned an unreadable response. Try again."
        ])
    }
    if json["error"] is [String: Any] {
      throw error(code: (200...299).contains(status) ? -1 : status)
    }
    return json
  }

  /// The response carried no transcript field, so there is nothing that could be pasted.
  static func missingTranscriptError() -> NSError {
    NSError(
      domain: domain, code: -6,
      userInfo: [NSLocalizedDescriptionKey: "Sarvam returned no transcript. Nothing pasted."])
  }

  static func error(code: Int) -> NSError {
    let message: String
    switch code {
    case 400: message = "Sarvam rejected the request. Check the model in Stok Settings."
    case 401, 403: message = "API key rejected. Review the Sarvam connection in Stok Settings."
    case 404: message = "Model unavailable. Review the model in Stok Settings."
    case 422: message = "Sarvam could not read the recording. Nothing pasted."
    case 429: message = "Too many requests. Try again shortly."
    case 500...599: message = "Sarvam is temporarily unavailable. Try again."
    default: message = "Sarvam could not finish this request. Try again."
    }
    return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
