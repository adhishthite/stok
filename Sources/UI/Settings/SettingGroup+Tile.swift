// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import StokEngine

extension SettingGroup {
  /// The sidebar tile colour for each pane.
  var tileTint: TileTint {
    switch self {
    case .general: .ink
    case .transcription: .indigo
    case .audio: .saffron
    case .appearance: .periwinkle
    case .vocabulary: .pink
    case .privacy: .green
    case .advanced: .ink
    case .about: .deepIndigo
    }
  }
}
