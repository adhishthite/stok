# Performance evidence

Note: Stok moved from a previous transcription backend to Sarvam AI. Microphone,
capture, and tooling records below do not depend on the backend and stay. Records
that did depend on it (latency, accuracy, token counts, cost, flush and frame
tuning) were removed or replaced with a statement of what must be re-run on
Sarvam. The first Sarvam results are in [VALIDATION.md](VALIDATION.md).

## Preparing the input node without capture, 2026-09-06

An explicit preparation probe constructed the AVAudioEngine input node before
measuring readiness. It did not install a tap or call `start` during preparation.
Preparation took 154.7 ms; `AVAudioEngine.isRunning` was false and
`kAudioOutputUnitProperty_IsRunning` returned zero with status zero.
The three subsequent readiness measurements were 297.9, 207.5, and 195.9 ms;
their main-thread request intervals were 0.016, 0.074, and 0.072 ms.

The 12-second Instruments capture completed successfully at
`build/microphone-startup-20260906-015434.trace`, PID 91206. The probe briefly
started and stopped audio for the readiness measurements, but retained no
dictation and uploaded no audio. The preparation-state measurements precede
those starts. They do not constitute visual verification of Control Center.

Stok now queues input-node construction at engine startup after permission checks,
while on-demand capture remains stopped. Device selection, tap installation,
and actual audio start still happen when capture is requested. The probe keeps
its unprepared baseline path and enables the preparation experiment explicitly:

```sh
STOK_PREPARE_MIC=1 make profile-microphone
```

This moves setup work before the first shortcut. These small sequential samples
do not prove a stable latency improvement, first-word accuracy, or the separate
sub-500 ms key-up-to-paste target.

## Stored dictation timing

The earlier read-only aggregate of Stok's history covered dictations that ran on
the previous backend. It is removed. Key-release-to-dispatch, API interval, and
total timings are not yet measured on Sarvam. Re-run `make report` on a history
that holds only Sarvam turns, filtered by build.

All records in that earlier history had a NULL build identifier, so it was a
mixed-version baseline. Stok now stamps its source revision into the bundle and
assigns that value to new history records, including a `-dirty` suffix for
uncommitted source. Existing rows are not backfilled. Diagnostics and the
development runtime report show the same build identifier.

## Microphone startup baseline, 2026-09-05

Before the hardware-queue change, Stok's on-demand microphone startup blocked
the main thread. This was a measured UI responsiveness problem, separate from
key-up-to-paste latency.

The debug probe starts and suspends the microphone three times with zero
pre-roll. It does not record a dictation or send audio for transcription.
It measures elapsed time until the first healthy audio buffer and elapsed time
inside the synchronous `ensureReady` call on the main thread.

| Attempt | Main-thread setup | Total readiness |
| --- | ---: | ---: |
| 1 | 306.0 ms | 496.2 ms |
| 2 | 85.7 ms | 191.8 ms |
| 3 | 78.0 ms | 184.7 ms |

These measurements were collected under Instruments Time Profiler against
one running Stok process, PID 75553. The recording completed with exit 0 and a
12-second time limit. The app remained running afterward. The local trace is
`build/microphone-startup-20260905-232839.trace`. Traces are generated artifacts
and are not committed. The JSON probe report is `/tmp/stok-microphone-probe.json`.

The measured interval includes synchronous audio-device selection, tap and
converter setup, and `AVAudioEngine.prepare/start`. CPU samples establish
call-stack attribution but do not measure blocked-thread wall time. The trace
export contained 69 main-thread CPU samples, 44 with `rebuildHardware` on the
stack, including input-node and audio-unit construction. The probe's
separate elapsed-time measurement covers that wait. Device and profiler state
affect timings, so these three samples do not establish a stable distribution
or compare performance against earlier unprofiled samples.

## Hardware queue result

The same three-attempt probe after moving hardware lifecycle operations to a
serial background queue measured:

| Attempt | Main-thread setup | Total readiness |
| --- | ---: | ---: |
| 1 | 0.132 ms | 462.2 ms |
| 2 | 0.065 ms | 190.7 ms |
| 3 | 0.057 ms | 193.9 ms |

`make profile-microphone` completed with exit 0. The trace is
`build/microphone-startup-20260905-233823.trace`, PID 80691. Exported CPU samples
contain 33 worker-thread samples with `rebuildHardware` on the stack and zero
main-thread samples with that call. There were 25 main-thread samples total.

This removes the measured synchronous startup stall. It does not establish
faster hardware readiness or faster transcription. Hardware readiness remains
hundreds of milliseconds, and first-word capture still needs real dictation
validation. These runs are small samples taken sequentially under Instruments.

The existing recovery state machine now runs with hardware operations on one
serial queue. Locked snapshots let the main thread check readiness and input
metadata. Epoch checks invalidate readiness results immediately on cancellation,
including results already queued for main. The turn arbiter still uses its
original DispatchQueue and NSLock model. No actor replaced it.

