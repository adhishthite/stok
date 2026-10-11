// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A socket that never answers. Like URLSessionWebSocketTask.receive(), its receive ignores
/// Swift task cancellation and returns only once the socket itself is cancelled.
final class HangingSocket: @unchecked Sendable {
  private let lock = NSLock()
  private var waiting: CheckedContinuation<Data, Error>?
  private var cancelled = false
  /// Seconds cancel() keeps its caller after waking the pending receive, so the woken
  /// receive reliably finishes first. Models a slow socket close.
  var cancelHoldSeconds = 0.0

  func receive() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      if cancelled {
        lock.unlock()
        continuation.resume(throwing: URLError(.cancelled))
      } else {
        waiting = continuation
        lock.unlock()
      }
    }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let continuation = waiting
    waiting = nil
    lock.unlock()
    continuation?.resume(throwing: URLError(.cancelled))
    if continuation != nil, cancelHoldSeconds > 0 {
      Thread.sleep(forTimeInterval: cancelHoldSeconds)
    }
  }
}
