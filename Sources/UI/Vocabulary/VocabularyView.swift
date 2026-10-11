// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import StokEngine
import SwiftUI

struct VocabularyView: View {
  @Bindable var model: VocabularyEditorModel
  let save: () -> Void
  let analyze: () -> Void
  let cancelAnalysis: () -> Void
  let addSelected: () -> Void
  @State private var confirmAnalysis = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 14) {
        LotusMark(size: 34)
        VStack(alignment: .leading, spacing: 4) {
          Text("Your vocabulary").font(.system(.title2, design: .serif))
          Text("One term per line. Write wrong => right to fix a word Stok mishears.")
            .foregroundStyle(.secondary)
        }
      }.padding(22)
      Divider()
      VocabularyTextEditor(
        text: $model.contents,
        unsent: (model.report?.tooLong ?? []) + (model.report?.overLimit ?? [])
      )
      .padding(4)
      Divider()
      if let report = model.report {
        KeytermSummary(report: report, showsChips: false)
          .padding(.horizontal, 16).padding(.top, 12)
      }
      HStack {
        if model.analyzing {
          ProgressView().controlSize(.small)
          Text("Finding suggestions…").font(.callout)
          Button("Cancel", action: cancelAnalysis)
        } else {
          Button("Analyze history…", systemImage: "sparkles") { confirmAnalysis = true }
            .help("Find vocabulary terms and replacements from saved dictations.")
        }
        Spacer()
        Button("Save", action: save).keyboardShortcut("s")
      }.padding(16)
      if let message = model.message {
        Text(message).font(.callout).foregroundStyle(.secondary).padding(
          [.horizontal, .bottom], 16)
      }
    }
    .frame(minWidth: 620, minHeight: 420)
    .confirmationDialog("Find vocabulary suggestions?", isPresented: $confirmAnalysis) {
      Button("Analyze history", action: analyze)
    } message: {
      Text(
        "This sends up to 500 saved dictations from the last 30 days, the app you dictated each one into, your vocabulary, and observed word corrections to Sarvam. No timestamps are sent. You choose which suggestions to add."
      )
    }
    .sheet(
      isPresented: Binding(
        get: { !model.suggestions.isEmpty },
        set: {
          if !$0 {
            model.suggestions = []
            model.selected = []
          }
        })
    ) {
      VocabularySuggestionsView(model: model, addSelected: addSelected)
    }
  }
}