The targeted Thread Sanitizer run passed all five selected tests, with no race
reports. Coverage includes the unchanged recovery regression fixtures, startup
while hardware is blocked, cancellation during startup, invalidating a result
already queued for main, and retaining the audio owner until queued shutdown
finishes. This covers the tested paths, not every possible device interaction.

```sh
./Scripts/xcodebuild.sh -project Stok.xcodeproj -scheme Stok \
  -configuration Debug -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' -enableThreadSanitizer YES \
  -only-testing:StokEngineTests/MicrophoneLifecycleTests \
  -only-testing:StokEngineTests/MicrophoneRegressionTests test
```

Output: `Executed 5 tests, with 0 failures`, `TEST SUCCEEDED`.

## Reproduce

```sh
make profile-microphone
```

This builds Debug with the existing 120-second build deadline, quits the old
app, launches through Launch Services, and attaches Time Profiler. The probe
waits six seconds to let attachment start. Recording lasts 12 seconds; the
profiler command has a 45-second deadline including trace saving. A successful
build and the profile invocation were exercised separately for this baseline.

Two initial `xctrace --launch` attempts saved samples but returned exit 54 and
left stopped processes at `_dyld_start`. Those processes were terminated after
inspection. The reproducible command uses `--attach` to avoid that launch path.
One quit attempt timed out after ten seconds while addressing a stopped process.
No timed-out command was counted as a successful profile.

## Remaining performance gates

- Real live-path key-up-to-paste median below 500 ms. Not yet measured on Sarvam.
- First-word capture after idle, including device changes and Bluetooth input.
- Windows opening below 100 ms and state presentation within one display frame.
- Refresh-rate scrolling, HUD smoothness, and accessibility interaction.

None of these gates is proven by the startup probe or offline tests.

## Optional cleanup

The owner reported that build 3 felt smooth and planned to use Stok exclusively.
That is qualitative feedback, not a frame-time measurement.

The optional text cleanup pass defaults to off. Earlier cleanup durations, live
dictation medians, and token usage were measured on the previous backend and are
removed. They are not yet measured on Sarvam with real speech. The first Sarvam
cleanup check used five synthetic text-only cases (see [VALIDATION.md](VALIDATION.md)).
It measures cleanup-stage time alone. It excludes microphone capture, the original
transcription, and paste delivery, and it is not a real-speech accuracy evaluation.
The off-path test verifies no cleanup request and inline continuation. No claim
of zero measured CPU overhead is made. Enabled and disabled dictations must be
kept separate when assessing the latency target.

## Turn latency report

`Scripts/turn_report.py` aggregates the metadata columns in `history.db`
(timings, counters, and enum labels only; it never selects transcript text,
corrections, app identity, or raw error strings) into medians, nearest-rank
p95s, and group-by tables for repeatable latency review. It opens the
database read-only and tolerates older databases that are missing a metric
or grouping column, printing a one-line note instead of failing.

```sh
make report
make report ARGS="--build bb2362f --since 2026-09-01"
make report ARGS="--tag control --json"
```

Default arguments read `~/Library/Application Support/Stok/history.db`;
pass `--db <path>` to point at another file. `--all-outcomes` shows outcome
counts instead of the default success/dispatched/live cohort. Run
`python3 Scripts/turn_report.py --help` for the full filter and column
list, and for the exact median and p95 definitions used.

## Sarvam latency budget, 2026-10-07

Key-up to paste is about 290 ms median, composed from measured segments. No
end-to-end Sarvam turn with real capture and paste has been recorded yet; the
acoustic harness was not run because it plays audio aloud.

| Segment | Median | p90 | n | Source |
| --- | --- | --- | --- | --- |
| Event tap to `handleKeyUp` | 0.2 ms | 4.6 ms | 141 | real-use history (previous backend, local segment) |
| Post-roll finalize | 32.5 ms | 35.0 ms | 141 | real-use history |
| `speech_end` to terminal final, `stream_type=fast` | 237.5 ms | 339.5 ms | 150 | wire probe |
| of which WebSocket ping round trip | 9.3 ms | 14.5 ms | 450 | wire probe |
| Paste (`inject`, including the 10 ms key hold) | 15.2 ms | 16.2 ms | 200 | headless paste benchmark |

Server compute dominates. Network round trip is about 9 ms. Per-frame audio work
(conversion, base64, JSON, send queue) costs about 240 us of CPU per second of
audio and is not worth optimizing.

## Server and capture settings, measured on Sarvam, 2026-10-07

Paired and interleaved direct-mode runs on identical clips (English, Hindi,
Marathi, Tamil, Bengali, Gujarati), compared with `stream_type=fast` and the
defaults:

