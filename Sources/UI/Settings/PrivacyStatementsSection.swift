// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

/// Plain statements about where data goes, each with a way to check the claim.
struct PrivacyStatementsSection: View {
  @Environment(DictationStore.self) private var store
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Section {
      PrivacyStatementRow(
        icon: IconTile(symbol: "mic.fill", tint: .saffron), title: "Audio, only while you dictate",
        detail: "Sent to the Sarvam API only to transcribe it. Stok keeps no audio.")
      PrivacyStatementRow(
        icon: IconTile(symbol: "character.book.closed.fill", tint: .pink),
        title: "Vocabulary for recognition",
        detail: "Up to 50 vocabulary terms are sent to Sarvam to help recognize them.")
      PrivacyStatementRow(
        icon: IconTile(symbol: "lightbulb.fill", tint: .pink),
        title: "Vocabulary suggestions, when requested",
        detail:
          "Sends recent history, vocabulary, corrections, and any context you provide to Sarvam.")
      PrivacyStatementRow(
        icon: IconTile(symbol: "wand.and.stars", tint: .indigo),
        title: "Optional dictation cleanup",
        detail:
          "When enabled, sends the transcript to Sarvam. App-aware formatting also sends the app name and identifier."
      )
      PrivacyStatementRow(
        icon: IconTile(symbol: "key.fill", tint: .deepIndigo),
        title: "Your API key, in the request header",
        detail: "Stored in the macOS Keychain. Sent only to Sarvam.",
        action: "Open Keychain Access", perform: openKeychainAccess)
      PrivacyStatementRow(
        icon: IconTile(symbol: "chart.bar.fill", tint: .green),
        title: "Usage metrics, only if you turn them on",
        detail: "Off by default. Never transcripts, audio, vocabulary, or your key.",
        action: "View queued events", perform: { openWindow(id: "diagnostics") })
      PrivacyStatementRow(
        icon: IconTile(symbol: "arrow.triangle.2.circlepath", tint: .ink), title: "Update checks",
        detail: "Fetch a signed appcast. No profile information is sent.",
        action: "Open appcast", perform: openAppcast)
    } header: {
      Text("Leaves this Mac")
    }
    Section {
      PrivacyStatementRow(
        icon: IconTile(symbol: "clock.fill", tint: .indigo), title: "Dictation history",
        detail: "A local database on this Mac. Retention is set below.",
        action: "Show history file", perform: { reveal(historyURL) })
      PrivacyStatementRow(
        icon: IconTile(symbol: "chart.line.uptrend.xyaxis", tint: .green), title: "Dictation stats",
        detail:
          "Counts, timing, app names, and per-day word usage in a local database. Never full transcripts.",
        action: "Show stats file",
        perform: { reveal(store.stats.fileURL ?? store.settings.supportDirectory) })
      PrivacyStatementRow(
        icon: IconTile(symbol: "character.book.closed.fill", tint: .pink),
        title: "Vocabulary and learned corrections",
        detail:
          "Stored as local files. Vocabulary is sent for recognition; corrections are also sent when you request suggestions.",
        action: "Show vocabulary file",
        perform: { reveal(store.settings.resolvedVocabularyURL) })
    } header: {
      Text("Stays on this Mac")
    } footer: {
      Button("Read the full privacy document") { PrivacyDocument.open() }
        .controlSize(.small).padding(.top, 4)
    }
  }
  private var historyURL: URL {
    let raw = store.settings.configuration.historyDbPath
    let path = raw.isEmpty ? "~/Library/Application Support/Stok/history.db" : raw
    return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
  }
  private func reveal(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
    }
  }
  private func openKeychainAccess() {
    guard
      let url = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.keychainaccess")
    else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: .init())
  }
  private func openAppcast() {
    guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      let url = URL(string: feed)
    else { return }
    NSWorkspace.shared.open(url)
  }
}
