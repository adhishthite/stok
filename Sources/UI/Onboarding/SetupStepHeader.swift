// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A numbered setup step with its state. The state is a word and a symbol, not colour alone.
struct SetupStepHeader: View {
  let number: Int
  let title: String
  /// nil for a step with no completion to report.
  var done: Bool?
  @Environment(\.colorSchemeContrast) private var systemContrast
  @Environment(\.forceIncreasedContrast) private var forcedContrast
  private var increased: Bool { systemContrast == .increased || forcedContrast }

  var body: some View {
    HStack(spacing: 8) {
      Text("\(number)")
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(StokColor.onInk)
        .frame(width: 18, height: 18)
        .background(StokColor.ink, in: .circle)
        .accessibilityHidden(true)
      Text(title).font(.headline).foregroundStyle(.primary)
      Spacer()
      if let done {
        Label(
          done ? "Done" : "To do", systemImage: done ? "checkmark.circle.fill" : "circle.dashed"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(done ? StokColor.green : StokColor.saffron)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(done ? StokColor.chipGreen : StokColor.chipSaffron, in: .capsule)
        .overlay {
          if increased {
            Capsule().strokeBorder(done ? StokColor.green : StokColor.saffron, lineWidth: 1)
          }
        }
        .contentTransition(.symbolEffect(.replace))
      }
    }
    .textCase(nil)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Step \(number), \(title)\(done.map { $0 ? ", done" : ", to do" } ?? "")")
    .accessibilityAddTraits(.isHeader)
  }
}
