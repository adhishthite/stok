// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct UpdateSection: View {
  @Environment(DictationStore.self) private var store
  var body: some View {
    @Bindable var updates = store.updates
    Section {
      LabeledContent("Version", value: BuildIdentity.version)
      if updates.configured {
        // Hidden, not disabled, in a build without an update feed: there is nothing to check.
        Button("Check for Updates…") { store.updates.check() }.disabled(!store.updates.canCheck)
        // No SettingCatalog entry: Sparkle owns this preference and persists it
        // itself, so a second store of truth would only drift.
        Toggle("Check for updates automatically", isOn: $updates.automaticChecks)
      } else {
        Text("Updates are unavailable in this build.").font(.caption)
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("Updates")
    }
  }
}
