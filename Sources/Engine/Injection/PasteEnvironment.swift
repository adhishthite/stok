// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

/// What the paste path asks of the system, gathered so tests can supply each answer without
/// Accessibility, a real clipboard, or a synthesized Cmd-V. The app always uses `live`, whose
/// closures are exactly the calls the paste path makes inline: the frontmost-app read stays a
/// DispatchQueue.main.sync, because Apple documents neither NSWorkspace.frontmostApplication
/// nor the Accessibility focused-app query as safe and current off the main thread.
struct PasteEnvironment {
  /// The frontmost application, as a process id and display name.
  struct App: Equatable {
    let pid: pid_t
    let name: String?
  }

  var isAccessibilityTrusted: () -> Bool
  var isSecureInputActive: () -> Bool
  var frontmostApp: () -> App?
  var awaitPreparedClipboard: (_ completion: @escaping (Bool) -> Void) -> Void
  var inject:
    (
      _ text: String, _ restorePreviousClipboard: Bool, _ completionSound: Bool,
      _ appendSpace: Bool, _ shouldDispatch: () -> Bool
    ) -> TextInjector.InjectionResult
  var copyOnly: (_ text: String, _ appendSpace: Bool) -> Bool

  static let live = PasteEnvironment(
    isAccessibilityTrusted: { AXIsProcessTrusted() },
    isSecureInputActive: { SecureInputMonitor.isActive },
    frontmostApp: {
      var app: App?
      DispatchQueue.main.sync {
        if let front = NSWorkspace.shared.frontmostApplication {
          app = App(pid: front.processIdentifier, name: front.localizedName)
        }
      }
      return app
    },
    awaitPreparedClipboard: { completion in
      TextInjector.awaitPreparedClipboard(completion: completion)
    },
    inject: { text, restore, sound, space, shouldDispatch in
      TextInjector.inject(
        text: text, restorePreviousClipboard: restore, completionSound: sound,
        appendSpace: space, shouldDispatch: shouldDispatch)
    },
    copyOnly: { text, space in TextInjector.copyOnly(text: text, appendSpace: space) })
}
