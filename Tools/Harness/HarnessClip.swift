// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One entry of build/harness/clips/manifest.json, written by Scripts/harness_clips.py.
struct HarnessClip: Decodable {
  let clipId: String
  let phraseId: String
  let text: String
  /// ISO 639-1 code of the phrase, for example "en" or "hi".
  let language: String
  /// The BCP-47 code the clip was rendered in, for example "en-IN".
  let languageCode: String
  let codeSwitch: Bool
  let ttsModel: String
  let voice: String
  let style: String
  /// Bulbul speaking pace the clip was rendered at (1.0 is normal).
  let pace: Double
  let durationS: Double
  let speechOnsetS: Double
  let speechOffsetS: Double
  let validationWer: Double

  struct Manifest: Decodable { let clips: [HarnessClip] }

  static func load(directory: URL) throws -> [HarnessClip] {
    let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Manifest.self, from: data).clips.filter {
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("\($0.clipId).wav").path)
    }
  }
}
