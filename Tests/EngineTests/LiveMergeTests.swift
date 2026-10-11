// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import StokEngine

final class LiveMergeTests: XCTestCase {
  private func overlap(_ committed: String, _ incoming: String) -> Int {
    SarvamLiveClient.transcriptOverlapLength(committed: committed, incoming: incoming)
  }

  func testOverlapCountsWholeWordsOnly() {
    XCTAssertEqual(overlap("hello world", "world today"), 5)
    XCTAssertEqual(overlap("the quick brown fox", "brown fox jumps over"), 9)
    // "world" is the head of "worldly", not a word of its own: trimming it would splice
    // "ly goods" onto the committed text.
    XCTAssertEqual(overlap("hello world", "worldly goods"), 0)
    XCTAssertEqual(overlap("hello", "goodbye"), 0)
    XCTAssertEqual(overlap("", "anything"), 0)
  }

  func testOverlapScanIsCapped() {
    // A run that repeats is the only way one transcript's tail can overlap another's head
    // by more than the cap.
    let shared = String(repeating: "ab ", count: 100)
    XCTAssertGreaterThan(shared.count, 200)
    let measured = overlap("x " + shared, shared + "end")
    // The shared run is longer than the scan cap, so the match is found but bounded.
    XCTAssertGreaterThan(measured, 0)
    XCTAssertLessThanOrEqual(measured, 200)
  }

  func testCorrectedFinalAppendsOnlyTheNewWords() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    // No utterance index: the text fallback trims the restated overlap.
    client.fixtureFinal("the quick brown fox", utterance: nil)
    client.fixtureFinal("brown fox jumps over", utterance: nil)
    XCTAssertEqual(client.fixtureText(), "the quick brown fox jumps over")
  }

  func testRepeatedFinalAddsNothing() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    client.fixtureFinal("hello there world", utterance: nil)
    client.fixtureFinal("there world", utterance: nil)
    XCTAssertEqual(client.fixtureText(), "hello there world")
  }

  func testUnrelatedFinalStillAppendsWithASeparator() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    client.fixtureFinal("hello", utterance: nil)
    client.fixtureFinal("goodbye", utterance: nil)
    XCTAssertEqual(client.fixtureText(), "hello goodbye")
  }

  func testPartialsReplaceTheLiveSegmentAndFinalsAccumulate() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    client.fixturePartial("Cuber", utterance: 0)
    client.fixturePartial("Cuber needs deployment", utterance: 0)
    XCTAssertEqual(client.fixtureText(), "Cuber needs deployment")
    client.fixtureFinal("Kubernetes deployment is ready.", utterance: 0)
    XCTAssertEqual(client.fixtureText(), "Kubernetes deployment is ready.")
    client.fixturePartial("Please", utterance: 1)
    XCTAssertEqual(client.fixtureText(), "Kubernetes deployment is ready. Please")
    client.fixtureFinal("Please review it.", utterance: 1)
    XCTAssertEqual(client.fixtureText(), "Kubernetes deployment is ready. Please review it.")
  }

  func testStalePartialAfterItsFinalIsIgnored() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    client.fixtureFinal("Done.", utterance: 0)
    // Partials for an utterance can trail its final; showing one would undo the final.
    client.fixturePartial("Do", utterance: 0)
    XCTAssertEqual(client.fixtureText(), "Done.")
    // A duplicate final for the same utterance adds nothing either.
    client.fixtureFinal("Done.", utterance: 0)
    XCTAssertEqual(client.fixtureText(), "Done.")
  }

  func testIndexedFinalsKeepRepeatedAndPrefixedSpeech() {
    // Each index is separate audio, so text that looks like a repeat is new speech.
    let repeated = SarvamLiveClient(apiKey: "")
    repeated.fixtureOpen()
    repeated.fixtureFinal("Yes.", utterance: 0)
    repeated.fixtureFinal("Yes.", utterance: 1)
    XCTAssertEqual(repeated.fixtureText(), "Yes. Yes.")
    let prefixed = SarvamLiveClient(apiKey: "")
    prefixed.fixtureOpen()
    prefixed.fixtureFinal("hello", utterance: 0)
    prefixed.fixtureFinal("hello again", utterance: 1)
    XCTAssertEqual(prefixed.fixtureText(), "hello hello again")
    let overlapping = SarvamLiveClient(apiKey: "")
    overlapping.fixtureOpen()
    overlapping.fixtureFinal("the quick brown fox", utterance: 0)
    overlapping.fixtureFinal("brown fox jumps over", utterance: 1)
    XCTAssertEqual(overlapping.fixtureText(), "the quick brown fox brown fox jumps over")
  }

  func testIndexedFinalsAssembleInIndexOrderAndIgnoreDuplicates() {
    let client = SarvamLiveClient(apiKey: "")
    client.fixtureOpen()
    client.fixtureFinal("Second.", utterance: 1)
    client.fixtureFinal("First.", utterance: 0)
    XCTAssertEqual(client.fixtureText(), "First. Second.")
    client.fixtureFinal("Second, resent.", utterance: 1)
    XCTAssertEqual(client.fixtureText(), "First. Second.", "a final per index counts once")
    client.fixturePartial("Thi", utterance: 2)
    XCTAssertEqual(client.fixtureText(), "First. Second. Thi")
    // A partial whose prefix happens to match committed text is still its own utterance.
    client.fixturePartial("First. again", utterance: 2)
    XCTAssertEqual(client.fixtureText(), "First. Second. First. again")
  }
}
