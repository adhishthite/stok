// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
@preconcurrency import ApplicationServices
import StokEngine
import SwiftUI

struct SetupStatusView: View {
  @Environment(DictationStore.self) private var store
  var onDone: (() -> Void)?
  @State private var importError: String?
  @State private var importMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      SetupHero(shortcut: store.shortcutLabel)
        .fixedSize(horizontal: false, vertical: true)
        .background(HeroGlow())
        .layoutPriority(1)
      Form {
        permissionsStep
        APIKeySection(step: 2)
        languageStep
        shortcutStep
        SetupPrivacySection()
        vocabularySection
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(StokColor.surface)
      Divider()
      footer
    }
    .frame(minWidth: 560, idealWidth: 600, minHeight: 640, idealHeight: 760)
    .task {
      while !Task.isCancelled {
        store.refreshPermissions()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  private var permissionsStep: some View {
    Section {
      SetupPermissionRow(
        name: "Microphone", purpose: "Hear you while you hold the shortcut.", symbol: "mic.fill",
        tint: .saffron, granted: store.permissions.microphone
      ) {
        Task {
          _ = await AVCaptureDevice.requestAccess(for: .audio)
          store.refreshPermissions()
          if !store.permissions.microphone { openPane("Privacy_Microphone") }
        }
      }
      SetupPermissionRow(
        name: "Accessibility", purpose: "Paste the text into the app you are using.",
        symbol: "accessibility", tint: .indigo, granted: store.permissions.accessibility
      ) {
        let options =
          [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPane("Privacy_Accessibility")
      }
      SetupPermissionRow(
        name: "Input Monitoring", purpose: "Notice the shortcut in any app.", symbol: "keyboard",
        tint: .periwinkle, granted: store.permissions.inputMonitoring
      ) {
        _ = CGRequestListenEventAccess()
        openPane("Privacy_ListenEvent")
      }
    } header: {
      SetupStepHeader(number: 1, title: "Allow access", done: store.permissions.allGranted)
    } footer: {
      if !store.permissions.accessibility || !store.permissions.inputMonitoring {
        HStack(alignment: .firstTextBaseline) {
          Text("Not listed in System Settings? Click + and add this copy of Stok.")
          Spacer()
          Button("Show Stok in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
          }
          .controlSize(.small)
        }
      }
    }
  }

  private var languageStep: some View {
    Section {
      if let setting = SettingCatalog.all.first(where: { $0.key == "LANGUAGE" }) {
        SettingRow(
          setting: setting, icon: IconTile(symbol: "character.bubble.fill", tint: .periwinkle))
      }
      outputRow
    } header: {
      SetupStepHeader(number: 3, title: "Language and output")
    } footer: {
      Text("Change these any time in Settings > Transcription.")
    }
  }

  private var shortcutStep: some View {
    Section {
      if let setting = SettingCatalog.all.first(where: { $0.key == "HOTKEY" }) {
        SettingRow(setting: setting, icon: IconTile(symbol: "command", tint: .ink))
      }
      ShortcutCheckView()
    } header: {
      SetupStepHeader(number: 4, title: "Try your shortcut")
    }
  }

  private var vocabularySection: some View {
    Section {
      HStack {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text("Import terms")
            Text("A text file with one name or term per line.").font(.caption)
              .foregroundStyle(.secondary)
          }
        } icon: {
          IconTile(symbol: "character.book.closed.fill", tint: .pink)
        }
        Spacer()
        Button("Choose File…") {
          guard let url = FileDialogs.chooseVocabulary() else { return }
          do {
            importMessage = try store.settings.importVocabulary(from: url).message
            importError = nil
          } catch {
            importMessage = nil
            importError = "Choose a readable UTF-8 text file no larger than 1 MB."
          }
        }.disabled(store.settings.isOverridden("CUSTOM_VOCABULARY_FILE"))
      }
      if let importError { Text(importError).foregroundStyle(.red).font(.caption) }
      if let importMessage { Text(importMessage).foregroundStyle(.secondary).font(.caption) }
    } header: {
      Text("Vocabulary (optional)")
    } footer: {
      Text(
        "Names and terms Stok should spell your way. Up to \(SarvamAPI.maxKeyterms) terms of \(SarvamAPI.maxKeytermLength) characters are sent with each dictation."
      )
    }
  }

  // The output choice with its example inline, as in Settings > Transcription.
  private var outputRow: some View {
    let mode = store.transcriptionMode
    return VStack(alignment: .leading, spacing: 5) {
      HStack {
        Label {
          Text("Output")
        } icon: {
          IconTile(symbol: "text.quote", tint: .indigo)
        }
        Spacer()
        Text(mode.example).font(.callout).lineLimit(1)
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(StokColor.chipIndigo, in: .rect(cornerRadius: 6))
          .accessibilityLabel("Example: \(mode.example)")
        Picker(
          "Output",
          selection: Binding(
            get: { mode.rawValue },
            set: { store.settings.set("TRANSCRIPTION_MODE", $0) })
        ) {
          ForEach(TranscriptionMode.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
        }
        .labelsHidden().fixedSize()
        .disabled(store.settings.isOverridden("TRANSCRIPTION_MODE"))
      }
      Text(mode.summary).font(.caption).foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  private var missing: [String] {
    var items: [String] = []
    if !store.permissions.microphone { items.append("Microphone") }
    if !store.permissions.accessibility { items.append("Accessibility") }
    if !store.permissions.inputMonitoring { items.append("Input Monitoring") }
    if !store.settings.hasAPIKey { items.append("Sarvam API key") }
    return items
  }

  private var footer: some View {
    HStack(spacing: 12) {
      if missing.isEmpty {
        Label(
          "Ready. Open a document and try \(store.shortcutLabel).",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(StokColor.green)
      } else {
        Label(
          "Still needed: \(missing.formatted(.list(type: .and))).", systemImage: "circle.dashed"
        )
        .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Start Dictating") { onDone?() }
        .buttonStyle(InkButtonStyle())
        .disabled(store.needsSetup)
        .keyboardShortcut(.defaultAction)
      // Escape leaves setup the same way, and only once setup is complete. A zero-size
      // button keeps the shortcut without a second visible control.
      Button("Close setup") { if !store.needsSetup { onDone?() } }
        .keyboardShortcut(.cancelAction)
        .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }
    .font(.callout)
    .padding(.horizontal, 20).padding(.vertical, 14)
    .background(.bar)
  }

  private func openPane(_ anchor: String) {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
  }
}
