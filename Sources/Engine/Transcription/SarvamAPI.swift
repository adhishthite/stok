// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Endpoints, the auth header, and documented request limits for the Sarvam API. Every
/// network call Stok makes for transcription, cleanup, or vocabulary analysis goes to one of
/// these URLs with the key in `authHeader`.
public enum SarvamAPI {
  /// Sarvam authenticates with this header, not `Authorization: Bearer`. Verified
  /// 2026-10-07: the realtime socket refuses a key passed as a query parameter.
  static let authHeader = "api-subscription-key"
  static let host = "api.sarvam.ai"
  static let realtimeURL = URL(string: "wss://api.sarvam.ai/speech-to-text-realtime/ws")!
  static let speechToTextURL = URL(string: "https://api.sarvam.ai/speech-to-text")!
  static let chatCompletionsURL = URL(string: "https://api.sarvam.ai/v1/chat/completions")!

  /// Keyterm prompting limits (saaras:v4): at most 50 terms of at most 64 characters each.
  /// The service rejects a request past either limit, so the client trims before sending.
  public static let maxKeyterms = 50
  public static let maxKeytermLength = 64

  /// 16 kHz mono 16-bit PCM, the only audio format Stok sends.
  static let pcmBytesPerSecond = 32_000

  /// The realtime `stream_type` for a configuration. "fast" streams partials for the live
  /// overlay. "simulated" sends finals only and settled the terminal final 66 ms sooner at the
  /// median in a paired check (n=150), with accuracy unchanged, so it is used whenever no
  /// words would be shown: live words off, or dictated words hidden on screen.
  public static func streamType(liveWords: Bool, privacyMode: Bool) -> String {
    liveWords && !privacyMode ? "fast" : "simulated"
  }

  /// The realtime endpointing mode Stok always uses: the shortcut marks speech start and end.
  static let endpointing = "manual"

  /// The synchronous REST endpoint refuses audio longer than 30 seconds.
  static let restMaxAudioSeconds = 30.0

  /// The realtime socket closes after 60 seconds without audio or a ping.
  static let realtimeInactivitySeconds = 60.0

  /// The terms a recognition request may carry: non-empty, within the length limit, unique
  /// ignoring case, and at most `maxKeyterms`, in the order given. A term past the length
  /// limit is left out rather than cut, because a truncated term biases toward a wrong word.
  public static func keyterms(from vocabulary: [String]) -> [String] {
    var seen = Set<String>()
    var terms: [String] = []
    for raw in vocabulary {
      let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !term.isEmpty, term.count <= maxKeytermLength, seen.insert(term.lowercased()).inserted
      else { continue }
      terms.append(term)
      if terms.count == maxKeyterms { break }
    }
    return terms
  }

  /// The JSON array the `keyterms` field and query parameter carry, or nil for no terms.
  static func keytermsJSON(_ terms: [String]) -> String? {
    guard !terms.isEmpty, let data = try? JSONSerialization.data(withJSONObject: terms) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  // Language codes per endpoint come from SpeechLanguage (the realtime socket takes `or-IN`
  // or `auto`; REST takes `od-IN` and omits the field to detect). The `mode` field is
  // TranscriptionMode's raw value on both endpoints.
}
