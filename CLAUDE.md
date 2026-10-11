# CLAUDE.md

Stok: native macOS push-to-talk dictation with a Sarvam realtime speech-to-text backend, shipped
as a signed menu-bar app. Live speech-to-text is Saaras v4 over the Sarvam realtime WebSocket,
with Saaras v4 REST as the fallback.

## Build
- XcodeGen `project.yml` is the source of truth; `*.xcodeproj` is generated
  and gitignored. `make generate build run test lint format check package`.
- Deployment target macOS 14. Swift 6 language mode in App/Store/UI/Support;
  Engine and HUD may stay in Swift 5 mode until audited.
- App Sandbox is OFF by design (global event tap, AX, synthesized paste,
  IOKit). Hardened runtime ON. Distribution is Developer ID + notarization.
- Sparkle is integrated. Hosted updates and an actual installed update remain unverified.
  Other dependencies require a concrete engineering benefit.

## Layering
- `Engine/` has no SwiftUI and no window code. It reports through a delegate.
- `Store/DictationStore` (`@MainActor @Observable`) is the only engine
  surface SwiftUI sees. Views never touch the engine, sockets, or SQLite.
- `HUD/` is AppKit + Core Animation on an NSPanel. Do not rewrite in SwiftUI.
  Never animate the panel frame. `HoldRingView`'s backing layer is the
  CAShapeLayer via `makeBackingLayer`. All colors come from the Stok palette.
- All AI calls go to the Sarvam API only (`api.sarvam.ai`, key in the `api-subscription-key`
  header). Do not add another AI service.
- One type per file, named after the type. Normal access control.

## Engine invariants (do not relearn these)
- Settle-once arbiter: `currentTurnId`/`turnSettled`/`pendingFallbackTimer`
  mutate only on `sessionQueue`; `settle()` is the sole paste-or-error path;
  WS and REST race, first result for a live turn wins. No second path to
  `handleTranscribedText`. No actors here.
- `isProcessing` is set in `handleKeyUp` before the post-roll drain; every
  pipeline exit clears it.
- `captureActive`, `turnLocked`, lock work items: main-thread-only.
  `handleKeyDown` checks `turnLocked` before `isProcessing`.
- Micro-click guard and silent-clip gate abandon the WS turn without
  committing; `startNewTurn` resets state.
- Nothing calls `sessionQueue.sync` from main.
- Never hold an NSLock while logging or calling out. Snapshot, release, act.
- History shows the clean transcript; only the pasted payload gets the
  trailing space. Token counts are raw API values or NULL, never estimates.
  Sarvam returns no per-request STT usage, so STT tokens are NULL. Sarvam prices
  are in INR and history stores USD, so cost is NULL (unknown). Never invent a rate.
- Realtime uses manual endpointing: the shortcut marks speech start and end. A turn
  is capped at 10 minutes (`turn_limit`). A live turn settles as `server_final`.
- REST fallback splits audio over 29 s at quiet frames (`RestAudioPlan`), sends at
  most 4 pieces at once (`RestTranscriptAssembler`), and joins them in order.
- Custom vocabulary goes out as keyterms: at most 50, at most 64 characters each,
  saaras:v4 only (`SarvamAPI.keyterms`).
- Cleanup uses `sarvam-105b-conversations` with reasoning off. Reasoning counts
  against `max_tokens`, so a reasoning model can return `content: null`;
  `ChatCompletionDecoder` treats that as truncated and keeps the original text.
- The API key is `SARVAM_API_KEY` (Keychain account `sarvam-api-key`).
- Every config knob: one table entry drives UserDefaults key, env override,
  Settings UI, and README row. API key lives in Keychain only.

## Verification
- `make check` runs XCTest, Swift format lint, the compiled settings-reference
  check, shell syntax checks, Python regression tests, and `git diff --check`.
  `make check-ci` validates workflows and signing helpers. Report what ran.
- Latency claims require a measured Diagnostics line, measured on Sarvam.
- Never log or commit secrets. Inspect config by key name only.

## Current working agreement
- Work directly on main and commit small, verified changes. Tags and releases require the owner's instruction.
- Stok is open source and public: `adhishthite/stok`, licensed Apache-2.0. Code and
  Sparkle releases (DMG, ZIP, appcast) live in this one repository. There is no
  separate release repository. The root `LICENSE` and `Resources/Stok-LICENSE.txt`
  must stay identical; `make check` enforces it.
  Pushes and releases still require the owner's instruction. Read
  [CI_RELEASE.md](CI_RELEASE.md) before release work.
- Continue the full goal autonomously. The owner superseded milestone review stops on 2026-09-05.
- Treat native behavior, restrained feedback, responsiveness, and performance as design inputs now, not a final cosmetic phase.
- Load the relevant skill before work in its area: `macos-menubar-tuist-app` (layering only),
  `macos-spm-app-packaging` (signing, notarization, Sparkle), `swiftui-expert-skill`,
  `swiftui-ui-patterns`, `swiftui-view-refactor`, `swift-concurrency-expert`,
  `swiftui-performance-audit`, `app-store-changelog` (release notes), `security-review`
  before a release, and the Sarvam skills `speech-to-text`/`chat` (`.agents/skills`) only for
  protocol changes; the live docs at docs.sarvam.ai win over a stale skill.
- Before SwiftUI work, read ~/.agents/skills/swiftui-expert-skill/references/latest-apis.md.
- No em dashes in prose, docs, or new user-facing copy.

## Operation deadlines
- Long foreground commands use Scripts/bounded_run.py with an explicit deadline.
- Builds and tests default to 120 seconds. Inspect a live process and concrete progress before extending its control file, by at most 60 seconds each time.
- A started command has a process handle. A plan or Working indicator does not establish execution.
- Report results or blockers promptly; avoid unbounded waits and repeated UI inventory attempts.
