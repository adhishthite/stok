// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum MicrophoneProbe {
  /// Path of the per-buffer capture report. It sits beside the readiness report that the
  /// app writes to /tmp/stok-microphone-probe.json.
  public static let captureReportPath = "/tmp/stok-microphone-capture.json"
  private static let attempts = 6
  private static let collectSeconds = 0.6

  @MainActor public static func measure(prepareInput: Bool = false) async throws
    -> (startup: [MicrophoneStartupMeasurement], preparation: MicrophonePreparationMeasurement?)
  {
    let audio = AudioCaptureEngine(preRollMs: 0)
    let log = MicrophoneBufferLog()
    audio.onHardwareBuffer = { frames, rate, time, inputAt in
      log.append(frames: frames, sampleRate: rate, at: time, inputAt: inputAt)
    }
    guard audio.setup(startImmediately: false) else {
      throw NSError(domain: "Stok.MicrophoneProbe", code: 1)
    }
    defer { audio.stopEngine() }
    let preparation: MicrophonePreparationMeasurement?
    if prepareInput {
      preparation = await withCheckedContinuation { continuation in
        audio.prepareInput { continuation.resume(returning: $0) }
      }
    } else {
      preparation = nil
    }
    var measurements: [MicrophoneStartupMeasurement] = []
    var attemptsReport: [[String: Any]] = []
    for _ in 0..<attempts {
      try Task.checkCancellation()
      _ = log.drain()
      let start = ProcessInfo.processInfo.systemUptime
      var synchronousMilliseconds = 0.0
      let ready = await withCheckedContinuation { continuation in
        audio.ensureReady { continuation.resume(returning: $0) }
        synchronousMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
      }
      guard ready else { throw NSError(domain: "Stok.MicrophoneProbe", code: 2) }
      let readiness = (ProcessInfo.processInfo.systemUptime - start) * 1000
      let presentationLatency = await withCheckedContinuation { continuation in
        audio.lifecycle.queue.async {
          continuation.resume(returning: audio.audioEngine.inputNode.presentationLatency)
        }
      }
      measurements.append(
        MicrophoneStartupMeasurement(
          readinessMilliseconds: readiness, synchronousSetupMilliseconds: synchronousMilliseconds))
      try await Task.sleep(nanoseconds: UInt64(collectSeconds * 1_000_000_000))
      audio.suspendEngine()
      let buffers = log.drain()
      var attempt = report(buffers: buffers, start: start, readinessMs: readiness)
      attempt["input_presentation_latency_ms"] = presentationLatency * 1000
      attemptsReport.append(attempt)
      try await Task.sleep(nanoseconds: 200_000_000)
    }
    if let data = try? JSONSerialization.data(
      withJSONObject: ["attempts": attemptsReport, "input": audio.currentInputLabel],
      options: [.sortedKeys])
    {
      try? data.write(to: URL(fileURLWithPath: captureReportPath), options: .atomic)
    }
    return (measurements, preparation)
  }

  private static func report(
    buffers: [MicrophoneBufferLog.Entry], start: TimeInterval,
    readinessMs: Double
  ) -> [String: Any] {
    let durations = buffers.map { Double($0.frames) / $0.sampleRate * 1000 }.sorted()
    var intervals: [Double] = []
    for index in buffers.indices.dropFirst() {
      intervals.append((buffers[index].at - buffers[index - 1].at) * 1000)
    }
    intervals.sort()
    func pct(_ values: [Double], _ fraction: Double) -> Double? {
      guard !values.isEmpty else { return nil }
      return values[min(values.count - 1, Int((Double(values.count - 1) * fraction).rounded()))]
    }
    var result: [String: Any] = [
      "readiness_ms": readinessMs,
      "buffer_count": buffers.count,
      "frames": Array(Set(buffers.map(\.frames))).sorted(),
      "sample_rate": buffers.first?.sampleRate ?? 0,
    ]
    if let first = buffers.first { result["first_buffer_ms"] = (first.at - start) * 1000 }
    result["buffer_ms_p50"] = pct(durations, 0.5)
    result["buffer_ms_p90"] = pct(durations, 0.9)
    result["buffer_ms_max"] = durations.last
    result["interval_ms_p50"] = pct(intervals, 0.5)
    result["interval_ms_p90"] = pct(intervals, 0.9)
    result["interval_ms_max"] = intervals.last
    // Delivery lag of each buffer's first frame: from CoreAudio's input stamp to the IO
    // callback. The frame captured at key-up reaches the ring within this lag.
    let lags = buffers.compactMap { entry in entry.inputAt.map { (entry.at - $0) * 1000 } }.sorted()
    result["first_frame_lag_ms_p50"] = pct(lags, 0.5)
    result["first_frame_lag_ms_p90"] = pct(lags, 0.9)
    result["first_frame_lag_ms_max"] = lags.last
    return result
  }
}
