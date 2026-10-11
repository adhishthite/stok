// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import XCTest

@testable import StokEngine

/// Hardware buffers that arrive through the IO-cycle ring keep the old capture rules: idle
/// audio feeds the pre-roll, recorded audio follows isRecording, a stale hardware generation
/// is dropped, and any lost or malformed buffer invalidates a live turn.
final class CaptureRingGatingTests: XCTestCase {
  private let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!

  private func makeEngine(preRollMs: Int = 400, chunkMs: Int = 100) -> AudioCaptureEngine {
    let audio = AudioCaptureEngine(preRollMs: preRollMs, chunkMs: chunkMs, silenceFlushMs: 0)
    let target = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    audio.prepareCapture(converter: AVAudioConverter(from: format, to: target)!, generation: 1)
    return audio
  }

  /// One 512-frame IO cycle (10.7 ms at 48 kHz), as the sink node would write it.
  private func deliverCycle(
    _ audio: AudioCaptureEngine, amplitude: Float = 0.25, buffers: Int = 1, frames: Int = 512
  ) {
    var samples = (0..<frames).map { amplitude * sin(Float($0) * 0.2) }
    samples.withUnsafeMutableBytes { raw in
      let list = AudioBufferList.allocate(maximumBuffers: buffers)
      defer { free(list.unsafeMutablePointer) }
      for index in 0..<buffers {
        list[index] = AudioBuffer(
          mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
      }
      _ = CaptureRing.write(
        audio.ring.pointer, UnsafePointer(list.unsafePointer), frames: UInt32(frames))
    }
  }

  private func stop(_ audio: AudioCaptureEngine) -> (bytes: Int, interrupted: Bool) {
    let result = audio.stopRecording(
      gracePeriodMs: 0, minTrailMs: 0, maxTrailMs: 0, silenceThresholdDb: -40)
    return (result.capturedBytes, result.interrupted)
  }

  func testIdleCyclesFeedThePreRollAndLiveCyclesTheTurn() {
    let audio = makeEngine()
    for _ in 0..<5 { deliverCycle(audio) }
    // No waker is running: start must drain on its own so the pre-roll is current.
    audio.audioProcessingQueue.sync { audio.startRecordingOnQueue() }
    XCTAssertGreaterThan(audio.preRollMsUsedInTurn, 40)
    for _ in 0..<10 { deliverCycle(audio) }
    // Stop drains everything delivered before it; ten cycles are about 107 ms.
    let (bytes, interrupted) = stop(audio)
    XCTAssertFalse(interrupted)
    XCTAssertGreaterThan(bytes, 90 * 32)
    XCTAssertLessThanOrEqual(bytes, 108 * 32)
  }

  func testStreamingFramesStayExactlyChunkSized() {
    let audio = makeEngine()
    let lock = NSLock()
    var sizes: [Int] = []
    audio.onAudioChunk = { chunk in
      lock.lock()
      sizes.append(chunk.count)
      lock.unlock()
    }
    audio.audioProcessingQueue.sync { audio.startRecordingOnQueue() }
    for _ in 0..<40 { deliverCycle(audio) }  // About 427 ms.
    audio.audioProcessingQueue.sync { audio.drainRingOnQueue() }
    lock.lock()
    let live = sizes
    lock.unlock()
    // CHUNK_MS 100 is 3,200 bytes; 427 ms yields four full frames and a carried remainder.
    XCTAssertEqual(live, [3200, 3200, 3200, 3200])
    _ = stop(audio)
    lock.lock()
    XCTAssertEqual(sizes.count, 5)
    XCTAssertGreaterThan(sizes.last ?? 0, 0)
    XCTAssertLessThan(sizes.last ?? .max, 3200)
    lock.unlock()
  }

  func testChunksShorterThanTheIOCycleNeverBuildABacklog() {
    // CHUNK_MS 20 is 640 bytes; a 1024-frame cycle at 48 kHz is about 683 bytes at 16 kHz.
    let audio = makeEngine(chunkMs: 20)
    let lock = NSLock()
    var chunks: [Data] = []
    audio.onAudioChunk = { chunk in
      lock.lock()
      chunks.append(chunk)
      lock.unlock()
    }
    audio.audioProcessingQueue.sync { audio.startRecordingOnQueue() }
    for _ in 0..<200 { deliverCycle(audio, frames: 1024) }
    audio.audioProcessingQueue.sync { audio.drainRingOnQueue() }
    lock.lock()
    let live = chunks
    lock.unlock()
    let result = audio.stopRecording(
      gracePeriodMs: 0, minTrailMs: 0, maxTrailMs: 0, silenceThresholdDb: -40)
    let total = result.capturedBytes
    // Every live chunk is exactly the target, and all but a sub-target remainder went out.
    XCTAssertTrue(live.allSatisfy { $0.count == 640 }, "sizes \(Set(live.map(\.count)))")
    XCTAssertEqual(live.count, total / 640)
    lock.lock()
    let all = chunks
    lock.unlock()
    XCTAssertLessThan(all.count - live.count, 2)
    XCTAssertLessThan(all.last?.count ?? 0, 641)
    // Order preserved: the chunks rebuild the captured audio exactly.
    XCTAssertEqual(all.reduce(Data(), +), result.pcmData)
  }

  func testRecordsFromAStoppedGenerationAreNeverCaptured() {
    let audio = makeEngine()
    audio.audioProcessingQueue.sync { audio.startRecordingOnQueue() }
    for _ in 0..<4 { deliverCycle(audio) }
    // A hardware rebuild discards the ring before the new generation starts.
    let target = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    audio.prepareCapture(converter: AVAudioConverter(from: format, to: target)!, generation: 2)
    let (bytes, interrupted) = stop(audio)
    XCTAssertEqual(bytes, 0)
    XCTAssertFalse(interrupted)
  }

  func testLostHardwareAudioInterruptsALiveTurn() {
    let audio = makeEngine()
    audio.audioProcessingQueue.sync { audio.startRecordingOnQueue() }
    // Fill the 1 MiB ring until the producer has to drop a cycle.
    while audio.ring.dropped == 0 { deliverCycle(audio) }
    XCTAssertTrue(stop(audio).interrupted)
  }

  func testLossDuringTheFinalStopDrainInterruptsTheTurn() {
    let audio = makeEngine()
    audio.audioProcessingQueue.sync { audio.startRecordingOnQueue() }
    deliverCycle(audio)
    // The stop drain is the first to see the cycle above. While it processes that cycle the
    // IO thread keeps writing and overflows the ring; that loss belongs to this turn.
    var injected = false
    audio.onHardwareBuffer = { [unowned self] _, _, _, _ in
      guard !injected else { return }
      injected = true
      while audio.ring.dropped == 0 { self.deliverCycle(audio) }
    }
    XCTAssertTrue(stop(audio).interrupted)
    XCTAssertTrue(injected)
  }

  func testMalformedCycleInterruptsALiveTurn() {
    let audio = makeEngine()
    audio.audioProcessingQueue.sync { audio.startRecordingOnQueue() }
    deliverCycle(audio)
    deliverCycle(audio, buffers: 2)  // Does not match the mono capture format.
    XCTAssertTrue(stop(audio).interrupted)
  }

  func testLostIdleAudioDoesNotTaintTheNextTurn() {
    let audio = makeEngine()
    while audio.ring.dropped == 0 { deliverCycle(audio) }
    audio.audioProcessingQueue.sync { audio.drainRingOnQueue() }
    audio.audioProcessingQueue.sync { audio.startRecordingOnQueue() }
    deliverCycle(audio)
    XCTAssertFalse(stop(audio).interrupted)
  }

  func testIOCycleIsShortenedOnlyWhenLong() {
    // 512 frames at 48 kHz is 10.7 ms: left alone.
    XCTAssertNil(AudioCaptureEngine.ioBufferFrames(current: 512, sampleRate: 48000, range: nil))
    // 4800 frames (100 ms) becomes 10 ms.
    XCTAssertEqual(
      AudioCaptureEngine.ioBufferFrames(current: 4800, sampleRate: 48000, range: 15...4096), 480)
    // Clamped to the device minimum.
    XCTAssertEqual(
      AudioCaptureEngine.ioBufferFrames(current: 2048, sampleRate: 16000, range: 256...4096), 256)
    // A device minimum above the current cycle never lengthens it.
    XCTAssertNil(
      AudioCaptureEngine.ioBufferFrames(current: 1024, sampleRate: 24000, range: 2048...4096))
    XCTAssertNil(AudioCaptureEngine.ioBufferFrames(current: 0, sampleRate: 48000, range: nil))
    XCTAssertNil(AudioCaptureEngine.ioBufferFrames(current: 4800, sampleRate: 0, range: nil))
  }
}
