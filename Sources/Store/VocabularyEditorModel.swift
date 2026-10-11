// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Observation
import StokEngine

@MainActor
@Observable
final class VocabularyEditorModel {
  var contents = "" { didSet { if contents != oldValue { didEdit?() } } }
  var suggestions: [VocabularySuggestion] = []
  var selected: Set<String> = []
  var analyzing = false
  var message: String?
  /// What the current draft would send. Refreshed on each edit by the document, which
  /// knows the effective settings; nil until the first refresh.
  var report: KeytermReport?
  @ObservationIgnored var didEdit: (() -> Void)?
}
