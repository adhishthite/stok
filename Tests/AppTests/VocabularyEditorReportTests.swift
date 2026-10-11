// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import StokEngine
import XCTest

@testable import Stok

@MainActor
final class VocabularyEditorReportTests: XCTestCase {
  private var suites: [String] = []

  override func tearDown() async throws {
    for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
  }

  private func makeSettings() -> SettingsStore {
    let suite = "StokEditorReport.\(UUID().uuidString)"
    suites.append(suite)
    return SettingsStore(
      defaults: UserDefaults(suiteName: suite)!,
      supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString))
  }

  func testLocatorMarksOnlyParsedItems() {
    let text = """
      # cat is a comment
      cat
      catalog
      kat => cat
      dog, cat , bird
      """
    let found = VocabularyTermLocator.terms(in: text)
    let string = text as NSString
    let cats = found.filter { $0.term.lowercased() == "cat" }.map {
      string.substring(with: $0.range)
    }
    // The line "cat", the right side of the rule, and the comma item; never the comment,
    // "catalog", or the rule's left side.
    XCTAssertEqual(cats, ["cat", "cat", "cat"])
    XCTAssertFalse(found.contains { $0.term == "kat" })
    XCTAssertFalse(found.contains { $0.term.hasPrefix("#") })
    XCTAssertTrue(found.contains { $0.term == "catalog" })
    let ruleLine = string.range(of: "kat => cat")
    let rightSide = found.first { NSLocationInRange($0.range.location, ruleLine) }
    XCTAssertEqual(rightSide.map { string.substring(with: $0.range) }, "cat")
    XCTAssertEqual(rightSide?.range.location, ruleLine.location + 7)
  }

  func testLocatorAgreesWithTheEngineParser() {
    let text =
      "Kubernetes\n  Vertex AI  \n# context: x\na, b ,c\ncube cuttle => kubectl\n=> empty\n"
    let located = VocabularyTermLocator.terms(in: text).map(\.term)
    let parsed = EngineConfiguration.vocabularyTerms(additionalSetting: "", fileText: text)
    XCTAssertEqual(Set(located), Set(parsed))
  }

  func testModeChangeIsObservable() {
    let store = DictationStore(settings: makeSettings())
    let changed = expectation(description: "mode change observed")
    withObservationTracking {
      _ = store.transcriptionMode
    } onChange: {
      changed.fulfill()
    }
    store.settings.set("TRANSCRIPTION_MODE", "TRANSLATE")
    wait(for: [changed], timeout: 1)
    XCTAssertEqual(store.transcriptionMode, .translate)
  }

  func testOpenEditorReportFollowsSettingsWithoutMarkingTheDocumentEdited() async throws {
    let settings = makeSettings()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("vocabulary.txt")
    try "Saaras\n".write(to: url, atomically: true, encoding: .utf8)
    let document = try VocabularyDocument(contentsOf: url, ofType: "public.plain-text")
    defer { document.close() }
    document.settings = settings
    XCTAssertEqual(document.model.report?.sent, ["Saaras"])
    settings.set("LIVE_MODEL", "saaras:v3-realtime")
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(document.model.report?.modelsWithoutKeyterms, ["saaras:v3-realtime"])
    settings.set("CUSTOM_VOCABULARY", (1...50).map { "Term\($0)" }.joined(separator: ","))
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(document.model.report?.overLimit, ["Saaras"])
    XCTAssertFalse(document.isDocumentEdited)
  }

  func testAdditionalTermsMoveIntoTheFile() throws {
    let settings = makeSettings()
    settings.set("CUSTOM_VOCABULARY", "Kubernetes, cube cuttle => kubectl")
    try settings.moveAdditionalTermsToFile()
    XCTAssertTrue(settings.additionalTerms.isEmpty)
    let file = try String(contentsOf: settings.vocabularyURL, encoding: .utf8)
    XCTAssertTrue(file.contains("Kubernetes"))
    XCTAssertTrue(file.contains("cube cuttle => kubectl"))
    XCTAssertEqual(
      Set(settings.configuration.customVocabulary), Set(["Kubernetes", "kubectl"]))
  }
}
