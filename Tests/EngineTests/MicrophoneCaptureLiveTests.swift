// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import XCTest

@testable import StokEngine

/// Opens the real microphone, so it runs only with STOK_MIC_TESTS=1 (pass
/// TEST_RUNNER_STOK_MIC_TESTS=1 to xcodebuild). It checks that IO-cycle capture delivers
/// short hardware buffers and that readiness follows the first one.
final class MicrophoneCaptureLiveTests: XCTestCase {
  override func setUpWithError() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["STOK_MIC_TESTS"] == "1", "Set STOK_MIC_TESTS=1")
  }

  @MainActor func testColdStartDeliversShortBuffers() async throws {
    let audio = AudioCaptureEngine(preRollMs: 0)
    let log = MicrophoneBufferLog()
    audio.onHardwareBuffer = { frames, rate, time, inputAt in
      log.append(frames: frames, sampleRate: rate, at: time, inputAt: inputAt)
    }
    XCTAssertTrue(audio.setup(startImmediately: false))
    defer { audio.stopEngine() }
    for attempt in 0..<3 {
      let start = ProcessInfo.processInfo.systemUptime
      let ready = await withCheckedContinuation { continuation in
        audio.ensureReady { continuation.resume(returning: $0) }
      }
      let readinessMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
      XCTAssertTrue(ready, "attempt \(attempt)")
      try await Task.sleep(nanoseconds: 300_000_000)
      audio.suspendEngine()
      let buffers = log.drain()
      let durations = buffers.map { Double($0.frames) / $0.sampleRate * 1000 }
      print(
        "attempt \(attempt) ready=\(ready) readiness_ms=\(readinessMs) count=\(buffers.count)"
          + " frames=\(Set(buffers.map(\.frames)).sorted())"
          + " first_ms=\(buffers.first.map { ($0.at - start) * 1000 } ?? -1)")
      XCTAssertFalse(buffers.isEmpty)
      XCTAssertLessThanOrEqual(durations.max() ?? .infinity, 21.4)
      try await Task.sleep(nanoseconds: 200_000_000)
    }
  }
}
