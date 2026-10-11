// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import StokEngine
import SwiftUI

/// The output choice as a list of real examples: the same Hindi sentence written by each
/// mode, so the difference is visible before choosing.
struct OutputModeSection: View {
  @Environment(DictationStore.self) private var store
  private let key = "TRANSCRIPTION_MODE"
  private var overridden: Bool { store.settings.isOverridden(key) }
  private var selection: TranscriptionMode { store.transcriptionMode }

  var body: some View {
    Section {
      ForEach(TranscriptionMode.allCases, id: \.self) { mode in
        OutputModeRow(mode: mode, selected: mode == selection) {
          store.settings.set(key, mode.rawValue)
        }
        .disabled(overridden)
      }
    } header: {
      Text("Output")
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text("Examples are what Saaras returned for “मेरी मीटिंग तीन बजे है”.")
        if selection == .translate {
          Text(
            "While you speak, the overlay shows your words as spoken. Stok pastes the English."
          )
        }
        if overridden { Label("Set by environment", systemImage: "terminal") }
      }
    }
  }
}
