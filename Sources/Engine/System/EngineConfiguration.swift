// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import AppKit
import AudioToolbox
import Carbon
import CoreAudio
import Foundation
import IOKit
import Network
import SQLite3

public struct EngineConfiguration: Sendable {
  public init() {}
  public var sarvamApiKey: String = ""
  public var restModel: String = "saaras:v4"
  public var liveModel: String = "saaras:v4"
  public var transcriptionMode: TranscriptionMode = .standard
  public var postProcessEnabled = false
  public var postProcessAppContext = false
  public var postProcessSelective = true
  public var postProcessModel = "sarvam-105b-conversations"
  public var postProcessTimeoutMs = 2500
  // Live words in the overlay need partial transcripts (stream_type "fast"). Without them the
  // service sends finals only ("simulated"), which settle sooner.
  public var liveWords = true
  /// The realtime stream_type: partials only when they would be shown.
  public var liveStreamType: String {
    SarvamAPI.streamType(liveWords: liveWords, privacyMode: privacyMode)
  }
  // The spoken language: a code from SpeechLanguage.all, or "auto" for detection. The
  // realtime socket and REST spell Odia differently; SpeechLanguage maps each.
  public var language: String = SpeechLanguage.automatic
  public var customVocabulary: [String] = []
  /// The keyterms sent with recognition requests: the first terms that fit the service's
  /// limits (SarvamAPI.maxKeyterms terms of at most SarvamAPI.maxKeytermLength characters).
  /// `customVocabulary` itself stays complete for the analyzer and correction watcher.
  public var recognitionVocabulary: [String] { SarvamAPI.keyterms(from: customVocabulary) }
  /// Terms that recognition requests leave out: past the term limit, or too long.
  public var customVocabularyDropped: Int {
    max(0, customVocabulary.count - recognitionVocabulary.count)
  }
  public var customVocabularyFile: String = ""
  var replacementRules: [ReplacementRule] = []
  // Sorted + regex-compiled form of replacementRules, built once at load (the raw rules
  // stay around for display and the analyzer).
  var compiledReplacementRules: [ReplacementEngine.CompiledRule] = []
  public var hotkey: String = "fn"
  public var hotkeyMode: String = "push_to_talk"  // "push_to_talk" or "toggle"
  /// Human label for the shortcut key, shared by the HUD, the menu panel, and messages.
  public var shortcutLabel: String {
    hotkey == "fn" ? "Fn" : hotkey.replacingOccurrences(of: "_", with: " ").capitalized
  }
  // Hold-to-lock: a hold this long (seconds) locks the turn - the release becomes a
  // non-event and the next press finishes. 0 disables; ignored in toggle mode.
  public var holdToLockSec: Double = 15.0
  // Seconds a locked turn may run before it finishes on its own (a forgotten open mic).
  public var lockLimitSec: Double = 120.0
  public var soundFeedback: Bool = true
  // Soft tick at key release - acknowledges the hold ended while the transcript settles
  // (there can be seconds of silence before the commit earcon on a slow REST fallback).
  public var releaseSound: Bool = true
  public var showHUD: Bool = true
  // Put the HUD on the display holding the frontmost app's focused window (pointer as
  // fallback) rather than always on the menu-bar/notch display. Resolved once per key-down.
  public var hudFollowFocus: Bool = true
  // HUD pill entrance animation: "slide" (shipped default), "bloom", "drift", "unfurl",
  // "morph" (Dynamic Island membrane; needs a physical notch, else falls back to slide).
  public var hudRevealStyle: String = "slide"
  // Ambient particle motes under the notch while listening (CAEmitterLayer, GPU-composited;
  // skipped under Reduce Motion).
  public var hudParticles: Bool = true
  // Screen-share privacy: the pill shows one state word and never a dictated word (the
  // aura tint tells success from failure) and the terminal prints only a char count. Paste still happens; the history
  // DB still records locally.
  public var privacyMode: Bool = false
  // Duck the system output while recording so music/video on speakers doesn't bleed into
  // the mic (hurting accuracy). Opt-in: changing the output
  // volume uninvited is surprising.
  public var duckAudio: Bool = false
  // Fraction of the current output volume kept while ducked (0.2 = drop to 20%).
  public var duckFraction: Double = 0.2
  public var enableLiveWebSocket: Bool = true
  public var restFallbackTimeout: Double = 4.0
  public var preRollMs: Int = 400
  // Capture device: empty = system default input; "auto" = built-in mic while the lid is
  // open, an external one while closed (re-evaluated on lid flips); otherwise an exact
  // CoreAudio UID or a case-insensitive name substring ("studio" -> "Studio Display
  // Microphone"); see --list-inputs. Unmatched falls back to the default with a warning.
  public var inputDevice: String = ""
  // 250ms default: people release the key while the last word is still leaving their mouth;
  // audio keeps streaming during the grace period, so the only cost is commit latency.
  public var postRollMs: Int = 250
  // Adaptive trailing capture: after key release, audio keeps streaming while speech energy
  // is still present; the turn commits once the mic has been quiet for postRollMs
  // continuously, hard-capped at postRollMaxMs. Set equal to postRollMs (or 0) to disable
  // adaptation and get the old fixed post-roll.
  public var postRollMaxMs: Int = 1500
  // Capture kept after release even when the quiet window was already banked before it:
  // a soft final sound can sit under the threshold, and a hardware buffer may still be in
  // flight at key-up. Every turn pays it, so it is a per-turn latency floor.
  public var postRollMinMs: Int = 30
  // Adaptive quiet line for the trailing-capture wait: in a room louder than
  // trailSilenceDb, audio up to this many dB above the turn's measured room floor still
  // counts as quiet, so room tone cannot hold every turn to postRollMaxMs. 0 disables it.
  public var quietMarginDb: Double = 8
  // RMS dBFS below which the mic is considered quiet (speech typically -30 to -15, room
  // noise -50 to -60 on this meter).
  public var trailSilenceDb: Double = -40.0
  // Streaming chunk size; the realtime docs stream ~100 ms frames (3200 bytes).
  public var chunkMs: Int = 100
  // Synthetic trailing silence appended after key-up so the speech encoder's lookahead
  // window can finalize the last word. 0 disables it entirely.
  public var silenceFlushMs: Int = 200
  // Release the mic (status-bar indicator off) after this many seconds without a dictation;
  // the next key-down re-arms it. 0 = keep the mic always on (lowest latency, indicator lit).
  public var keepMicrophoneWarm: Bool = false
  public var micIdleTimeoutSec: Int = 300
  public var restoreClipboard: Bool = true
  // Append one trailing space to the injected/copied payload so back-to-back dictations
  // don't fuse ("...are you?Are you..."). Logs, HUD, and history keep the unpadded text.
  public var trailingSpace: Bool = true
  public var logLevel: String = "verbose"
  // Local dictation history (SQLite). Every turn - success, empty, or error - becomes one row
  // so usage/latency/cost can be analyzed later. Plaintext on disk; disable with HISTORY=false.
  public var historyEnabled: Bool = true
  public var historyRetentionDays: Int = 0
  // Opt-in usage metrics: counts, categories, and buckets only. See PRIVACY.md.
  public var shareUsageMetrics: Bool = false
  public var historyDbPath: String = ""  // empty = ~/Library/Application Support/Stok/history.db
  // Local dictation stats: counts, timing, and word frequencies in stats.db, never
  // transcripts. Separate from history so totals survive history settings. See PRIVACY.md.
  public var statsEnabled: Bool = true
  public var statsWordsEnabled: Bool = true
  // The typing speed the stats dashboard assumes when it estimates time saved.
  public var typingWordsPerMinute: Int = 40
  // Source revision from Stok's built bundle, including a dirty-worktree marker.
  // Assigned by SettingsStore; never a user preference or imported .env setting.
  public var buildId: String = ""
  // Analyzer-only knobs. Analysis is rare and offline, so it uses the reasoning chat model;
  // empty falls back to the same default.
  public static let defaultAnalyzeModel = "sarvam-105b"
  public var analyzeModel: String = Self.defaultAnalyzeModel
  // Free-text persona for the analysis prompt ("solutions architect at ...; daily terms:
  // GCP services, AI products") so the model can judge what a garbled phrase plausibly
  // meant. Also settable as "# context: ..." lines in the vocabulary file; the knob wins.
  public var analyzeContext: String = ""
  // Opt-in typed-correction capture: after a paste, read the focused field back once via
  // the Accessibility API and record gated single-word edits ("cloud" -> "Claude") to the
  // corrections table for `make analyze`. Off by default: it reads field content (only the
  // changed word pairs are ever stored or shown).
  public var learnCorrections: Bool = false
  // paste-to-read-back delay; the user needs time to notice and fix
  public var learnDelayMs: Int = 8000
  // Free-text label stored with every history row so measurements from a
  // deliberate A/B session can be grouped later without timestamp archaeology. Hot: no
  // engine restart needed. nil (not empty string) when unset, so old rows and rows with no
  // label both read NULL. Trimmed and capped to 64 characters at parse time (SettingCatalog).
  public var experimentTag: String? = nil

