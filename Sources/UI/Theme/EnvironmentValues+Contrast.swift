// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

extension EnvironmentValues {
  /// Forces the Increase Contrast treatment. SwiftUI's `colorSchemeContrast` follows the
  /// system setting, which a render test cannot change; views honor either one.
  @Entry var forceIncreasedContrast = false
}
