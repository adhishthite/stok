// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

public enum SettingUnit: Sendable {
  case seconds
  case milliseconds
  case days
  case decibels
  case wordsPerMinute

  /// Short label shown beside the value field.
  public var label: String {
    switch self {
    case .seconds: "s"
    case .milliseconds: "ms"
    case .days: "days"
    case .decibels: "dBFS"
    case .wordsPerMinute: "wpm"
    }
  }

  /// Fraction digits shown for decimal values in this unit.
  public var fractionDigits: ClosedRange<Int> {
    switch self {
    case .seconds, .decibels: 0...1
    case .milliseconds, .days, .wordsPerMinute: 0...0
    }
  }
}
