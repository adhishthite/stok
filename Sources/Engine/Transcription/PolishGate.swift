// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Decides on the turn queue whether a transcript needs the cleanup request.
/// Saaras already punctuates short English sentences; cleanup pays off for
/// run-on text, spoken structure, and spelled-out numbers. Misses paste the
/// raw transcript, so the rules lean toward polishing: any non-Latin letter
/// polishes, because the cue lists cover English only.
enum PolishGate {
  /// A sentence run longer than this usually lacks punctuation or paragraphs.
  static let maximumRunWords = 20

  static func needsPolish(_ text: String) -> Bool {
    let characters = Array(text.lowercased())
    var words: [String] = []
    var current = ""
    var runWords = 0
    for (index, character) in characters.enumerated() {
      // The base scalar decides the script; combining accents follow it.
      if character.isLetter, let base = character.unicodeScalars.first, !isLatin(base) {
        return true
      }
      if character.isLetter || character.isNumber {
        current.append(character)
        continue
      }
      // Apostrophes and dots inside a word ("can't", "com.example", "2.5")
      // join it; quotes and sentence-ending dots end it.
      let next = index + 1 < characters.count ? characters[index + 1] : " "
      if !current.isEmpty, connectors.contains(character), next.isLetter || next.isNumber {
        current.append(character == "\u{2019}" ? "'" : character)
        continue
      }
      if !current.isEmpty {
        words.append(current)
        current = ""
        runWords += 1
        if runWords > maximumRunWords { return true }
      }
      if terminators.contains(character) { runWords = 0 }
      if terminators.contains(character) || clauseBreaks.contains(character),
        words.last != boundary
      {
        words.append(boundary)
      }
    }
    if !current.isEmpty {
      words.append(current)
      runWords += 1
    }
    if runWords > maximumRunWords { return true }
    for (position, word) in words.enumerated() {
      if numberWords.contains(word) { return true }
      let startsSentence = position == 0 || words[position - 1] == boundary
      if startsSentence, sentenceEnumerators.contains(word) { return true }
      guard position + 1 < words.count, let followers = cuePairs[word] else { continue }
      let next = words[position + 1]
      if followers.contains(next) { return true }
      if ordinalFollowers.contains(word), next.allSatisfy(\.isNumber) { return true }
    }
    return words.contains { singleCues.contains($0) }
  }

  private static func isLatin(_ scalar: Unicode.Scalar) -> Bool { scalar.value < 0x0250 }

  /// Marks a sentence or clause end in the word list so cue pairs never span
  /// sentences and enumerators match after a colon or semicolon.
  private static let boundary = "."

  /// Ordinals that open a sentence or clause in a spoken list ("Second, buy eggs.").
  /// "First" is left out because it opens ordinary sentences too.
  private static let sentenceEnumerators: Set<String> = ["second", "third", "fourth", "lastly"]

  private static let connectors: Set<Character> = ["'", "\u{2019}", "."]
  private static let clauseBreaks: Set<Character> = [":", ";"]
  private static let terminators: Set<Character> = [".", "?", "!", "\u{0964}", "\u{0965}"]

  /// Numbers that Saaras can leave spelled out. One to ten are omitted
  /// because they are common in ordinary prose.
  private static let numberWords: Set<String> = [
    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
    "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
    "hundred", "thousand", "lakh", "lakhs", "crore", "crores", "million", "billion", "percent",
  ]

  private static let ordinals: Set<String> = [
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
  ]

  /// Cue words that also start a list when followed by digits ("number 1").
  private static let ordinalFollowers: Set<String> = ["number", "point", "step", "item"]

  /// Spoken structure: "number one", "point two", "step three", "new line".
  private static let cuePairs: [String: Set<String>] = [
    "number": ordinals, "point": ordinals, "step": ordinals, "item": ordinals,
    "new": ["line", "paragraph"], "next": ["line", "paragraph"],
    "full": ["stop"], "question": ["mark"], "exclamation": ["mark"],
  ]

  private static let singleCues: Set<String> = [
    "firstly", "secondly", "thirdly", "bullet", "bullets", "comma", "colon", "semicolon", "period",
  ]
}
