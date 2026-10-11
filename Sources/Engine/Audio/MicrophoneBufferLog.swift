// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Thread-safe record of hardware buffers for MicrophoneProbe. Appends arrive on the
/// capture processing queue; reads happen on main after the attempt ends.
final class MicrophoneBufferLog: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [MicrophoneBufferLog.Entry] = []

  typealias Entry = (frames: Int, sampleRate: Double, at: TimeInterval, inputAt: TimeInterval?)

  func append(frames: Int, sampleRate: Double, at time: TimeInterval, inputAt: TimeInterval?) {
    lock.lock()
    entries.append((frames, sampleRate, time, inputAt))
    lock.unlock()
  }

  func drain() -> [Entry] {
    lock.lock()
    let copy = entries
    entries.removeAll()
    lock.unlock()
    return copy
  }
}
