// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum SettingCatalog {
  public static let all: [SettingDefinition] = [
    SettingDefinition(
      key: "HOTKEY", title: "Dictation shortcut",
      help: "The key you hold to dictate.",
      group: .general, section: "Shortcut",
      kind: .choice([
        "fn", "right_option", "left_option", "right_control", "left_control", "right_cmd",
        "left_cmd", "f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20",
      ]), defaultValue: "fn"
    ) { config, value in
      config.hotkey = value.lowercased()
    },
    SettingDefinition(
      key: "HOTKEY_MODE", title: "Shortcut behavior",
      help: "Hold to speak, or press once to start and again to finish.", group: .general,
      section: "Shortcut",
      kind: .choice(["push_to_talk", "toggle"]), defaultValue: "push_to_talk"
    ) { config, value in
      config.hotkeyMode = value.lowercased()
    },
    SettingDefinition(
      key: "HOLD_TO_LOCK", title: "Hold to lock",
      help: "Seconds before a held shortcut locks recording. Zero disables it.", group: .general,
      section: "Shortcut",
      kind: .decimal(0...60), unit: .seconds,
      enabledWhen: .equals("HOTKEY_MODE", "push_to_talk"), defaultValue: "15.0"
    ) { config, value in
      if let s = Double(value) { config.holdToLockSec = min(60.0, max(0.0, s)) }
    },
    SettingDefinition(
      key: "LOCK_LIMIT", title: "Locked recording limit",
      help:
        "Maximum seconds for hands-free recording. Zero removes the limit. Every dictation still ends at 10 minutes.",
      group: .general,
      section: "Shortcut",
      kind: .decimal(0...600), unit: .seconds,
      enabledWhen: .isPositive("HOLD_TO_LOCK").and(.equals("HOTKEY_MODE", "push_to_talk")),
      defaultValue: "120.0"
    ) { config, value in
      if let s = Double(value) { config.lockLimitSec = min(600.0, max(0.0, s)) }
    },
    SettingDefinition(
      key: "SOUND_FEEDBACK", title: "Play dictation sounds",
      help: "Quiet cues when recording starts, finishes, locks, or fails.", group: .general,
      section: "Sounds",
      kind: .toggle, defaultValue: "false", restartsEngine: false
    ) { config, value in
      config.soundFeedback = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "RELEASE_SOUND", title: "Play a release cue",
      help: "An additional short cue when you release the shortcut.", group: .general,
      section: "Sounds",
      kind: .toggle, enabledWhen: .isOn("SOUND_FEEDBACK"), defaultValue: "false",
      restartsEngine: false
    ) { config, value in
      config.releaseSound = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "RESTORE_CLIPBOARD", title: "Restore clipboard",
      help: "Put your previous clipboard back after pasting, unless you copied something new.",
      group: .general, section: "Pasting", kind: .toggle, defaultValue: "true"
    ) { config, value in
      config.restoreClipboard = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "TRAILING_SPACE", title: "Add a trailing space",
      help: "Keep consecutive dictations separated.", group: .general, section: "Pasting",
      kind: .toggle,
      defaultValue: "true"
    ) { config, value in
      config.trailingSpace = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "TYPING_WPM", title: "Typing speed",
      help: "Your typing speed. Stats uses it to estimate the time dictation saves.",
      group: .general, section: "Dictation stats", kind: .integer(10...200),
      unit: .wordsPerMinute, defaultValue: "40", restartsEngine: false
    ) { config, value in
      if let wpm = Int(value) { config.typingWordsPerMinute = min(200, max(10, wpm)) }
    },
    SettingDefinition(
      key: "LANGUAGE", title: "Spoken language",
      help:
        "Detect automatically recognizes any supported language. Choose one language for short dictations, where detection has little to go on.",
      group: .transcription, section: "Language",
      kind: .choice(SpeechLanguage.codes),
      optionLabels: Dictionary(
        uniqueKeysWithValues: SpeechLanguage.codes.map { ($0, SpeechLanguage.label(for: $0)) }),
      defaultValue: SpeechLanguage.automatic
    ) { config, value in
      config.language = SpeechLanguage.named(value)?.code ?? SpeechLanguage.automatic
    },
    SettingDefinition(
      key: "TRANSCRIPTION_MODE", title: "Output",
      help:
        "How Stok writes what you say: native script, mixed script, Roman script, word for word, or English.",
      group: .transcription, section: "Output",
      kind: .choice(TranscriptionMode.allCases.map(\.rawValue)),
      optionLabels: Dictionary(
        uniqueKeysWithValues: TranscriptionMode.allCases.map { ($0.rawValue, $0.title) }),
      defaultValue: TranscriptionMode.standard.rawValue
    ) { config, value in
      config.transcriptionMode = TranscriptionMode(rawValue: value.lowercased()) ?? .standard
    },
    SettingDefinition(
      key: "POST_PROCESS_ENABLED", title: "Polish dictations before pasting",
      help:
        "Send the transcript through a cleanup pass for punctuation, numbers, and lists. Adds response time and API usage.",
      group: .transcription, section: "Cleanup", kind: .toggle, defaultValue: "false"
    ) { config, value in
      config.postProcessEnabled = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "POST_PROCESS_SELECTIVE", title: "Only polish when needed",
      help:
        "Skip cleanup for short dictations without lists, spoken punctuation, or spelled-out numbers. Those paste about a quarter second sooner.",
      group: .transcription, section: "Cleanup", kind: .toggle,
      enabledWhen: .isOn("POST_PROCESS_ENABLED"), defaultValue: "true"
    ) { config, value in
      config.postProcessSelective = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "POST_PROCESS_APP_CONTEXT", title: "Adapt formatting to the app",
      help:
        "When cleanup is enabled, include the destination app name and identifier. Window titles and contents are not sent.",
      group: .transcription, section: "Cleanup", kind: .toggle,
      enabledWhen: .isOn("POST_PROCESS_ENABLED"), defaultValue: "false"
    ) { config, value in
      config.postProcessAppContext = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "INPUT_DEVICE", title: "Microphone",
      help:
        "System Default follows your Mac’s sound settings. Automatic uses the built-in microphone with the lid open and an external microphone with it closed.",
      group: .audio, section: "Microphone", kind: .microphone, defaultValue: ""
    ) { config, value in
      config.inputDevice = value
    },
    SettingDefinition(
      key: "KEEP_MICROPHONE_WARM", title: "Keep microphone ready",
      help:
        "Keep capturing between dictations for pre-roll. macOS will show microphone use while idle.",
      group: .audio, section: "Microphone", kind: .toggle, defaultValue: "false"
    ) { config, value in
      config.keepMicrophoneWarm = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "MIC_IDLE_TIMEOUT", title: "Release an idle microphone",
      help:
        "Seconds before releasing warm capture. Zero keeps it open. Applies only when “Keep microphone ready” is on.",
      group: .audio, section: "Microphone", kind: .integer(0...7200), unit: .seconds,
      enabledWhen: .isOn("KEEP_MICROPHONE_WARM"), defaultValue: "300"
    ) { config, value in
      if let sec = Int(value) { config.micIdleTimeoutSec = min(7200, max(0, sec)) }
    },
    SettingDefinition(
      key: "DUCK_AUDIO", title: "Lower other audio while dictating",
      help: "Restore the volume after capture. Your manual volume changes take priority.",
      group: .audio, section: "Other audio", kind: .toggle, defaultValue: "false"
    ) { config, value in
      config.duckAudio = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "DUCK_FRACTION", title: "Background volume fraction",
      help: "How much output volume to keep while dictating, from zero to one.", group: .audio,
      section: "Other audio",
      kind: .decimal(0...1), enabledWhen: .isOn("DUCK_AUDIO"), defaultValue: "0.2"
    ) { config, value in
      if let f = Double(value) { config.duckFraction = min(1.0, max(0.0, f)) }
    },
    SettingDefinition(
      key: "SHOW_HUD", title: "Show dictation overlay",
      help: "A small overlay follows your dictation without taking keyboard focus.",
      group: .appearance, section: "Overlay", kind: .toggle, defaultValue: "true",
      restartsEngine: false
    ) { config, value in
      config.showHUD = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "LIVE_WORDS", title: "Show words while speaking",
      help:
        "Show words in the overlay as you speak. Off shows the text when you finish, which arrives about 65 ms sooner. Hiding dictated words on screen also turns this off.",
      group: .appearance, section: "Overlay", kind: .toggle,
      enabledWhen: .isOn("SHOW_HUD").and(.equals("PRIVACY_MODE", "false")), defaultValue: "true",
      restartsEngine: false
    ) { config, value in
      config.liveWords = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "HUD_FOLLOW_FOCUS", title: "Follow the focused display",
      help: "Show the overlay on the display where you are writing.", group: .appearance,
      section: "Overlay",
      kind: .toggle, enabledWhen: .isOn("SHOW_HUD"), defaultValue: "true", restartsEngine: false
    ) { config, value in
      config.hudFollowFocus = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "HUD_REVEAL", title: "Overlay motion",
      help: "Preview the entrance and exit before choosing.", group: .appearance,
      section: "Overlay",
      kind: .choice(["drift", "slide", "bloom", "unfurl", "morph"]), enabledWhen: .isOn("SHOW_HUD"),
      defaultValue: "drift", restartsEngine: false
    ) { config, value in
      if ["slide", "bloom", "drift", "unfurl", "morph"].contains(value.lowercased()) {
        config.hudRevealStyle = value.lowercased()
      }
    },
    SettingDefinition(
      key: "HUD_PARTICLES", title: "Ambient particles",
      help: "Optional particles while listening. Disabled with Reduce Motion.", group: .appearance,
      section: "Overlay",
      kind: .toggle, enabledWhen: .isOn("SHOW_HUD"), defaultValue: "false", restartsEngine: false
    ) { config, value in
      config.hudParticles = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "PRIVACY_MODE", title: "Hide dictated words on screen",
      help:
        "Hide dictated words in the overlay and menu, for example while you share your screen. History is set separately.",
      group: .privacy, section: "On screen", kind: .toggle, defaultValue: "false",
      restartsEngine: false
    ) { config, value in
      config.privacyMode = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "CUSTOM_VOCABULARY", title: "Additional terms",
      help:
        "Extra terms or wrong => right rules, separated by commas, for .env and environment setups. Settings offers to move them into the vocabulary file.",
      group: .vocabulary,
      section: "Terms",
      kind: .text, prompt: "Kubernetes, cube cuttle => kubectl", defaultValue: ""
    ) { config, value in
      config.customVocabulary = EngineConfiguration.parseVocabulary(from: value)
    },
    SettingDefinition(
      key: "CUSTOM_VOCABULARY_FILE", title: "Vocabulary file",
      help: "Edit terms and replacements in the Vocabulary window.", group: .vocabulary,
      section: "Terms",
      kind: .text, prompt: "vocabulary.txt", defaultValue: "vocabulary.txt"
    ) { config, value in
      config.customVocabularyFile = value
    },
    SettingDefinition(
      key: "ANALYZE_CONTEXT", title: "Your work and terminology",
      help: "Optional context to help vocabulary suggestions understand your domain.",
      group: .vocabulary, section: "Suggestions", kind: .text,
      prompt: "Cloud architecture and payments", defaultValue: ""
    ) { config, value in
      config.analyzeContext = value
    },
    SettingDefinition(
      key: "LEARN_CORRECTIONS", title: "Learn from typed corrections",
      help:
        "Observe word corrections after a paste. Only word pairs are stored, never the surrounding field.",
      group: .vocabulary, section: "Corrections", kind: .toggle, defaultValue: "false"
    ) { config, value in
      config.learnCorrections = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "LEARN_DELAY_MS", title: "Correction observation delay",
      help: "Milliseconds after a paste before checking for a correction.", group: .vocabulary,
      section: "Corrections",
      kind: .integer(2000...60000), unit: .milliseconds, enabledWhen: .isOn("LEARN_CORRECTIONS"),
      defaultValue: "8000"
    ) { config, value in
      if let ms = Int(value) { config.learnDelayMs = min(60000, max(2000, ms)) }
    },
    SettingDefinition(
      key: "HISTORY", title: "Save dictation history",
      help: "Store dictations locally on this Mac.", group: .privacy, section: "Local history",
      kind: .toggle,
      defaultValue: "true"
    ) { config, value in
      config.historyEnabled = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "HISTORY_RETENTION_DAYS", title: "History retention",
      help: "Days to retain history. Zero keeps it indefinitely.", group: .privacy,
      section: "Local history",
      kind: .integer(0...3650), unit: .days, defaultValue: "0", restartsEngine: false
    ) { config, value in
      if let days = Int(value) { config.historyRetentionDays = min(3650, max(0, days)) }
    },
    SettingDefinition(
      key: "STATS", title: "Track dictation stats",
      help:
        "Count words, dictations, speaking time, and time saved in a local stats database. No transcripts are stored there.",
      group: .privacy, section: "Dictation stats", kind: .toggle, defaultValue: "true",
      restartsEngine: false
    ) { config, value in
      config.statsEnabled = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "STATS_WORDS", title: "Track word usage",
      help:
        "Count how often each word is dictated for the most and least used lists. Stored as per-day counts, never as sentences.",
      group: .privacy, section: "Dictation stats", kind: .toggle, enabledWhen: .isOn("STATS"),
      defaultValue: "true", restartsEngine: false
    ) { config, value in
      config.statsWordsEnabled = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "SHARE_USAGE_METRICS", title: "Share anonymous usage metrics",
      help:
        "Off by default. Records counts, categories, and timing buckets only. Never transcripts, audio, vocabulary, or your API key. See PRIVACY.md.",
      group: .privacy, section: "Usage metrics", kind: .toggle, defaultValue: "false",
      restartsEngine: false
    ) { config, value in
      config.shareUsageMetrics = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "LIVE_MODEL", title: "Live model",
      help: "Streams while you speak. Vocabulary terms are sent only with saaras:v4.",
      group: .advanced, section: "Models", kind: .choice(["saaras:v4", "saaras:v3-realtime"]),
      optionLabels: ["saaras:v4": "saaras:v4", "saaras:v3-realtime": "saaras:v3-realtime"],
      defaultValue: "saaras:v4"
    ) { config, value in
      config.liveModel = value
    },
    SettingDefinition(
      key: "REST_MODEL", title: "Fallback model",
      help:
        "Finishes a dictation when the live connection cannot. Vocabulary terms are sent only with saaras:v4.",
      group: .advanced, section: "Models",
      kind: .choice(["saaras:v4", "saaras:v3"]),
      optionLabels: ["saaras:v4": "saaras:v4", "saaras:v3": "saaras:v3"], defaultValue: "saaras:v4"
    ) { config, value in
      config.restModel = value
    },
    SettingDefinition(
      key: "ANALYZE_MODEL", title: "Vocabulary analysis model",
      help: "Used only when you request suggestions from history.", group: .advanced,
      section: "Models", kind: .text,
      defaultValue: "sarvam-105b"
    ) { config, value in
      config.analyzeModel = value
    },
    SettingDefinition(
      key: "POST_PROCESS_MODEL", title: "Cleanup model",
      help:
        "A Sarvam chat model. The default, sarvam-105b-conversations, is the low-latency variant.",
      group: .advanced, section: "Cleanup", kind: .text, enabledWhen: .isOn("POST_PROCESS_ENABLED"),
      defaultValue: "sarvam-105b-conversations"
    ) { config, value in
      config.postProcessModel = value.trimmingCharacters(in: .whitespacesAndNewlines)
    },
    SettingDefinition(
      key: "POST_PROCESS_TIMEOUT_MS", title: "Maximum cleanup wait",
      help:
        "Milliseconds before using the original transcript. Failed cleanup never blocks delivery indefinitely.",
      group: .advanced, section: "Cleanup", kind: .integer(500...10000), unit: .milliseconds,
      enabledWhen: .isOn("POST_PROCESS_ENABLED"), defaultValue: "2500"
    ) { config, value in
      if let value = Int(value) { config.postProcessTimeoutMs = min(10000, max(500, value)) }
    },
    SettingDefinition(
      key: "ENABLE_LIVE_WEBSOCKET", title: "Stream while speaking",
      help: "Use the live connection for lower settlement latency.", group: .advanced,
      section: "Streaming",
      kind: .toggle, defaultValue: "true"
    ) { config, value in
      config.enableLiveWebSocket = (value.lowercased() == "true" || value == "1")
    },
    SettingDefinition(
      key: "REST_FALLBACK_TIMEOUT", title: "Fallback delay",
      help: "Seconds to wait before also trying the fallback route.", group: .advanced,
      section: "Streaming",
      kind: .decimal(0.1...30), unit: .seconds, defaultValue: "4.0"
    ) { config, value in
      if let t = Double(value) { config.restFallbackTimeout = t }
    },
    SettingDefinition(
      key: "CHUNK_MS", title: "Streaming frame size",
      help: "Milliseconds of audio sent in each streaming frame.", group: .advanced,
      section: "Streaming",
      // 100 ms frames are what the realtime docs stream (3200 bytes at 16 kHz). The latency
      // measurements in PERFORMANCE.md predate the Sarvam backend and need repeating.
      kind: .integer(20...500), unit: .milliseconds, defaultValue: "100"
    ) { config, value in
      if let ms = Int(value) { config.chunkMs = min(500, max(20, ms)) }
    },
    SettingDefinition(
      key: "SILENCE_FLUSH_MS", title: "Trailing silence",
      help: "Milliseconds of synthetic silence sent to help finalize the final word.",
      group: .advanced, section: "Streaming", kind: .integer(0...2000), unit: .milliseconds,
      // The 200 ms default comes from measurements on the previous backend (PERFORMANCE.md,
      // "Silence flush"); it has not been re-measured on Sarvam.
      defaultValue: "200"
    ) { config, value in
      if let ms = Int(value) { config.silenceFlushMs = min(2000, max(0, ms)) }
    },
    SettingDefinition(
      key: "PRE_ROLL_MS", title: "Pre-roll",
      help: "Milliseconds retained before pressing the shortcut when warm capture is enabled.",
      group: .advanced, section: "Capture timing", kind: .integer(0...1000), unit: .milliseconds,
      enabledWhen: .isOn("KEEP_MICROPHONE_WARM"), defaultValue: "400"
    ) { config, value in
      if let ms = Int(value) { config.preRollMs = min(1000, max(0, ms)) }
    },
    SettingDefinition(
      key: "POST_ROLL_MS", title: "Trailing quiet window",
      help: "Milliseconds of quiet needed before finishing capture.", group: .advanced,
      section: "Capture timing",
      kind: .integer(0...500), unit: .milliseconds, defaultValue: "250"
    ) { config, value in
      if let ms = Int(value) { config.postRollMs = min(500, max(0, ms)) }
    },
    SettingDefinition(
      key: "POST_ROLL_MIN_MS", title: "Minimum trailing capture",
      help: "Milliseconds recorded after release even when the room is already quiet.",
      group: .advanced, section: "Capture timing",
      // Measured 2026-09-26 (PERFORMANCE.md, "Trailing-capture floor"): the floor binds on
      // turns that were already quiet before release; there it is the whole wait. 30 ms
      // still covers the one hardware buffer in flight at key-up (1024 frames, about 21 ms).
      kind: .integer(0...250), unit: .milliseconds, defaultValue: "30"
    ) { config, value in
      if let ms = Int(value) { config.postRollMinMs = min(250, max(0, ms)) }
    },
    SettingDefinition(
      key: "POST_ROLL_MAX_MS", title: "Maximum trailing capture",
      help: "Milliseconds to wait for speech after release, at most.", group: .advanced,
      section: "Capture timing",
      kind: .integer(0...5000), unit: .milliseconds, defaultValue: "1500"
    ) { config, value in
      if let ms = Int(value) { config.postRollMaxMs = min(5000, max(0, ms)) }
    },
    SettingDefinition(
      key: "TRAIL_SILENCE_DB", title: "Quiet threshold",
      help: "Audio below this level in dBFS counts as quiet.", group: .advanced,
      section: "Capture timing",
      kind: .decimal((-80)...(-10)), unit: .decibels, defaultValue: "-40.0"
    ) { config, value in
      if let db = Double(value) { config.trailSilenceDb = min(-10.0, max(-80.0, db)) }
    },
    SettingDefinition(
      key: "QUIET_MARGIN_DB", title: "Noisy-room margin",
      help:
        "In a noisy room, audio this many dB above the room's own level still counts as quiet. 0 uses the quiet threshold alone.",
      group: .advanced, section: "Capture timing",
      kind: .decimal(0...20), unit: .decibels, defaultValue: "8"
    ) { config, value in
      if let db = Double(value) { config.quietMarginDb = min(20.0, max(0.0, db)) }
    },
    SettingDefinition(
      key: "HISTORY_DB", title: "History database path",
      help: "Empty uses Stok’s Application Support folder.", group: .advanced, section: "Storage",
      kind: .text, prompt: "Application Support folder",
      defaultValue: ""
    ) { config, value in
      config.historyDbPath = value
    },
    SettingDefinition(
      key: "LOG_LEVEL", title: "Diagnostic detail",
      help: "Normal records essential events. Verbose includes additional engineering detail.",
      group: .advanced, section: "Diagnostics", kind: .choice(["normal", "verbose"]),
      defaultValue: "normal", restartsEngine: false
    ) { config, value in
      config.logLevel = value.lowercased()
    },
    SettingDefinition(
      key: "EXPERIMENT_TAG", title: "Experiment label",
      help: "Stored with each dictation so measurements can be grouped. Leave empty normally.",
      group: .advanced, section: "Diagnostics", kind: .text, defaultValue: "",
      restartsEngine: false
    ) { config, value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      config.experimentTag = trimmed.isEmpty ? nil : String(trimmed.prefix(64))
    },
  ]
}
