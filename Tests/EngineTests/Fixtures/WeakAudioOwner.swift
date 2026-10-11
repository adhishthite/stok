// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

@testable import StokEngine

@MainActor
final class WeakAudioOwner: Sendable {
  weak var value: AudioCaptureEngine?
}
