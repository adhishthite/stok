// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Lays children out in rows, wrapping to a new row when the next one does not fit.
struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
    let height = rows.last.map { $0.y + $0.height } ?? 0
    let width = rows.map(\.width).max() ?? 0
    // A nil or infinite proposal asks for the ideal size: report the measured width,
    // never infinity.
    guard let proposed = proposal.width, proposed.isFinite else {
      return CGSize(width: width, height: height)
    }
    return CGSize(width: proposed, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for row in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let size = measure(subviews[index], width: bounds.width)
        subviews[index].place(
          at: CGPoint(x: x, y: bounds.minY + row.y),
          proposal: ProposedViewSize(width: size.width, height: size.height))
        x += size.width + spacing
      }
    }
  }

  /// A child's natural size, never wider than the row: a long chip truncates instead of
  /// overflowing its card.
  private func measure(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
    let natural = subview.sizeThatFits(.unspecified)
    guard width.isFinite, natural.width > width else { return natural }
    return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
  }

  private struct Row {
    var indices: [Int] = []
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = [Row()]
    for (index, subview) in subviews.enumerated() {
      let size = measure(subview, width: width)
      var row = rows.removeLast()
      if !row.indices.isEmpty, row.width + spacing + size.width > width {
        let next = Row(y: row.y + row.height + spacing)
        rows.append(row)
        row = next
      }
      row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
      rows.append(row)
    }
    return rows.filter { !$0.indices.isEmpty }
  }
}
