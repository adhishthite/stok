// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import AppKit
import StokEngine
import SwiftUI

/// The vocabulary text, editable, with every term that is not sent struck through in red
/// right where it is written. Terms are located with the engine's own parsing rules
/// (VocabularyTermLocator), so only real items are marked: never a substring of a longer
/// word, a comment, or a replacement's left side. The marks are temporary layout
/// attributes and never enter the saved file. Ranges are computed once per text revision,
/// off the main thread for a large file, and only marks that changed are touched.
struct VocabularyTextEditor: NSViewRepresentable {
  @Binding var text: String
  /// Terms to mark, exactly as they appear in the report.
  var unsent: [String]

  /// Above this many UTF-16 units the ranges are found on a background queue.
  static let backgroundThreshold = 100_000

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    guard let textView = scroll.documentView as? NSTextView else { return scroll }
    textView.delegate = context.coordinator
    textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.textContainerInset = NSSize(width: 8, height: 10)
    textView.setAccessibilityLabel("Vocabulary terms and replacement rules")
    textView.string = text
    scroll.drawsBackground = false
    textView.drawsBackground = false
    context.coordinator.textView = textView
    context.coordinator.refresh(text: text, unsent: unsent)
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let textView = scroll.documentView as? NSTextView else { return }
    context.coordinator.parent = self
    if textView.string != text { textView.string = text }
    context.coordinator.refresh(text: text, unsent: unsent)
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: VocabularyTextEditor
    weak var textView: NSTextView?
    private var revision = 0
    private var lastText: String?
    private var lastUnsent: Set<String> = []
    private var marked: Set<NSRange> = []

    init(parent: VocabularyTextEditor) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
    }

    /// Recomputes the marks only when the text or the unsent set changed.
    func refresh(text: String, unsent: [String]) {
      let wanted = Set(unsent.map { $0.lowercased() })
      let textChanged = text != lastText
      guard textChanged || wanted != lastUnsent else { return }
      lastText = text
      lastUnsent = wanted
      revision += 1
      let current = revision
      guard !wanted.isEmpty || !marked.isEmpty else { return }
      let find: @Sendable () -> Set<NSRange> = {
        Set(
          VocabularyTermLocator.terms(in: text)
            .filter { wanted.contains($0.term.lowercased()) }.map(\.range))
      }
      if (text as NSString).length > VocabularyTextEditor.backgroundThreshold {
        DispatchQueue.global(qos: .userInitiated).async {
          let ranges = find()
          DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
              self?.apply(ranges, revision: current, textChanged: textChanged)
            }
          }
        }
      } else {
        apply(find(), revision: current, textChanged: textChanged)
      }
    }

    // After an edit the old ranges no longer line up with the text, so every mark is cleared
    // in one call and the new ones added. When only the unsent set changed, just the
    // difference is touched.
    private func apply(_ ranges: Set<NSRange>, revision: Int, textChanged: Bool) {
      guard revision == self.revision, let layout = textView?.layoutManager,
        let length = textView.map({ ($0.string as NSString).length })
      else { return }
      if textChanged {
        let whole = NSRange(location: 0, length: length)
        layout.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: whole)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        marked = []
      }
      guard ranges != marked else { return }
      for range in marked.subtracting(ranges) where NSMaxRange(range) <= length {
        layout.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: range)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
      }
      for range in ranges.subtracting(marked) where NSMaxRange(range) <= length {
        layout.addTemporaryAttributes(
          [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.systemRed,
          ], forCharacterRange: range)
      }
      marked = ranges
    }
  }
}
