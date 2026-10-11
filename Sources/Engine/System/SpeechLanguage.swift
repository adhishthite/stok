// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

/// A spoken language Saaras v4 recognizes, with the code each endpoint expects. The table
/// and both code spellings were verified live on 2026-10-07: the REST endpoint accepts only
/// `od-IN` for Odia and the realtime socket accepts only `or-IN`; every other code is the same.
public struct SpeechLanguage: Identifiable, Sendable, Equatable {
  /// Stok's stored value for the language: the realtime spelling.
  public let code: String
  public let name: String
  /// The language's own name in its own script, shown beside the English name.
  public let nativeName: String
  public var id: String { code }

  /// The stored value that asks the service to detect the language.
  public static let automatic = "auto"

  public static let all: [SpeechLanguage] = [
    SpeechLanguage(code: "en-IN", name: "English", nativeName: "English"),
    SpeechLanguage(code: "hi-IN", name: "Hindi", nativeName: "हिन्दी"),
    SpeechLanguage(code: "bn-IN", name: "Bengali", nativeName: "বাংলা"),
    SpeechLanguage(code: "mr-IN", name: "Marathi", nativeName: "मराठी"),
    SpeechLanguage(code: "te-IN", name: "Telugu", nativeName: "తెలుగు"),
    SpeechLanguage(code: "ta-IN", name: "Tamil", nativeName: "தமிழ்"),
    SpeechLanguage(code: "gu-IN", name: "Gujarati", nativeName: "ગુજરાતી"),
    SpeechLanguage(code: "kn-IN", name: "Kannada", nativeName: "ಕನ್ನಡ"),
    SpeechLanguage(code: "ml-IN", name: "Malayalam", nativeName: "മലയാളം"),
    SpeechLanguage(code: "or-IN", name: "Odia", nativeName: "ଓଡ଼ିଆ"),
    SpeechLanguage(code: "pa-IN", name: "Punjabi", nativeName: "ਪੰਜਾਬੀ"),
    SpeechLanguage(code: "as-IN", name: "Assamese", nativeName: "অসমীয়া"),
    SpeechLanguage(code: "ur-IN", name: "Urdu", nativeName: "اردو"),
    SpeechLanguage(code: "ne-IN", name: "Nepali", nativeName: "नेपाली"),
    SpeechLanguage(code: "kok-IN", name: "Konkani", nativeName: "कोंकणी"),
    SpeechLanguage(code: "mai-IN", name: "Maithili", nativeName: "मैथिली"),
    SpeechLanguage(code: "doi-IN", name: "Dogri", nativeName: "डोगरी"),
    SpeechLanguage(code: "brx-IN", name: "Bodo", nativeName: "बड़ो"),
    SpeechLanguage(code: "sa-IN", name: "Sanskrit", nativeName: "संस्कृतम्"),
    SpeechLanguage(code: "ks-IN", name: "Kashmiri", nativeName: "کٲشُر"),
    SpeechLanguage(code: "sd-IN", name: "Sindhi", nativeName: "سنڌي"),
    SpeechLanguage(code: "sat-IN", name: "Santali", nativeName: "ᱥᱟᱱᱛᱟᱲᱤ"),
    SpeechLanguage(code: "mni-IN", name: "Manipuri", nativeName: "ꯃꯩꯇꯩꯂꯣꯟ"),
  ]

  /// Codes the setting accepts, automatic detection first.
  public static let codes: [String] = [automatic] + all.map(\.code)

  public static func named(_ code: String) -> SpeechLanguage? {
    all.first { $0.code.lowercased() == code.lowercased() }
  }

  /// The setting's label for a stored code.
  public static func label(for code: String) -> String {
    guard let language = named(code) else { return "Detect automatically" }
    return language.name == language.nativeName
      ? language.name : "\(language.name) · \(language.nativeName)"
  }

  /// The realtime socket's spelling: the stored code, or `auto`.
  public static func realtimeCode(for code: String) -> String {
    named(code)?.code ?? automatic
  }

  /// The REST spelling: nil asks REST to detect the language, and Odia is `od-IN` there.
  public static func restCode(for code: String) -> String? {
    guard let language = named(code) else { return nil }
    return language.code == "or-IN" ? "od-IN" : language.code
  }
}
