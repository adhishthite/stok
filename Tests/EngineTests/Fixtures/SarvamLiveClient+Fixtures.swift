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
import XCTest

@testable import StokEngine

extension SarvamLiveClient {
  func recoveryFixture(_ probe: LiveWriteProbe) {
    webSocketTask = urlSession.webSocketTask(with: URL(string: "wss://example.invalid")!)
    writeTransport = { _, text, completion in probe.accept(text, completion) }
  }
  func recoveryReady() {
    fixtureSessionBegin()
    recoveryDrain()
  }
  func recoveryDrain() {
    sendQueue.sync {}
    sendQueue.sync {}
  }
  var recoveryPending: Int {
    lock.lock()
    defer { lock.unlock() }
    return pendingWrites.count
  }
  var recoveryGap: Bool {
    lock.lock()
    defer { lock.unlock() }
    return turnHasAudioGap
  }
  func recoveryExpire() {
    lock.lock()
    let work = writeDeadline
    lock.unlock()
    work?.perform()
    recoveryDrain()
  }
  func recoveryConnectionFailure() {
    connectionFailed(epoch: connectionID, error: NSError(domain: "fixture", code: 2))
    recoveryDrain()
  }
  func recoverySend(_ text: String) {
    sendTurnMessage(text)
    recoveryDrain()
  }
  func recoveryForceSettleAge() {
    lock.lock()
    turnCommitTime = ProcessInfo.processInfo.systemUptime - 10
    commitWritesCompletedAt = turnCommitTime
    let current = turnID
    lock.unlock()
    attemptSettle(turn: current)
  }
}

extension SarvamLiveClient {
  func fixtureOpen() {
    lock.lock()
    turnID &+= 1
    turnOpen = true
    readyState = true
    turnHasAudioGap = false
    hasFiredTurnCompletion = false
    resetTranscriptLocked()
    lock.unlock()
  }
  /// Feeds one server event, shaped like the realtime socket's JSON messages.
  func fixtureEvent(_ fields: [String: Any], oldConnection: Bool = false) {
    let bytes = try! JSONSerialization.data(withJSONObject: fields)
    lock.lock()
    let epoch = connectionID
    lock.unlock()
    handleIncomingMessage(.data(bytes), epoch: oldConnection ? epoch &- 1 : epoch)
  }
  /// `utterance: nil` omits the index, the shape the text fallback handles.
  func fixturePartial(_ text: String, utterance: Int? = 0, oldConnection: Bool = false) {
    var fields: [String: Any] = ["event": "transcript.partial", "text": text]
    if let utterance { fields["utterance_idx"] = utterance }
    fixtureEvent(fields, oldConnection: oldConnection)
  }
  /// `endS` is the session-relative end time the server adds with return_timestamps.
  func fixtureFinal(
    _ text: String, utterance: Int? = 0, endS: Double? = nil, oldConnection: Bool = false
  ) {
    var fields: [String: Any] = ["event": "transcript.final", "text": text]
    if let utterance { fields["utterance_idx"] = utterance }
    if let endS { fields["end_s"] = endS }
    fixtureEvent(fields, oldConnection: oldConnection)
  }
  /// Streams `seconds` of audio through the probe one second per write, acknowledging each,
  /// then sends speech_end and acknowledges it, leaving the turn committed.
  func fixtureStreamAndCommit(
    seconds: Int, probe: LiveWriteProbe, acknowledgeSpeechEnd: Bool = true,
    completion:
      @escaping (Result<(text: String, firstTokenMs: Double, totalMs: Double), Error>) -> Void
  ) {
    for _ in 0..<seconds {
      sendAudioChunk(Data(count: 32_000))
      recoveryDrain()
      probe.finish(probe.sent.count - 1)
      recoveryDrain()
    }
    commitTurn(completion: completion)
    recoveryDrain()
    guard acknowledgeSpeechEnd else { return }
    probe.finish(probe.sent.count - 1)
    recoveryDrain()
  }
  /// Puts the turn in the state finishCommitWrites leaves it in: speech_end is on the wire.
  func fixtureCompletion(
    _ completion:
      @escaping (Result<(text: String, firstTokenMs: Double, totalMs: Double), Error>) -> Void
  ) {
    lock.lock()
    isCommitting = true
    turnCommitTime = ProcessInfo.processInfo.systemUptime
    commitWritesComplete = true
    commitWritesCompletedAt = turnCommitTime
    turnCompletion = completion
    lock.unlock()
  }
  func fixtureSessionBegin() {
    fixtureEvent(["event": "session.begin", "request_id": "fixture"])
  }
  func fixtureText() -> String {
    lock.lock()
    defer { lock.unlock() }
    return currentTurnText
  }
  func fixtureGap() {
    lock.lock()
    turnHasAudioGap = true
    lock.unlock()
  }
  func fixtureBeginCommit(
    _ completion:
      @escaping (Result<(text: String, firstTokenMs: Double, totalMs: Double), Error>) -> Void
  ) {
    beginCommit(turn: turnID, completion: completion)
  }
  /// Whether an idle keepalive ping is armed for the current connection.
  var fixtureKeepaliveArmed: Bool {
    lock.lock()
    defer { lock.unlock() }
    return keepaliveWorkItem != nil
  }
}
