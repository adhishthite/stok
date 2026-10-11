// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

/// What recognition requests actually carry from a vocabulary, and why any term is left
/// out. Mirrors `SarvamAPI.keyterms`: terms are trimmed, deduplicated ignoring case, at
/// most `SarvamAPI.maxKeytermLength` characters, and at most `SarvamAPI.maxKeyterms`.
public struct KeytermReport: Equatable, Sendable {
  /// Sent with every dictation, in order.
  public let sent: [String]
  /// Longer than the per-term limit. Never cut, because a cut term biases toward a wrong word.
  public let tooLong: [String]
  /// Within the length limit but past the term limit.
  public let overLimit: [String]
  /// Models in use that do not accept keyterms at all.
  public let modelsWithoutKeyterms: [String]

  public init(vocabulary: [String], liveModel: String, restModel: String) {
    sent = SarvamAPI.keyterms(from: vocabulary)
    var seen = Set(sent.map { $0.lowercased() })
    var long: [String] = []
    var over: [String] = []
    for raw in vocabulary {
      let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { continue }
      if term.count > SarvamAPI.maxKeytermLength { long.append(term) } else { over.append(term) }
    }
    tooLong = long
    overLimit = over
    modelsWithoutKeyterms = [liveModel, restModel].filter { !$0.hasPrefix("saaras:v4") }
  }

  public init(configuration: EngineConfiguration) {
    self.init(
      vocabulary: configuration.customVocabulary, liveModel: configuration.liveModel,
      restModel: configuration.restModel)
  }
}
