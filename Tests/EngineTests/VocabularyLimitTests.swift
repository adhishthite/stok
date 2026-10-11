// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import XCTest

@testable import StokEngine

final class VocabularyLimitTests: XCTestCase {
  func testVocabularyBeyondTheServiceLimitIsDroppedAndCounted() {
    let terms = (1...1205).map { "term\($0)" }.joined(separator: ",")
    let config = EngineConfiguration.load(values: ["CUSTOM_VOCABULARY": terms])
    XCTAssertEqual(config.recognitionVocabulary.count, SarvamAPI.maxKeyterms)
    XCTAssertEqual(config.customVocabularyDropped, 1155)
    XCTAssertEqual(config.recognitionVocabulary.first, "term1")
    XCTAssertEqual(config.recognitionVocabulary.last, "term50")
    // The complete list stays available so the analyzer never re-suggests a saved term.
    XCTAssertEqual(config.customVocabulary.count, 1205)
    XCTAssertEqual(config.customVocabulary.last, "term1205")
  }

  func testVocabularyWithinTheLimitIsSentUnchanged() {
    let config = EngineConfiguration.load(
      values: ["CUSTOM_VOCABULARY": "Kubernetes, cube cuttle => kubectl, Kubernetes"])
    XCTAssertEqual(config.customVocabulary, ["Kubernetes", "kubectl"])
    XCTAssertEqual(config.recognitionVocabulary, config.customVocabulary)
    XCTAssertEqual(config.customVocabularyDropped, 0)
  }

  func testOverlongTermIsCountedAsDropped() {
    let long = String(repeating: "a", count: SarvamAPI.maxKeytermLength + 1)
    let config = EngineConfiguration.load(values: ["CUSTOM_VOCABULARY": "Stok, \(long)"])
    XCTAssertEqual(config.recognitionVocabulary, ["Stok"])
    XCTAssertEqual(config.customVocabularyDropped, 1)
  }

  func testTurnLimitMatchesTheLockLimitMaximum() {
    XCTAssertEqual(DictationEngine.maxTurnSeconds, 600)
    let lockLimit = SettingCatalog.all.first { $0.key == "LOCK_LIMIT" }
    guard case .decimal(let range)? = lockLimit?.kind else { return XCTFail("LOCK_LIMIT kind") }
    XCTAssertEqual(range.upperBound, DictationEngine.maxTurnSeconds)
  }
}
