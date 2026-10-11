// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import StokEngine
import SwiftUI

struct VocabularyPane: View {
  @Environment(DictationStore.self) private var store
  @State private var importMessage: String?
  @State private var importError: String?
  private var report: KeytermReport { KeytermReport(configuration: store.settings.configuration) }
  private var isEmpty: Bool {
    report.sent.isEmpty && report.tooLong.isEmpty && report.overLimit.isEmpty
  }

  var body: some View {
    Form {
      Section {
        if isEmpty {
          emptyState
        } else {
          KeytermSummary(report: report).padding(.vertical, 4)
        }
        actions
        if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
        if let importMessage { Text(importMessage).font(.caption).foregroundStyle(.secondary) }
      } header: {
        Text("Sent with each dictation")
      } footer: {
        Text(
          "Terms bias recognition toward your spelling. Replacements (wrong => right) send their right side as a term and fix the text after."
        )
      }
      Section("File") {
        LabeledContent {
          HStack(spacing: 8) {
            // The folder and file name; the full path is in the tooltip.
            Text(shortPath(store.settings.resolvedVocabularyURL))
              .font(.callout).foregroundStyle(.secondary)
              .lineLimit(1).truncationMode(.middle)
              .help(store.settings.resolvedVocabularyURL.path)
              .accessibilityLabel("Path \(store.settings.resolvedVocabularyURL.path)")
            Button("Show in Finder") {
              NSWorkspace.shared.activateFileViewerSelecting([store.settings.resolvedVocabularyURL])
            }
          }
        } label: {
          Label {
            Text("Vocabulary file")
          } icon: {
            IconTile(symbol: "doc.text.fill", tint: .ink)
          }
        }
      }
      if !store.settings.additionalTerms.isEmpty { additionalTermsSection }
      // Additional terms are not edited here: the vocabulary file is the one format.
      CatalogSections(
        group: .vocabulary, excluding: ["CUSTOM_VOCABULARY", "CUSTOM_VOCABULARY_FILE"])
    }
  }

  private var additionalTermsSection: some View {
    let count = store.settings.additionalTerms.count
    let fromEnvironment = store.settings.isOverridden("CUSTOM_VOCABULARY")
    return Section {
      HStack {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(count == 1 ? "1 additional term" : "\(count) additional terms")
            Text(
              fromEnvironment
                ? "Set by the CUSTOM_VOCABULARY environment variable. Sent before the file's terms."
                : "From your configuration. Sent before the file's terms."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        } icon: {
          IconTile(symbol: "text.badge.plus", tint: .pink)
        }
        Spacer()
        if !fromEnvironment {
          Button("Move to File") {
            do {
              importMessage = try store.settings.moveAdditionalTermsToFile().message
              importError = nil
            } catch {
              importError = "Could not write the vocabulary file."
            }
          }
        }
      }
    } header: {
      Text("Additional terms")
    }
  }

  // The one way into the editor, with import beside it.
  private var actions: some View {
    HStack {
      Button("Open Editor") { store.showVocabulary?() }
        .buttonStyle(InkButtonStyle())
      Button("Import Terms…") {
        guard let url = FileDialogs.chooseVocabulary() else { return }
        do {
          importMessage = try store.settings.importVocabulary(from: url).message
          importError = nil
        } catch {
          importMessage = nil
          importError = "Choose a readable UTF-8 text file no larger than 1 MB."
        }
      }.disabled(store.settings.isOverridden("CUSTOM_VOCABULARY_FILE"))
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: isEmpty ? .center : .leading)
  }

  private func shortPath(_ url: URL) -> String {
    url.pathComponents.suffix(2).joined(separator: "/")
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      HStack(spacing: 14) {
        Hairline()
        LotusMark(size: 72)
        Hairline()
      }
      .padding(.horizontal, 40)
      Text("No terms yet").font(.system(size: 28, weight: .regular, design: .serif))
      Text(
        "Add the names, products, and jargon you say often. Stok sends up to \(SarvamAPI.maxKeyterms) with each dictation."
      )
      .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 18).padding(.bottom, 6)
  }
}
