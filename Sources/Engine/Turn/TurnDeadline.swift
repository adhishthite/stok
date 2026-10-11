// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

enum TurnDeadline {
  /// Seconds a committed turn may take before both routes are abandoned: the fallback delay
  /// (the REST hedge can start that late), then `secondsPerWave` for every wave of REST pieces (a recording past 30 seconds goes out as pieces,
  /// `RestTranscriptAssembler.maxConcurrent` at a time), then a small margin. Never less
  /// than the 10-second floor a short turn always had.
  static func budget(fallbackTimeout: Double, audioBytes: Int = 0) -> Double {
    let pieces = max(1, RestAudioPlan.maxPieceCount(audioBytes: audioBytes))
    let waves =
      (pieces + RestTranscriptAssembler.maxConcurrent - 1) / RestTranscriptAssembler.maxConcurrent
    return max(
      minimumSeconds,
      max(0, fallbackTimeout) + Double(waves) * secondsPerWave + marginSeconds)
  }

  /// The longest one wave of pieces can legitimately take under SarvamRestClient's retry
  /// policy: a request that ends in a 429 at its timeout, the longest backoff it honors, and
  /// the one retried request.
  static var secondsPerWave: Double {
    2 * SarvamRestClient.requestTimeout + SarvamRestClient.maxRetryDelay
  }

  static let minimumSeconds = 10.0
  static let marginSeconds = 1.0

  static func remaining(budget: Double, elapsed: Double) -> Double {
    max(0, budget - elapsed)
  }
}
