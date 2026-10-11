// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A one-way flag shared between concurrent tasks: once set, it stays set.
final class ProbeFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  func set() {
    lock.lock()
    value = true
    lock.unlock()
  }

  var isSet: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}
