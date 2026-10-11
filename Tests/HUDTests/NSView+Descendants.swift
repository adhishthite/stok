// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit

extension NSView {
  /// Every view below this one, depth first. Render tests use it to reach HUD subviews.
  var descendants: [NSView] {
    subviews.flatMap { [$0] + $0.descendants }
  }
}
