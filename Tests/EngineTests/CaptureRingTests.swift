// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import CoreAudio
import StokCaptureRing
import XCTest

@testable import StokEngine

/// The lock-free hand-off between the CoreAudio IO thread and the capture processing queue.
final class CaptureRingTests: XCTestCase {
  /// Writes `samples` as one mono record, as the IO thread would.
  @discardableResult
  private func write(_ ring: CaptureRing, _ samples: [Float], buffers: Int = 1) -> Bool {
    var storage = samples
    return storage.withUnsafeMutableBytes { raw in
      let list = AudioBufferList.allocate(maximumBuffers: buffers)
      defer { free(list.unsafeMutablePointer) }
      for index in 0..<buffers {
        list[index] = AudioBuffer(
          mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
      }
      return CaptureRing.write(
        ring.pointer, UnsafePointer(list.unsafePointer), frames: UInt32(samples.count))
    }
  }

  /// Reads one mono record of at most `capacity` frames.
  private func read(_ ring: CaptureRing, capacity: Int = 4096) -> (
    StokCaptureReadStatus, StokCaptureRecordInfo, [Float]
  ) {
    var storage = [Float](repeating: 0, count: capacity)
    return storage.withUnsafeMutableBytes { raw in
      var list = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
          mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
      let (status, info) = ring.read(into: &list)
      let count = Int(list.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
      let values = Array(
        raw.bindMemory(to: Float.self).prefix(status == StokCaptureReadOK ? count : 0))
      return (status, info, values)
    }
  }

  func testRecordsRoundTripInOrderAcrossTheWrap() {
    let ring = CaptureRing(capacityBytes: 4096)
    // 4096-byte ring; each 100-frame record is 32 + 8 + 400 bytes, so 30 records wrap
    // several times.
    for record in 0..<30 {
      let samples = (0..<100).map { Float(record * 1000 + $0) }
      XCTAssertTrue(write(ring, samples))
      let (status, info, values) = read(ring)
      XCTAssertEqual(status, StokCaptureReadOK)
      XCTAssertEqual(info.frames, 100)
      XCTAssertEqual(info.bufferCount, 1)
      XCTAssertEqual(values, samples)
    }
    XCTAssertEqual(read(ring).0, StokCaptureReadEmpty)
    XCTAssertEqual(ring.dropped, 0)
  }

  func testHostTimeIsTheDeliveryInstantOnTheUptimeClock() {
    let ring = CaptureRing(capacityBytes: 4096)
    let before = ProcessInfo.processInfo.systemUptime
    write(ring, [0, 1])
    let after = ProcessInfo.processInfo.systemUptime
    let at = CaptureRing.uptime(hostTime: read(ring).1.hostTime)
    XCTAssertGreaterThanOrEqual(at, before - 0.001)
    XCTAssertLessThanOrEqual(at, after + 0.001)
  }

  func testCoreAudioInputStampTravelsWithTheRecord() {
    let ring = CaptureRing(capacityBytes: 4096)
    var samples: [Float] = [1, 2]
    var stamp = AudioTimeStamp()
    stamp.mHostTime = 123_456
    stamp.mFlags = .hostTimeValid
    samples.withUnsafeMutableBytes { raw in
      var list = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
          mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
      XCTAssertTrue(CaptureRing.write(ring.pointer, &list, frames: 2, timestamp: &stamp))
      stamp.mFlags = []
      XCTAssertTrue(CaptureRing.write(ring.pointer, &list, frames: 2, timestamp: &stamp))
    }
    XCTAssertEqual(read(ring).1.inputHostTime, 123_456)
    XCTAssertEqual(read(ring).1.inputHostTime, 0)
  }

  func testFullRingDropsAndCountsInsteadOfOverwriting() {
    let ring = CaptureRing(capacityBytes: 1024)
    let samples = [Float](repeating: 1, count: 100)  // 440 bytes per record
    XCTAssertTrue(write(ring, samples))
    XCTAssertTrue(write(ring, samples))
    XCTAssertFalse(write(ring, samples))
    XCTAssertEqual(ring.dropped, 1)
    // Unread data survives intact; space returns once the consumer reads.
    XCTAssertEqual(read(ring).2, samples)
    XCTAssertTrue(write(ring, samples))
    XCTAssertEqual(ring.dropped, 1)
  }

  func testDiscardAllDropsPublishedRecordsAndStartsANewEpoch() {
    let ring = CaptureRing(capacityBytes: 4096)
    write(ring, [1, 2, 3])
    let old = ring.epoch
    let epoch = ring.discardAll()
    XCTAssertEqual(epoch, old &+ 1)
    XCTAssertEqual(ring.usedBytes, 0)
    XCTAssertNil(ring.peek())
    write(ring, [4])
    XCTAssertEqual(ring.peek()?.epoch, epoch)
  }

  func testMismatchedDestinationConsumesTheRecord() {
    let ring = CaptureRing(capacityBytes: 4096)
    write(ring, [1, 2, 3], buffers: 2)
    write(ring, [7, 8])
    XCTAssertEqual(read(ring).0, StokCaptureReadMismatch)
    let (status, _, values) = read(ring)
    XCTAssertEqual(status, StokCaptureReadOK)
    XCTAssertEqual(values, [7, 8])
    // A record larger than the destination is also consumed, not left to block the ring.
    write(ring, [Float](repeating: 0, count: 64))
    XCTAssertEqual(read(ring, capacity: 8).0, StokCaptureReadMismatch)
    XCTAssertNil(ring.peek())
  }

  func testMalformedListIsDroppedOnTheProducerSide() {
    let ring = CaptureRing(capacityBytes: 4096)
    var list = AudioBufferList(
      mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: nil))
    XCTAssertFalse(CaptureRing.write(ring.pointer, &list, frames: 2))
    XCTAssertEqual(ring.dropped, 1)
    XCTAssertNil(ring.peek())
  }

  /// A real producer thread against a real consumer thread. Under Thread Sanitizer this is
  /// the race check for the hand-off; without it, it still proves order and integrity.
  func testConcurrentProducerAndConsumerKeepOrderAndIntegrity() {
    let ring = CaptureRing(capacityBytes: 16384)
    let records = 20000
    let frames = 37
    let producerDone = expectation(description: "producer")
    let producer = Thread {
      var sent = 0
      while sent < records {
        let samples = [Float](repeating: Float(sent), count: frames)
        if self.write(ring, samples) { sent += 1 }
      }
      producerDone.fulfill()
    }
    producer.start()
    var expected = 0
    var failures = 0
    let deadline = Date().addingTimeInterval(20)
    while expected < records && Date() < deadline {
      if ring.peek() == nil {
        ring.wait()
        continue
      }
      let (status, info, values) = read(ring)
      if status != StokCaptureReadOK || info.frames != UInt32(frames)
        || values != [Float](repeating: Float(expected), count: frames)
      {
        failures += 1
      }
      expected += 1
    }
    wait(for: [producerDone], timeout: 20)
    XCTAssertEqual(expected, records)
    XCTAssertEqual(failures, 0)
  }
}
