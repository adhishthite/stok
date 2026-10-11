// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import QuartzCore

/// The display link's target. A display link retains its target, so pointing it at the HUD
/// would keep a released HUD alive and ticking; this proxy holds the HUD weakly and, once
/// the HUD is gone, invalidates the link on its next frame.
final class DisplayLinkTarget: NSObject {
  private weak var hud: FloatingHUD?

  init(hud: FloatingHUD) {
    self.hud = hud
  }

  @objc func frame(_ link: CADisplayLink) {
    guard let hud else {
      link.invalidate()
      return
    }
    hud.displayLinkFired()
  }
}