| Change | Pairs | Paired median difference (95% CI) | Accuracy | Decision |
| --- | --- | --- | --- | --- |
| `stream_type=simulated` | 150 | -66.4 ms (-79 to -59) | unchanged | `LIVE_WORDS` off |
| `stream_type=balanced` | 150 | +5.0 ms (-6 to +21) | unchanged | not used |
| `SILENCE_FLUSH_MS` 0 | 75 | -7.5 ms (-21 to +3) | worse | keep 200 |
| `SILENCE_FLUSH_MS` 100 | 75 | -11.7 ms (-29 to +4) | worse | keep 200 |
| `SILENCE_FLUSH_MS` 400 | 75 | +0.3 ms | unchanged | keep 200 |
| `PRE_ROLL_MS` 0 | 75 | +3.6 ms (not significant) | worse | keep 400 |
| Fresh socket per turn | 150 | -3.4 ms (-13 to +6) | unchanged | keep the warm socket |

`simulated` sends no partial transcripts, so the overlay cannot show words while
you speak. `LIVE_WORDS` (on by default) keeps `fast` with live words; off, or with
dictated words hidden on screen, Stok uses `simulated`. The real Swift client
confirmed the gain: 30 turns per arm, median 183.9 ms (`fast`) and 137.1 ms
(`simulated`), paired difference -47.8 ms (95% CI -66.3 to -38.7), 30 of 30
exact transcripts in both arms. Accuracy comparisons use the script-aware word
error rate in `make harness-report`, which counts a Devanagari and a romanized
rendering of the same words as a match.

## Low-latency capture, 2026-10-07

The input tap delivered 100 ms buffers (220 real turns), not the 1024 frames the
earlier reasoning assumed. Capture now runs on the hardware IO cycle through an
`AVAudioSinkNode` and a lock-free ring (`Sources/Engine/Audio/CaptureRing`), with
no allocation or locks on the IO thread. `make profile-microphone`, built-in
microphone, 48 kHz:

| Measure | Tap | IO cycle |
| --- | --- | --- |
| Cold readiness, median | 174.0 ms (n=10) | 72.4 ms (n=20) |
| Buffer duration | 100 ms | 10.7 ms (512 frames) |

Thread Sanitizer reported no warnings on the capture tests, including a real
microphone run. `CHUNK_MS` values below 100 ms now take effect, in steps of one
IO cycle.

## Trailing-capture floor, 2026-09-26 (capture-side timing)

Every turn records at least `POST_ROLL_MIN_MS` after release. On turns where the
speaker was already quiet for `POST_ROLL_MS` (250 ms) before release, the floor is
the whole wait, and that is the usual case: real-use capture finalize has a 78 ms
median. Acoustic harness, 24 turns per arm, finalize time on the turns where the
floor bound (banked quiet of 250 ms or more):

| Floor | Turns | Finalize |
| --- | --- | --- |
| 60 ms | 9 | 61 to 67 ms |
| 30 ms | 6 | 35 to 42 ms |
| 15 ms | 7 | 19 to 21 ms |

Last-word misses were measured on the previous backend and are not yet measured on
Sarvam. On a floor-bound turn all speech ended at least 250 ms before release, so
the only post-release audio that matters is the audio in flight at key-up. With
IO-cycle capture that is one cycle (512 frames, 10.7 ms here) plus about 2 ms of
delivery lag and 1.2 ms of input latency, about 14.3 ms worst case over about 720
measured cycles. The default stays 30 ms. On the built-in microphone 20 ms would
be safe; lower it only after Bluetooth and USB inputs are measured and last-word
misses are measured on Sarvam.

## Long dictations

An earlier direct-mode run of 40 paragraph clips (16 to 34 s of speech) measured
commit-to-result time and accuracy on the previous backend. Those results are
removed. Whether round trip grows with turn length on Sarvam, and whether the
flush savings hold on long turns, is not yet measured. Re-run the long-clip set in
direct mode with the `baseline`, `flush200`, `flush0`, and `verbatim` arms.

## Adaptive quiet line, 2026-09-26 (capture-side timing)

The capture tail ends after `POST_ROLL_MS` below `TRAIL_SILENCE_DB` (-40 dBFS). In a
room whose own level reaches that line, room tone reads as speech, and turns wait up
to `POST_ROLL_MAX_MS` (1.5 s). The quiet line now rises to the turn's room floor (10th
percentile of its 20 ms frames) plus `QUIET_MARGIN_DB` (8), never closer than 12 dB to
the turn's speech level (90th percentile), never below the configured threshold.
`quiet_threshold_db` records the line used on every turn.

Acoustic harness, adaptive (default) vs the fixed line (`QUIET_MARGIN_DB=0`), paired.
Only capture-side columns are kept. Total latency and accuracy columns came from the
previous backend and are removed.

