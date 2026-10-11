// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AboutPane: View {
  @Environment(DictationStore.self) private var store
  @State private var copiedReport = false
  var body: some View {
    Form {
      Section {
        VStack(spacing: 12) {
          // Two equal flexible rules keep the icon group exactly centred.
          HStack(spacing: 14) {
            Hairline()
            Sparkle().fill(StokColor.glowSaffron).frame(width: 9, height: 9)
            Image(nsImage: NSApplication.shared.applicationIconImage)
              .resizable().interpolation(.high).frame(width: 96, height: 96)
            Sparkle().fill(StokColor.glowSaffron).frame(width: 9, height: 9)
            Hairline()
          }
          .accessibilityHidden(true)
          Text("Stok").font(.system(size: 30, weight: .regular, design: .serif))
          Text("Push-to-talk dictation in your language.").foregroundStyle(.secondary)
          Text("Version \(BuildIdentity.version)").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(alignment: .top) { HeroGlow().opacity(0.6).clipShape(.rect(cornerRadius: 8)) }
        .accessibilityElement(children: .combine)
      }
      Section("Support") {
        if store.updates.configured {
          Button("Check for Updates…") { store.updates.check() }.disabled(!store.updates.canCheck)
        }
        LabeledContent {
          Button(copiedReport ? "Copied" : "Copy") { copyReport() }
        } label: {
          Text("Build details")
          Text(BuildIdentity.report).font(.caption).foregroundStyle(.secondary)
        }
        Link(
          "Release notes",
          destination: URL(string: "https://github.com/adhishthite/stok/releases")!)
      }
      Section("Developer") {
        LabeledContent("Made by", value: "Adhish Thite")
        Link("GitHub", destination: URL(string: "https://github.com/adhishthite")!)
      }
      Section("License") {
        LabeledContent("License", value: "Apache License 2.0")
        LabeledContent {
          Button("Read") { open(license: "Stok-LICENSE") }
        } label: {
          Text(BuildIdentity.copyright)
        }
        LabeledContent {
          Button("Read") { PrivacyDocument.open() }
        } label: {
          Text("Privacy")
          Text("What stays on this Mac and what leaves it.").font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Section("Acknowledgements") {
        Text("Transcription is provided by the Sarvam API. Stok is not a Sarvam product.")
          .foregroundStyle(.secondary)
        LabeledContent {
          Button("Read") { open(license: "Sparkle-LICENSE") }
        } label: {
          Text("Sparkle")
          Text("Software updates. MIT License.").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }
  private func copyReport() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(BuildIdentity.report, forType: .string)
    copiedReport = true
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      copiedReport = false
    }
  }
  /// Opens the bundled license text in the user's text editor.
  private func open(license name: String) {
    guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return }
    NSWorkspace.shared.open(url)
  }
}
