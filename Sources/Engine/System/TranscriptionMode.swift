// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

/// What Saaras returns for the words you speak: the `mode` field on the REST request and the
/// realtime socket. Every mode was verified live with saaras:v4 on both endpoints on
/// 2026-10-07. The examples are the actual outputs for one Hindi clip that says
/// "मेरी मीटिंग तीन बजे है".
public enum TranscriptionMode: String, CaseIterable, Sendable {
  case transcribe
  case codemix
  case translit
  case verbatim
  case translate

  /// The setting's default and the fallback for an unknown stored value.
  public static let standard = TranscriptionMode.transcribe

  public var title: String {
    switch self {
    case .transcribe: "Native script"
    case .codemix: "Mixed script"
    case .translit: "Roman script"
    case .verbatim: "Word for word"
    case .translate: "Translate to English"
    }
  }

  public var summary: String {
    switch self {
    case .transcribe: "Your language in its own script, with digits and punctuation."
    case .codemix: "English words stay in English. Indian-language words use their own script."
    case .translit: "Everything in Latin letters, as it sounds."
    case .verbatim: "Exactly as spoken. Numbers stay as words and no punctuation is added."
    case .translate: "Speak any supported language. Stok pastes English."
    }
  }

  public var example: String {
    switch self {
    case .transcribe: "मेरी मीटिंग 3 बजे है।"
    case .codemix: "मेरी meeting 3 बजे है।"
    case .translit: "Meri meeting teen baje hai."
    case .verbatim: "मेरी मीटिंग तीन बजे है"
    case .translate: "My meeting is at 3:00."
    }
  }
}
