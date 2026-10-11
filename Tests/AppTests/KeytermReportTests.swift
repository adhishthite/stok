// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import XCTest

@testable import Stok
@testable import StokEngine

@MainActor
final class KeytermReportTests: XCTestCase {
  private func makeSettings() -> (SettingsStore, String) {
    let suite = "StokKeytermTests.\(UUID().uuidString)"
    let settings = SettingsStore(
      defaults: UserDefaults(suiteName: suite)!,
      supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString))
    return (settings, suite)
  }

  func testAdditionalTermsComeFirstSoAFileTermPastTheLimitIsReportedUnsent() {
    let (settings, suite) = makeSettings()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let additional = (1...50).map { "Term\($0)" }.joined(separator: ", ")
    settings.set("CUSTOM_VOCABULARY", additional)
    let report = settings.keytermReport(forFile: "Saaras")
    XCTAssertEqual(report.sent.count, 50)
    XCTAssertFalse(report.sent.contains("Saaras"))
    XCTAssertEqual(report.overLimit, ["Saaras"])
  }

  func testAnOlderModelSendsNoTerms() {
    let (settings, suite) = makeSettings()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    settings.set("LIVE_MODEL", "saaras:v3-realtime")
    let report = settings.keytermReport(forFile: "Saaras")
    XCTAssertEqual(report.modelsWithoutKeyterms, ["saaras:v3-realtime"])
  }

  func testDraftReportLeavesVerboseLoggingAlone() {
    let (settings, suite) = makeSettings()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let before = Log.isVerbose
    _ = settings.keytermReport(forFile: "Saaras\n" + String(repeating: "x", count: 70))
    XCTAssertEqual(Log.isVerbose, before)
  }
}