| Room | Pairs | Arm | Finalize | Tail caps |
| --- | --- | --- | --- | --- |
| About -47 dBFS (natural) | 24 | adaptive | 78 ms | 0% |
| | | fixed | 105 ms | 0% |
| About -40 dBFS (steady fan-like noise) | 12 | adaptive | 41 ms | 0% |
| | | fixed | 305 ms | 25% |

In the quieter room the line barely moved (median -38.7 dBFS) and finalize did not
regress. In the -40 dBFS room the fixed line waited on room tone.

Review follow-up: in that first version the raised line also decided how much quiet was
banked before release, so a soft final syllable under the raised line could count as
quiet and a release during it could end capture at the 30 ms floor. Banked quiet is now
judged against the configured threshold, and the adaptive line applies only to the wait
after release, so a noisy-room turn always waits out the full 250 ms quiet window. Re-run
in the fan-noise room (it ran louder, -34 to -38 dBFS), 12 pairs:

| Arm | Finalize | Tail caps |
| --- | --- | --- |
| adaptive | 258 ms | 0% |
| fixed | 1,502 ms | 83% |

The safer version gives up the 41 ms finalize of the first version for the full quiet
window, and still removes the cap. Loud transient sounds at speech level (a
notification, a voice) still hold the tail; no level-based rule can separate those from
words. Effects on transcription accuracy in noisy rooms are not yet measured on Sarvam.

## Latency harness

The harness runs real engine turns without a person. `StokHarness` builds a
`DictationEngine` with a `.sink` delivery: real capture on the built-in mic, real
Live and REST routes, real history rows. It presses and releases the shortcut in
code, and it never touches the clipboard, pastes, or needs Accessibility. Clips
play through the built-in speakers, so capture start, warm and cold microphone
state, and the capture tail are measured on hardware.

```sh
make harness-clips   # once: 60 phrases x 2 variants from text-to-speech models
make harness-smoke   # 2 turns per arm, about 2 minutes, to check the setup
make harness         # default: baseline, warm90, and flush0; 60 turns each, about 4 hours
make harness ARGS="--arms baseline,flush700 --turns-per-arm 80"
make harness-direct ARGS="--arms baseline,flush0,flush700 --repeats 2"
make harness-report  # add ARGS="--min-turns 20" to drop smoke runs
```

- **Direct mode.** `--direct` streams each clip straight into `SarvamLiveClient`
  at real-time pace, over -60 dBFS room tone at a -20 dBFS speech peak, with the
  engine's pre-roll and digital-zero silence flush. Several workers run at once,
  each holding one persistent socket per arm and running every clip on every arm
  back to back, so contention falls on all arms alike. It measures the
  commit-to-result round trip and accuracy by accent and language. It cannot
  measure capture start, warm or cold state, or the capture tail; those need the
  acoustic run. It reaches the internal client through `@testable import`, as
  `LiveIntegrationTests` does. Each `make harness*` run executes a copy of the
  binary under `build/harness/bin`, so a rebuild never replaces a running one.

- **Clips.** `Scripts/harness_clips.py` renders `Tools/Harness/phrases.json` with
  weighted accents (mostly Indian English), voices, and pacing styles, alternating
  the two TTS models. Each clip is transcribed once over REST and regenerated when
  the check misses more than 20% of words, so a TTS mistake is not scored as an
  engine mistake.
- **Design.** Each round draws a block of clips with idle gaps drawn from the
  owner's measured gap mix (40% under 30 s, 17% 30 to 90 s, 43% 95 to 110 s; past the 90 s release
  window a longer gap leaves the microphone in the same cold state),
  a 150 to 450 ms lead from press to speech, and a 100 to 500 ms tail from
  last word to release. Every arm runs the same block, in an order that rotates
  each round. The report pairs turns on round and position.
- **Settings.** Arms start from the installed app's own preferences
  (`com.adhishthite.stok`), then force sounds, ducking, clipboard restore,
  correction learning, hold-to-lock, and usage metrics off. Each arm changes one
  factor. Rows go to `build/harness/history.db`, tagged `harness-<arm>`, and to
  `build/harness/runs/<run>.jsonl`.
- **Conditions.** Keep the lid open, the built-in speakers on at a fixed volume,
  and the room quiet. Before each arm block the harness measures the room with
  nothing playing. It pauses while the median is above `TRAIL_SILENCE_DB` minus
  5 dB, because room tone near the threshold keeps resetting the quiet window
  and runs the tail to `POST_ROLL_MAX_MS`. It also pauses when the output is not
  the built-in speakers, and it stops after 4 turns in a row without a transcript.
- **Limits.** Speakers into the laptop mic are not a person at dictation
  distance, so absolute tail and accuracy numbers are approximate. Paired arm
  differences are the result. No harness result has been recorded on Sarvam yet.
