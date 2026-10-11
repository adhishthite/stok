// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Where each recognition term sits in a vocabulary file's text, found with the same rules
/// `EngineConfiguration.parseVocabulary` and `splitVocabularyItems` apply: comment and empty
/// lines are skipped, a line with commas holds several items, and a `wrong => right` item
/// contributes only its right side. The editor marks these exact ranges, so a short term is
/// never matched inside a longer word, a comment, or a replacement's left side.
public enum VocabularyTermLocator {
  public struct Located: Equatable, Sendable {
    public let term: String
    public let range: NSRange
  }

  public static func terms(in text: String) -> [Located] {
    let string = text as NSString
    let trimmedWhole = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // A JSON array file is parsed as a whole by the engine; there are no lines to mark.
    if trimmedWhole.hasPrefix("[") && trimmedWhole.hasSuffix("]") { return [] }
    var found: [Located] = []
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length), options: [.byLines, .substringNotRequired]
    ) { _, lineRange, _, _ in
      let line = string.substring(with: lineRange)
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
      var pieces: [NSRange] = []
      if line.contains(",") {
        var start = lineRange.location
        for part in line.components(separatedBy: ",") {
          let length = (part as NSString).length
          pieces.append(NSRange(location: start, length: length))
          start += length + 1
        }
      } else {
        pieces.append(lineRange)
      }
      for piece in pieces {
        guard let item = trimmedRange(of: piece, in: string) else { continue }
        let itemText = string.substring(with: item)
        if itemText.hasPrefix("#") { continue }
        let arrow = (itemText as NSString).range(of: "=>")
        if arrow.location == NSNotFound {
          found.append(Located(term: itemText, range: item))
          continue
        }
        let wrong = itemText.prefix(arrow.location).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = NSRange(
          location: item.location + arrow.location + arrow.length,
          length: item.length - arrow.location - arrow.length)
        guard !wrong.isEmpty, let term = trimmedRange(of: right, in: string) else { continue }
        found.append(Located(term: string.substring(with: term), range: term))
      }
    }
    return found
  }

  private static func trimmedRange(of range: NSRange, in string: NSString) -> NSRange? {
    var start = range.location
    var end = range.location + range.length
    let space = CharacterSet.whitespacesAndNewlines
    while start < end, let scalar = UnicodeScalar(string.character(at: start)),
      space.contains(scalar)
    {
      start += 1
    }
    while end > start, let scalar = UnicodeScalar(string.character(at: end - 1)),
      space.contains(scalar)
    {
      end -= 1
    }
    return end > start ? NSRange(location: start, length: end - start) : nil
  }
}
