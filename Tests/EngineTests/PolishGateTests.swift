// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import XCTest

@testable import StokEngine

final class PolishGateTests: XCTestCase {
  func testShortPunctuatedSentencesSkipCleanup() {
    for text in [
      "Okay this is another test that I am doing and hopefully it works.",
      "I think I have done a few turns, can you check?",
      "Sounds good, let's meet at five.",
      "What is your number? One call is enough.",
      "First we test, then we ship.",
      "I can’t attend today but I can review your draft and send feedback before the meeting starts later this afternoon.",
      "",
    ] {
      XCTAssertFalse(PolishGate.needsPolish(text), text)
    }
  }

  func testSpokenStructureNeedsCleanup() {
    for text in [
      "Here are the things number one commit this number two push this",
      "Add milk new line add eggs",
      "Step one open the app.",
      "Firstly we ship.",
      "Bullet apples.",
      "Dear team comma thanks.",
      "Is it ready question mark",
      "Number 1 commit this number 2 push this",
      "First, buy milk. Second, buy eggs. Third, buy bread.",
      "Buy these: first, milk; second, eggs; third, bread.",
      "Hello team period Thanks for your help period",
    ] {
      XCTAssertTrue(PolishGate.needsPolish(text), text)
    }
  }

  func testSpelledOutNumbersNeedCleanup() {
    XCTAssertTrue(PolishGate.needsPolish("It costs twenty five rupees."))
    XCTAssertTrue(PolishGate.needsPolish("We grew forty percent."))
    XCTAssertTrue(PolishGate.needsPolish("Budget is two crore."))
    XCTAssertTrue(PolishGate.needsPolish("He said 'twenty' rupees."))
  }

  func testNonLatinScriptsAlwaysPolish() {
    XCTAssertTrue(PolishGate.needsPolish("मैं कल आऊंगा।"))
    XCTAssertTrue(PolishGate.needsPolish("दूध नई लाइन अंडे"))
    XCTAssertFalse(PolishGate.needsPolish("Caf\u{E9} opens at nine."))
    XCTAssertFalse(PolishGate.needsPolish("Cafe\u{301} opens at nine."))
  }

  func testInternalDotsDoNotEndASentence() {
    XCTAssertTrue(
      PolishGate.needsPolish(
        "Please change the com.example.app configuration and make sure all requests go through our staging endpoint before deploying the next release to production"
      ))
    XCTAssertFalse(PolishGate.needsPolish("Version 2.5 ships today. Ping me."))
  }

  func testLongRunsWithoutTerminatorsNeedCleanup() {
    let run = Array(repeating: "word", count: PolishGate.maximumRunWords + 1).joined(
      separator: " ")
    XCTAssertTrue(PolishGate.needsPolish(run))
    XCTAssertTrue(PolishGate.needsPolish(run + "."))
    let atLimit = Array(repeating: "word", count: PolishGate.maximumRunWords).joined(
      separator: " ")
    XCTAssertFalse(PolishGate.needsPolish(atLimit + ". " + atLimit + "."))
  }

  func testSelectiveStageSkipsInlineWithoutARequest() {
    var config = EngineConfiguration()
    config.postProcessEnabled = true
    XCTAssertTrue(config.postProcessSelective)
    let queue = DispatchQueue(label: "test.cleanup.selective")
    let stage = PostProcessingStage(queue: queue) { _, _, _, _, _ in
      XCTFail("A turn that needs no cleanup must not contact a model")
      return CancellableRequest()
    }
    var completedInline = false
    queue.sync {
      stage.process(
        text: "Sounds good.", configuration: config, appName: nil, appBundleId: nil
      ) {
        XCTAssertEqual($0.text, "Sounds good.")
        XCTAssertEqual($0.metrics.status, "not_needed")
        XCTAssertEqual($0.metrics.displayStatus, "Not needed; original used")
        completedInline = true
      }
    }
    XCTAssertTrue(completedInline)
  }

  func testSelectiveStageStillPolishesStructuredTurns() {
    var config = EngineConfiguration()
    config.postProcessEnabled = true
    let queue = DispatchQueue(label: "test.cleanup.selective.list")
    let done = expectation(description: "cleanup")
    let stage = PostProcessingStage(queue: queue) { _, _, _, _, completion in
      completion(
        PostProcessingResult(text: "1. Commit", metrics: PostProcessingMetrics(status: "completed"))
      )
      return CancellableRequest()
    }
    queue.sync {
      stage.process(
        text: "number one commit", configuration: config, appName: nil, appBundleId: nil
      ) {
        XCTAssertEqual($0.text, "1. Commit")
        XCTAssertEqual($0.metrics.status, "completed")
        done.fulfill()
      }
    }
    wait(for: [done], timeout: 1)
  }

  func testCatalogDefaultsToSelective() {
    XCTAssertTrue(EngineConfiguration.load(values: [:]).postProcessSelective)
    XCTAssertFalse(
      EngineConfiguration.load(values: ["POST_PROCESS_SELECTIVE": "false"]).postProcessSelective)
  }
}
