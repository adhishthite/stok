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

final class CoreRegressionTests: XCTestCase {
  func testReferenceFixtures() throws {
    func pairs(_ input: [CorrectionWatcher.Pair]) -> [String] {
      input.map { $0.wrong + "=>" + $0.right }
    }

    check(
      pairs(CorrectionWatcher.extractCorrections(pasted: "cloud", field: "Claude", vocabSet: []))
        == ["cloud=>Claude"], "proper noun correction")
    check(
      CorrectionWatcher.extractCorrections(pasted: "cloud", field: "Cloud", vocabSet: []).isEmpty,
      "case-only changes rejected")
    check(
      CorrectionWatcher.extractCorrections(pasted: "the", field: "The", vocabSet: []).isEmpty,
      "stopword rejected")
    check(
      CorrectionWatcher.extractCorrections(
        pasted: String(repeating: "word ", count: 513), field: "word", vocabSet: []
      ).isEmpty, "long paste budget")

    var seed: UInt64 = 0x51A7
    func next(_ limit: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 32) % UInt64(limit))
    }
    let vocabulary = [
      "cloud", "Claude", "code", "Code", "report", "Priya", "priya", "the", "...", "Next.js",
      "next.js", "部署", "मराठी",
    ]
    for _ in 0..<300 {
      let n = 1 + next(12)
      let pasted = (0..<n).map { _ in vocabulary[next(vocabulary.count)] }.joined(separator: " ")
      let field = (0..<(1 + next(40))).map { _ in vocabulary[next(vocabulary.count)] }.joined(
        separator: " ")
      let expected = LegacyCorrectionWatcher.extractCorrections(
        pasted: pasted, field: field, vocabSet: ["claude"]
      ).map { $0.wrong + "=>" + $0.right }
      check(
        pairs(
          CorrectionWatcher.extractCorrections(pasted: pasted, field: field, vocabSet: ["claude"]))
          == expected, "rolling window retains gates and tie behavior")
    }

    // A deliberately blocked terminal must not block producers or grow their queue without limit.
    let writerEntered = DispatchSemaphore(value: 0)
    let releaseWriter = DispatchSemaphore(value: 0)
    let logLock = NSLock()
    var written: [String] = []
    let writer = BoundedLogBuffer { text in
      if text == "block" {
        writerEntered.signal()
        releaseWriter.wait()
      }
      logLock.lock()
      written.append(text)
      logLock.unlock()
    }
    writer.submit("block")
    check(writerEntered.wait(timeout: .now() + 1) == .success, "log sink entered")
    let enqueueStart = ProcessInfo.processInfo.systemUptime
    for i in 0..<10000 { writer.submit("meter \(i)", meter: true) }
    for _ in 0..<1000 { writer.submit("diagnostic") }
    check(
      ProcessInfo.processInfo.systemUptime - enqueueStart < 1,
      "logging producers do not wait for sink")
    releaseWriter.signal()
    writer.flush(timeout: 2)
    logLock.lock()
    let logged = written
    logLock.unlock()
    check(logged.count <= 131, "bounded log queue")
    check(logged.contains("meter 9999"), "latest meter retained")
    Log.isVerbose = false
    var formatted = false
    func expensiveMessage() -> String {
      formatted = true
      return "unexpected"
    }
    Log.meter(expensiveMessage())
    check(!formatted, "normal mode skips meter formatting")

    let retryScope = CancellableRequest()
    let retryFired = DispatchSemaphore(value: 0)
    retryScope.schedule(after: 0.02) { retryFired.signal() }
    retryScope.cancel()
    check(retryFired.wait(timeout: .now() + 0.08) == .timedOut, "cancelled retry cannot start")

    let live = SarvamLiveClient(apiKey: "")
    live.fixtureOpen()
    live.fixtureFinal("First segment.", utterance: 0)
    check(live.fixtureText() == "First segment.", "pre-commit final preserves text")
    live.fixturePartial("Second segment", utterance: 1)
    let settled = DispatchSemaphore(value: 0)
    let resultLock = NSLock()
    var completions = 0
    var resultText = ""
    live.fixtureCompletion { result in
      resultLock.lock()
      completions += 1
      if case .success(let value) = result { resultText = value.text }
      resultLock.unlock()
      settled.signal()
    }
    // end_s at or past where the turn's audio ended marks the final that ends the turn.
    live.fixtureFinal("Second segment.", utterance: 1, endS: 0)
    check(settled.wait(timeout: .now() + 2) == .success, "split turn settles on its last final")
    resultLock.lock()
    check(resultText == "First segment. Second segment.", "segments preserved")
    resultLock.unlock()
    live.fixtureFinal("Late text", utterance: 2)
    resultLock.lock()
    check(
      completions == 1 && live.fixtureText().isEmpty,
      "completion exactly once; late closed-turn text ignored")
    resultLock.unlock()
    live.fixtureOpen()
    live.fixtureFinal("Old connection", utterance: 3, oldConnection: true)
    check(live.fixtureText().isEmpty, "old connection ignored")
    live.fixtureGap()
    check(!live.canCommitTurn, "partial stream ineligible")
    var rejected = false
    live.fixtureBeginCommit { if case .failure = $0 { rejected = true } }
    check(rejected, "partial stream fails before commit")

  }
}
