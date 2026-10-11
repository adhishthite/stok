// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Runs one REST request per audio piece with bounded concurrency and completes once: with
/// the joined transcript after every piece succeeds, or with the first failure. Requests
/// still in flight after a failure are cancelled through their scope.
final class RestTranscriptAssembler {
  typealias Start = (_ index: Int, _ done: @escaping (Result<String, Error>) -> Void) -> Void

  /// Pieces sent at once. A ten-minute dictation is 21 pieces; a small window keeps one long
  /// turn from tripping the per-minute rate limit.
  static let maxConcurrent = 4

  private let lock = NSLock()
  private let count: Int
  private let start: Start
  private var transcripts: [String?]
  private var nextIndex = 0
  private var finished = false
  private let completion: (Result<String, Error>) -> Void

  init(
    count: Int, start: @escaping Start, completion: @escaping (Result<String, Error>) -> Void
  ) {
    self.count = count
    self.start = start
    self.completion = completion
    self.transcripts = Array(repeating: nil, count: count)
  }

  func run() {
    guard count > 0 else {
      finish(.success(""))
      return
    }
    for _ in 0..<min(Self.maxConcurrent, count) { launchNext() }
  }

  private func launchNext() {
    lock.lock()
    guard !finished, nextIndex < count else {
      lock.unlock()
      return
    }
    let index = nextIndex
    nextIndex += 1
    lock.unlock()
    start(index) { [self] result in self.pieceFinished(index, result) }
  }

  private func pieceFinished(_ index: Int, _ result: Result<String, Error>) {
    switch result {
    case .failure(let error):
      finish(.failure(error))
    case .success(let text):
      lock.lock()
      transcripts[index] = text
      let all = transcripts.allSatisfy { $0 != nil }
      let joined = all ? RestAudioPlan.join(transcripts.compactMap { $0 }) : nil
      lock.unlock()
      if let joined { finish(.success(joined)) } else { launchNext() }
    }
  }

  private func finish(_ result: Result<String, Error>) {
    lock.lock()
    let first = !finished
    finished = true
    lock.unlock()
    if first { completion(result) }
  }
}
