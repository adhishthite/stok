// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import StokEngine
import SwiftUI

/// The privacy step of setup: what leaves the Mac, and the metrics choice, off by default.
struct SetupPrivacySection: View {
  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        point("waveform", "Audio goes to Sarvam only while you dictate. Stok keeps no audio.")
        point("internaldrive.fill", "History stays in a local database you control.")
        point("key.fill", "Your API key stays in the macOS Keychain.")
      }
      .fixedSize(horizontal: false, vertical: true)
      if let setting = SettingCatalog.all.first(where: { $0.key == "SHARE_USAGE_METRICS" }) {
        SettingRow(setting: setting, icon: IconTile(symbol: "chart.bar.fill", tint: .green))
      }
    } header: {
      Text("Privacy")
    } footer: {
      HStack {
        Text("Change this any time in Settings > Privacy.")
        Spacer()
        Button("Privacy details") { PrivacyDocument.open() }.controlSize(.small)
      }
    }
  }

  private func point(_ symbol: String, _ text: String) -> some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: symbol).foregroundStyle(StokColor.green).frame(width: 18)
    }
  }
}
