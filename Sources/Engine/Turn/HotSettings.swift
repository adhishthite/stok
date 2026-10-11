// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The subset of EngineConfiguration that a running DictationEngine re-reads per use
/// instead of at construction, so Settings changes to these keys apply without a restart.
public struct HotSettings: Sendable {
  public var soundFeedback: Bool
  public var releaseSound: Bool
  public var hudFollowFocus: Bool
  public var privacyMode: Bool
  public var experimentTag: String?

  public init(_ config: EngineConfiguration) {
    soundFeedback = config.soundFeedback
    releaseSound = config.releaseSound
    hudFollowFocus = config.hudFollowFocus
    privacyMode = config.privacyMode
    experimentTag = config.experimentTag
  }
}
