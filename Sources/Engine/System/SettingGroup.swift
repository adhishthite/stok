// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

public enum SettingGroup: String, CaseIterable, Identifiable, Sendable {
  case general = "General"
  case transcription = "Transcription"
  case audio = "Audio"
  case appearance = "Appearance"
  case vocabulary = "Vocabulary"
  case privacy = "Privacy"
  case advanced = "Advanced"
  case about = "About"
  public var id: String { rawValue }
  public var symbol: String {
    switch self {
    case .general: "gearshape.fill"
    case .transcription: "waveform"
    case .audio: "mic.fill"
    case .appearance: "circle.lefthalf.filled"
    case .vocabulary: "character.book.closed.fill"
    case .privacy: "hand.raised.fill"
    case .advanced: "slider.horizontal.3"
    case .about: "info"
    }
  }
}
