# Performance evidence and comparison plan

Note: this review predates the move to Sarvam AI. Source review, protocol, and UI
evidence needs stay valid. Latency observations were removed (see below).

Reviewed on 2026-09-06 using source and a read-only query of the configured history
database. The query selected only build, outcome, route, delivery, cleanup status,
and timing columns. It did not select transcripts, app names, corrections, or
credentials. No microphone, preferences, or running app state changed.

## Current observations

The history snapshot taken here (median and maximum total time for build 3 and
build 4 Live turns, and one build 4 timing breakdown) came from turns that ran on
the previous transcription backend. It is removed. No Sarvam latency distribution
exists yet. Re-run the same read-only query on a history that holds only Sarvam
turns, grouped by source build, and report sample counts with it. Do not pool
previous-backend rows with Sarvam rows. Failed and clipboard-only turns stay out
of latency summaries but remain necessary reliability outcomes.

`TextInjector.swift` reports dispatch after posting the paste events. It does not
confirm that the destination application consumed or rendered the text. Therefore
dispatch timings do not prove physical key-up-to-visible-text latency, first-word
retention, duplicate-free delivery, or transcription accuracy. No p95 claim is
useful with a handful of samples; nearest-rank p95 is simply their maximum.

## Source review

- History queries and statistics run through HistoryRepository's database queue.
  The initial 180 ms debounce was removed in build 5; only search edits debounce.
  This fixes a loading-state delay, not measured window presentation time.
- History's displayed aggregate includes all successful routes and cleanup states
  within its date range. It must not be used alone for the Live-only, cleanup-off
  acceptance target. Use stratified metadata instead.
- The injector deliberately waits 10 ms between key-down and key-up events. This
  is part of the existing paste behavior; do not remove it without delivery tests.
- Existing microphone profiles in PERFORMANCE.md concern hardware readiness and
  main-thread setup. They do not measure current window frames or speech accuracy.

## Repeatable real-speech evaluation

1. Use the same Mac, microphone, destination document, network, language settings,
   vocabulary, and cleanup-off policy for every run.
   Record the exact source build and relevant configuration before the session.
2. Prepare 15 owner-reviewed prompts outside Git: English, Marathi, and mixed
   language, each covering a short phrase, names/technical terms, numbers and
   punctuation, a mid-sentence pause, and a longer sentence. Define expected words
   before testing; Stok's transcript is not the ground truth.
3. Speak each prompt twice. This gives 30 turns. Treat this as an initial
   evaluation, not a precise tail study. Quit other dictation apps first.
4. Bound each recording to 20 seconds and each settlement wait to 10 seconds.
   Record timeout/fallback/missing-output trials as failures. Repeat a failed trial
   only as a separately identified retry. Never drop the original result.
5. Inspect the destination after every turn. Record missing first words, incorrect
   words, omissions, additions, punctuation errors, duplicate insertions, and
   clipboard-only results separately. Compute word error rate from the agreed
   tokenization, and also report names/numbers errors and language-specific slices.
6. Report median and nearest-rank p95 dispatch latency for successful Live turns,
   plus sample counts, all failure counts, and REST fallback rate. Report actual
   visible-text timing separately if an instrumented destination is available.
   Do not call dispatch timing visible-text timing.
7. Repeat idle startup and device-switch trials separately, including Bluetooth
   when available. Test optional cleanup in another set so its added roundtrip
   does not contaminate the baseline. Review meaning preservation manually.

Acceptance requires median Live latency below 500 ms and per-slice accuracy
against the ground truth. Current evidence establishes
neither. The real-speech session needs owner participation and has not been run.

## UI performance evidence still needed

Use a bounded Instruments capture while opening each window and scrolling a
synthetic History fixture. Measure event-to-presented-frame time, dropped frames
at the display refresh rate, and engine-event-to-menu-state presentation. Capture
the same interaction before and after any proposed change. Source inspection and
the duration of a window-opening method cannot prove the 100 ms presentation or
one-frame update targets. No new Instruments capture was performed in this review.

## Checks performed

- Read-only SQLite metadata queries completed successfully with a two-second busy
  timeout; preference-path lookup used a three-second subprocess timeout.
- Inspected timing/injection code and existing performance evidence. No live API
  calls, recording, benchmark settings changes, or transcript analysis were run.

## Deferred-work refresh, 2026-09-06

A new read-only SQLite query selected only build, outcome, transport, delivery,
cleanup status, and total timing. It used a two-second database timeout and a
three-second preference-path lookup. No real-speech trials or destination-output
inspections have occurred.
[ACCEPTANCE_SESSION.md](ACCEPTANCE_SESSION.md) provides the prepared protocol.

The current host is macOS 26.6.2 (25G83), arm64. Instruments discovery lists
SwiftUI and Animation Hitches templates. Native Computer Use attachment to
installed Stok times out, so reproducible window/scroll/state interactions are
blocked. No idle trace was substituted for frame-presentation evidence and no
UI performance optimization is justified by this discovery alone.
