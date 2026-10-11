// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import QuartzCore

extension AuraView {
  /// One aura colour, precomputed: the opaque tint (alpha rides layer opacity) and the
  /// pool's three gradient stops. The listening and processing cycles are sampled once into
  /// tables, so the display link only looks a colour up.
  struct AuraTint {
    let index: Int
    let color: CGColor
    let poolColors: [CGColor]

    private static let steps = 512

    private init(index: Int, _ color: NSColor) {
      self.index = index
      self.color = color.cgColor
      poolColors = [
        color.cgColor, color.withAlphaComponent(0.35).cgColor, color.withAlphaComponent(0).cgColor,
      ]
    }

    private static let listeningTable = (0..<steps).map {
      AuraTint(index: $0, Palette.listeningColor(at: CGFloat($0) / CGFloat(steps)))
    }
    private static let processingTable = (0..<steps).map {
      AuraTint(index: steps + $0, Palette.processingColor(at: CGFloat($0) / CGFloat(steps)))
    }
    static let success = AuraTint(index: 2 * steps, Palette.success)
    static let error = AuraTint(index: 2 * steps + 1, Palette.error)

    /// Keyframes for the render server's colour cycle: 64 evenly spaced samples, with the
    /// first repeated at the end so the loop closes without a jump.
    static let listeningCycle = keyframes(listeningTable)
    static let processingCycle = keyframes(processingTable)

    private static func keyframes(_ table: [AuraTint]) -> [AuraTint] {
      stride(from: 0, to: steps, by: steps / 64).map { table[$0] } + [table[0]]
    }

    static func listening(at phase: CGFloat) -> AuraTint { listeningTable[slot(phase)] }
    static func processing(at phase: CGFloat) -> AuraTint { processingTable[slot(phase)] }

    private static func slot(_ phase: CGFloat) -> Int {
      let wrapped = phase - floor(phase)
      return min(steps - 1, Int(wrapped * CGFloat(steps)))
    }
  }
}