  static func parseVocabulary(from text: String) -> [String] {
    var items: [String] = []
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
      if let data = trimmed.data(using: .utf8),
        let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
      {
        return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      }
    }

    let lines = text.components(separatedBy: .newlines)
    for line in lines {
      let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if cleanLine.isEmpty || cleanLine.hasPrefix("#") { continue }

      if cleanLine.contains(",") {
        let parts = cleanLine.components(separatedBy: ",")
        for part in parts {
          let cleaned = part.trimmingCharacters(in: .whitespacesAndNewlines)
          if !cleaned.isEmpty && !cleaned.hasPrefix("#") {
            items.append(cleaned)
          }
        }
      } else {
        items.append(cleanLine)
      }
    }
    return items
  }

  // "# context: ..." lines in the vocabulary file describe the dictating user for the
  // analyzer prompt. parseVocabulary already skips them as comments, so the directive
  // rides in the same file without affecting recognition. Multiple lines join with a space.
  static func parseContextDirective(from text: String) -> String {
    var parts: [String] = []
    for line in text.components(separatedBy: .newlines) {
      let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
      let lower = cleaned.lowercased()
      guard lower.hasPrefix("# context:") || lower.hasPrefix("#context:") else { continue }
      guard let colon = cleaned.firstIndex(of: ":") else { continue }
      let value = String(cleaned[cleaned.index(after: colon)...]).trimmingCharacters(
        in: .whitespaces)
      if !value.isEmpty { parts.append(value) }
    }
    return parts.joined(separator: " ")
  }

  // Splits raw vocabulary items into plain boost terms and "wrong => right" replacement
  // rules (first "=>" wins; either side empty after trim discards the item). Rules are
  // deduped by lowercased "wrong", first occurrence wins - matching the boost-term dedupe.
  static func splitVocabularyItems(_ items: [String]) -> (vocab: [String], rules: [ReplacementRule])
  {
    var vocab: [String] = []
    var rules: [ReplacementRule] = []
    var seenWrong = Set<String>()
    for item in items {
      guard let arrow = item.range(of: "=>") else {
        vocab.append(item)
        continue
      }
      let wrong = item[item.startIndex..<arrow.lowerBound].trimmingCharacters(
        in: .whitespacesAndNewlines)
      let right = item[arrow.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
      if wrong.isEmpty || right.isEmpty { continue }
      let key = wrong.lowercased()
      if seenWrong.contains(key) { continue }
      seenWrong.insert(key)
      rules.append(ReplacementRule(wrong: wrong, right: right))
    }
    return (vocab, rules)
  }

  /// The recognition terms and replacement rules from the Additional terms setting and the
  /// vocabulary file, in the order recognition sees them: Additional terms first, then the
  /// file, then each rule's right side; deduplicated ignoring case. Pure: no global state.
  static func vocabulary(additional: [String], fileText: String?) -> (
    terms: [String], rules: [ReplacementRule]
  ) {
    var items = additional
    if let fileText { items.append(contentsOf: parseVocabulary(from: fileText)) }
    let split = splitVocabularyItems(items)
    var seen = Set<String>()
    let terms = (split.vocab + split.rules.map { $0.right }).compactMap { value -> String? in
      let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { return nil }
      return term
    }
    return (terms, split.rules)
  }

  /// The recognition terms for a draft vocabulary file, with the Additional terms setting's
  /// raw value. Used to preview what a dictation would send before the file is saved.
  public static func vocabularyTerms(additionalSetting: String, fileText: String) -> [String] {
    vocabulary(additional: parseVocabulary(from: additionalSetting), fileText: fileText).terms
  }

  public static func load(values: [String: String], vocabularyText: String? = nil)
    -> EngineConfiguration
  {
    var config = EngineConfiguration()
    config.sarvamApiKey = values["SARVAM_API_KEY"] ?? ""
    for setting in SettingCatalog.all {
      setting.apply(&config, values[setting.key] ?? setting.defaultValue)
    }
    if let vocabularyText, config.analyzeContext.isEmpty {
      config.analyzeContext = parseContextDirective(from: vocabularyText)
    }
    let vocabulary = vocabulary(
      additional: config.customVocabulary, fileText: vocabularyText)
    config.replacementRules = vocabulary.rules
    config.compiledReplacementRules = ReplacementEngine.compile(vocabulary.rules)
    config.customVocabulary = vocabulary.terms
    Log.isVerbose = config.logLevel == "verbose"
    return config
  }
}
