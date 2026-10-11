// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import StokEngine
import SwiftUI
import XCTest

@testable import Stok

/// Renders the app's windows in light and dark for visual review. Runs only when
/// /tmp/stok-ui exists, so a normal test run writes nothing.
@MainActor
final class UIRenderTests: XCTestCase {
  private let directory = URL(fileURLWithPath: "/tmp/stok-ui", isDirectory: true)
  private var suites: [String] = []

  override func tearDown() async throws {
    for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
  }

  private func makeStore(_ values: [String: String] = [:]) -> DictationStore {
    let suite = "StokUIRender.\(UUID().uuidString)"
    suites.append(suite)
    let settings = SettingsStore(
      defaults: UserDefaults(suiteName: suite)!,
      supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString))
    for (key, value) in values { settings.set(key, value) }
    return DictationStore(settings: settings)
  }

  private func render(
    _ view: some View, size: NSSize, name: String, contrast: Bool = false
  ) async throws {
    let variants: [(String, NSAppearance.Name)] =
      contrast
      ? [("contrast", .accessibilityHighContrastAqua)]
      : [("light", .aqua), ("dark", .darkAqua)]
    for (suffix, appearanceName) in variants {
      let host = NSHostingView(
        rootView: view.frame(width: size.width, height: size.height)
          .background(Color(nsColor: .windowBackgroundColor))
          .environment(\.forceIncreasedContrast, contrast))
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: appearanceName)
      window.contentView = host
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(150))
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
    }
  }

  func testRenderWindows() async throws {
    try XCTSkipUnless(
      FileManager.default.fileExists(atPath: directory.path), "Create /tmp/stok-ui to render.")
    let store = makeStore(["TRANSCRIPTION_MODE": "translate", "LANGUAGE": "hi-IN"])
    for group in SettingGroup.allCases {
      try await render(
        NavigationStack { SettingsPane(group: group) }.environment(store),
        size: NSSize(width: 580, height: group == .advanced ? 1500 : 1000),
        name: "settings-\(group.rawValue.lowercased())")
    }
    try await render(
      SetupStatusView().environment(makeStore()), size: NSSize(width: 600, height: 1180),
      name: "onboarding")
    try await render(
      SetupStatusView().environment(makeStore()), size: NSSize(width: 600, height: 1180),
      name: "onboarding", contrast: true)
    try await render(
      NavigationStack { SettingsPane(group: .transcription) }.environment(store),
      size: NSSize(width: 580, height: 1000), name: "settings-transcription", contrast: true)
    // Setup complete: every permission granted and a key in the (injected) Keychain.
    let suite = "StokUIRender.\(UUID().uuidString)"
    suites.append(suite)
    let ready = SettingsStore(
      defaults: UserDefaults(suiteName: suite)!,
      supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString),
      readKey: { "render-fixture" })
    ready.load()
    let done = DictationStore(
      settings: ready,
      permissions: {
        PermissionStatus(microphone: true, accessibility: true, inputMonitoring: true)
      })
    try await render(
      SetupStatusView().environment(done), size: NSSize(width: 600, height: 1180),
      name: "onboarding-done")
    try await render(
      StatusMenu().environment(store), size: NSSize(width: 300, height: 420), name: "menu")
    let model = VocabularyEditorModel()
    model.contents = """
      # context: Solutions architect, cloud and payments
      Kubernetes
      Sarvam
      Saaras
      Vertex AI
      cube cuttle => kubectl
      ek naya term jo bahut lamba hai aur chaunsath akshar ki seema se zyada ho jata hai
      """
    model.report = store.settings.keytermReport(forFile: model.contents)
    try await render(
      VocabularyView(model: model, save: {}, analyze: {}, cancelAnalysis: {}, addSelected: {})
        .environment(store),
      size: NSSize(width: 680, height: 560), name: "vocabulary-editor")
  }
}
