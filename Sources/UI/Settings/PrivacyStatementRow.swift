// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// One privacy fact: an icon tile for a visual anchor, a short claim, a one-line detail,
/// and an optional way to check the claim.
struct PrivacyStatementRow: View {
  let icon: IconTile
  let title: String
  let detail: String
  var action: String? = nil
  var perform: () -> Void = {}
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      icon
      VStack(alignment: .leading, spacing: 2) {
        Text(title).fontWeight(.medium)
        Text(detail).font(.callout).foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 12)
      if let action {
        Button(action, action: perform).controlSize(.small).fixedSize()
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}
