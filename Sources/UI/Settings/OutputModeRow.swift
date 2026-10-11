// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import StokEngine
import SwiftUI

/// One selectable output mode: a radio mark, the name and summary, and its example.
struct OutputModeRow: View {
  let mode: TranscriptionMode
  let selected: Bool
  let choose: () -> Void
  @Environment(\.colorSchemeContrast) private var systemContrast
  @Environment(\.forceIncreasedContrast) private var forcedContrast
  private var increased: Bool { systemContrast == .increased || forcedContrast }

  var body: some View {
    Button(action: choose) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(selected ? Color.accentColor : (increased ? .primary : .secondary))
          .imageScale(.medium)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(mode.title)
          Text(mode.summary).font(.caption)
            .foregroundStyle(increased ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 12)
        Text(mode.example)
          .font(.callout)
          .foregroundStyle(.primary)
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(StokColor.chipIndigo, in: .rect(cornerRadius: 6))
          .overlay {
            RoundedRectangle(cornerRadius: 6)
              .strokeBorder(
                selected ? Color.accentColor : (increased ? Color.primary.opacity(0.6) : .clear),
                lineWidth: selected ? 1.5 : 1)
          }
          .lineLimit(1)
          .fixedSize()
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(mode.title). \(mode.summary) Example: \(mode.example)")
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }

}
