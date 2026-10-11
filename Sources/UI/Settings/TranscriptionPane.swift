// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import StokEngine
import SwiftUI

/// The Sarvam connection, the spoken language, the output mode, and optional cleanup.
struct TranscriptionPane: View {
  var body: some View {
    Form {
      APIKeySection()
      ForEach(CatalogSection.sections(for: .transcription)) { section in
        if section.title == "Output" {
          OutputModeSection()
        } else {
          Section(section.title) {
            ForEach(section.settings) { setting in SettingRow(setting: setting) }
          }
        }
      }
    }
  }
}
