// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Splits 16 kHz 16-bit mono PCM into pieces the synchronous REST endpoint accepts. The
/// endpoint refuses audio past 30 seconds, and a dictation can run for minutes, so a long
/// recording goes out as several requests whose transcripts are joined in order. Each cut
/// lands in the quietest 50 ms frame of a search window, so a word is rarely split.
enum RestAudioPlan {
  static let bytesPerSecond = 32_000
  /// The longest piece, kept under the 30-second limit with room for rounding.
  static let maxPieceSeconds = 29.0
  /// Cuts are searched between this point and `maxPieceSeconds` into each piece.
  static let minPieceSeconds = 20.0
  static let frameBytes = bytesPerSecond / 20

  /// An upper bound on `pieces(of:).count` for this much audio, without reading it: every
  /// piece but the last is at least `minPieceSeconds` long.
  static func maxPieceCount(audioBytes: Int) -> Int {
    let maxBytes = Int(maxPieceSeconds * Double(bytesPerSecond))
    let minBytes = Int(minPieceSeconds * Double(bytesPerSecond))
    guard audioBytes > 0 else { return 0 }
    guard audioBytes > maxBytes else { return 1 }
    return (audioBytes + minBytes - 1) / minBytes
  }

  /// Byte ranges covering `pcm` in order, each at most `maxPieceSeconds` long and starting
  /// on a sample boundary.
  static func pieces(of pcm: Data) -> [Range<Int>] {
    let maxBytes = Int(maxPieceSeconds * Double(bytesPerSecond))
    let minBytes = Int(minPieceSeconds * Double(bytesPerSecond))
    let base = pcm.startIndex
    let total = pcm.count - pcm.count % 2
    var ranges: [Range<Int>] = []
    var start = 0
    while total - start > maxBytes {
      let cut = quietestCut(in: pcm, from: start + minBytes, to: start + maxBytes)
      ranges.append((base + start)..<(base + cut))
      start = cut
    }
    if total > start { ranges.append((base + start)..<(base + total)) }
    return ranges
  }

  /// Offset, relative to the start of `pcm`, of the middle of the lowest-energy frame
  /// between `lower` and `upper`. Always even and inside the window.
  static func quietestCut(in pcm: Data, from lower: Int, to upper: Int) -> Int {
    var bestOffset = upper
    var bestEnergy = Double.infinity
    pcm.withUnsafeBytes { raw in
      let samples = raw.bindMemory(to: Int16.self)
      var frame = lower
      while frame + frameBytes <= upper {
        var energy = 0.0
        for index in (frame / 2)..<((frame + frameBytes) / 2) {
          let value = Double(Int16(littleEndian: samples[index]))
          energy += value * value
        }
        if energy < bestEnergy {
          bestEnergy = energy
          bestOffset = frame + frameBytes / 2
        }
        frame += frameBytes
      }
    }
    return bestOffset - bestOffset % 2
  }

  /// Joins piece transcripts with single spaces, skipping empty pieces.
  static func join(_ transcripts: [String]) -> String {
    transcripts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
