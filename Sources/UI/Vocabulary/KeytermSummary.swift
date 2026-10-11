// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import StokEngine
import SwiftUI

/// What the vocabulary sends with each dictation: a count against the limit, the sent terms
/// as chips, and every term left out with the reason. Shared by Settings and the editor.
struct KeytermSummary: View {
  let report: KeytermReport
  var showsChips = true
  @Environment(\.colorSchemeContrast) private var systemContrast
  @Environment(\.forceIncreasedContrast) private var forcedContrast
  private var increased: Bool { systemContrast == .increased || forcedContrast }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(sentCount) of \(SarvamAPI.maxKeyterms) terms sent")
          .font(.body.monospacedDigit())
        Spacer()
        Text("Up to \(SarvamAPI.maxKeytermLength) characters each")
          .font(.caption).foregroundStyle(.secondary)
      }
      ProgressView(value: Double(sentCount), total: Double(SarvamAPI.maxKeyterms))
        .tint(report.overLimit.isEmpty ? StokColor.accent : StokColor.saffron)
        .accessibilityLabel("Terms sent")
        .accessibilityValue("\(sentCount) of \(SarvamAPI.maxKeyterms)")
      if !report.modelsWithoutKeyterms.isEmpty {
        warning(
          "No terms are sent while \(report.modelsWithoutKeyterms.formatted(.list(type: .and))) is in use. Choose saaras:v4 in Advanced > Models."
        )
      }
      if showsChips, !report.sent.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(report.sent, id: \.self) { term in
            Text(term).font(.callout).lineLimit(1)
              .padding(.horizontal, 8).padding(.vertical, 3)
              .foregroundStyle(StokColor.chipText)
              .background(StokColor.chipIndigo, in: .capsule)
              .overlay {
                if increased { Capsule().strokeBorder(StokColor.accent, lineWidth: 1) }
              }
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sent terms: \(report.sent.joined(separator: ", "))")
      }
      if !report.tooLong.isEmpty || !report.overLimit.isEmpty {
        // One element that names each excluded term and why, read in place of the
        // visual warnings below.
        Color.clear.frame(height: 0)
          .accessibilityElement()
          .accessibilityLabel("Not sent: \(exclusions)")
      }
      if !report.tooLong.isEmpty {
        warning(
          "\(count(report.tooLong.count)) over \(SarvamAPI.maxKeytermLength) characters, not sent"
            + (showsChips ? ": \(preview(report.tooLong))" : ". Struck through above."),
          coveredByExclusions: true)
      }
      if !report.overLimit.isEmpty {
        warning(
          "\(count(report.overLimit.count)) past the first \(SarvamAPI.maxKeyterms), not sent"
            + (showsChips ? ": \(preview(report.overLimit))" : ". Struck through above."),
          coveredByExclusions: true)
      }
    }
  }

  /// Nothing is sent when neither model accepts terms.
  private var sentCount: Int { report.modelsWithoutKeyterms.count == 2 ? 0 : report.sent.count }

  private func count(_ n: Int) -> String { n == 1 ? "1 term" : "\(n) terms" }

  private func preview(_ terms: [String]) -> String {
    let shown = terms.prefix(3).map { $0.count > 40 ? String($0.prefix(40)) + "…" : $0 }
    let rest = terms.count - shown.count
    return shown.joined(separator: ", ") + (rest > 0 ? ", and \(rest) more" : "")
  }

  /// Every term left out, with its reason, for VoiceOver: the editor's strikethrough is
  /// visual only.
  private var exclusions: String {
    let long = report.tooLong.map { "\($0), over \(SarvamAPI.maxKeytermLength) characters" }
    let over = report.overLimit.map { "\($0), past the first \(SarvamAPI.maxKeyterms)" }
    return (long + over).joined(separator: "; ")
  }

  private func warning(_ text: String, coveredByExclusions: Bool = false) -> some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(StokColor.saffron)
    }
    .font(.callout)
    .accessibilityHidden(coveredByExclusions)
  }
}
