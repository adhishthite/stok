// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct PostProcessingMetrics: Sendable {
  public var status: String
  public var model: String? = nil
  public var latencyMs: Double? = nil
  public var inputTokens: Int? = nil
  public var outputTokens: Int? = nil
  public var thinkingTokens: Int? = nil
  public var costUSD: Double? = nil
  public var errorCode: String? = nil
  public var appContextUsed = false

  public static let off = PostProcessingMetrics(status: "off", costUSD: 0)
  public static let notNeeded = PostProcessingMetrics(status: "not_needed", costUSD: 0)

  public var displayStatus: String {
    switch status {
    case "off": "Off"
    case "not_needed": "Not needed; original used"
    case "completed": "Applied"
    case "timed_out": "Timed out; original used"
    case "skipped": "Skipped; original used"
    default: "Failed; original used"
    }
  }

  public var failureDescription: String? {
    switch errorCode {
    case "timeout": "Cleanup reached its time limit."
    case "input_limit": "The dictation is too long for the cleanup pass."
    case "invalid_configuration", "http_400": "Review the cleanup model in Settings."
    case "http_401", "http_403": "Review the Sarvam API key and model access."
    case "http_404": "The cleanup model is unavailable."
    case "http_429": "Sarvam is limiting requests."
    case "network": "The cleanup request could not connect."
    case "truncated": "The cleanup answer was cut short."
    case "invalid_response", "empty_response": "Sarvam returned an incomplete or unusable result."
    case nil: nil
    default: "Sarvam could not complete cleanup."
    }
  }
}
