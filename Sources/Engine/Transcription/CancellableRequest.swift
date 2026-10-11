// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import AppKit
import AudioToolbox
import Carbon
import CoreAudio
import Foundation
import IOKit
import Network
import SQLite3

final class CancellableRequest {
  let lock = NSLock()
  var cancelled = false
  private var task: URLSessionTask?
  var retry: DispatchWorkItem?
  private var children: [CancellableRequest] = []
  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func start(_ task: URLSessionTask) {
    lock.lock()
    let stop = cancelled
    if !stop { self.task = task }
    lock.unlock()
    if stop { task.cancel() } else { task.resume() }
  }

  func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
    let item = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      let stop = self.cancelled
      self.retry = nil
      self.lock.unlock()
      if !stop { work() }
    }
    lock.lock()
    let stop = cancelled
    if !stop { retry = item }
    lock.unlock()
    if !stop { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item) }
  }

  /// A scope for one of several requests that make up this one (a long recording sent in
  /// pieces). Cancelling this request cancels every child.
  func child() -> CancellableRequest {
    let child = CancellableRequest()
    lock.lock()
    let stop = cancelled
    if !stop { children.append(child) }
    lock.unlock()
    if stop { child.cancel() }
    return child
  }

  func completedTask() {
    lock.lock()
    task = nil
    lock.unlock()
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let task = self.task
    let retry = self.retry
    let children = self.children
    self.task = nil
    self.retry = nil
    self.children = []
    lock.unlock()
    retry?.cancel()
    task?.cancel()
    for child in children { child.cancel() }
  }
}
