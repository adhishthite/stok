// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import CoreAudio
import Foundation
import StokCaptureRing

/// Owns one StokCaptureRing. The producer side is `pointer`, handed to the IO-cycle callback
/// as a trivial value, so the callback captures no Swift reference and does no reference
/// counting. Every other method is for the single consumer (the capture processing queue) or
/// its waker thread.
final class CaptureRing: @unchecked Sendable {
  let pointer: OpaquePointer

  init(capacityBytes: UInt32) {
    guard let ring = stok_capture_ring_create(capacityBytes) else {
      fatalError("Could not allocate the capture ring")
    }
    pointer = ring
  }

  deinit { stok_capture_ring_destroy(pointer) }

  /// Producer entry point. Also usable from tests that stand in for the IO thread.
  @inline(__always) static func write(
    _ ring: OpaquePointer, _ list: UnsafePointer<AudioBufferList>, frames: UInt32,
    timestamp: UnsafePointer<AudioTimeStamp>? = nil
  ) -> Bool {
    stok_capture_ring_write(ring, timestamp, list, frames)
  }

  func peek() -> StokCaptureRecordInfo? {
    var info = StokCaptureRecordInfo()
    return stok_capture_ring_peek(pointer, &info) ? info : nil
  }

  func read(into list: UnsafeMutablePointer<AudioBufferList>) -> (
    StokCaptureReadStatus, StokCaptureRecordInfo
  ) {
    var info = StokCaptureRecordInfo()
    let status = stok_capture_ring_read(pointer, list, &info)
    return (status, info)
  }

  @discardableResult func discardAll() -> UInt32 { stok_capture_ring_discard_all(pointer) }
  var epoch: UInt32 { stok_capture_ring_epoch(pointer) }
  var dropped: UInt64 { stok_capture_ring_dropped(pointer) }
  var usedBytes: UInt64 { stok_capture_ring_used(pointer) }
  func wait() { stok_capture_ring_wait(pointer) }
  func wake() { stok_capture_ring_wake(pointer) }

  /// Uptime seconds for a record's host time (the same clock as ProcessInfo.systemUptime).
  static func uptime(hostTime: UInt64) -> TimeInterval {
    Double(AudioConvertHostTimeToNanos(hostTime)) / 1_000_000_000
  }
}
