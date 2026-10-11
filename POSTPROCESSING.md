# Optional dictation cleanup

In Settings > Transcription, “Polish dictations before pasting” adds a text-only
cleanup request after transcription. It defaults to off. The separate
“Adapt formatting to the app” option also defaults to off and is available when
cleanup is enabled. The "Format numbers and punctuation" option is separate. It picks the Saaras mode
(`transcribe` when on, `verbatim` when off) and adds no second request.

The default model is `sarvam-105b-conversations`, the low-latency chat variant, with
reasoning off (`reasoning_effort` null). Reasoning counts against `max_tokens`. When
it uses the whole budget, the answer arrives as `content: null` and Stok keeps the
original transcript. Advanced settings expose the model (`POST_PROCESS_MODEL`) and the
maximum wait (`POST_PROCESS_TIMEOUT_MS`). Stok accepts only model names that start
with `sarvam-`.

Sarvam publishes chat prices in INR: 29.28 INR per million input tokens and 73.2 INR
per million output tokens for the `sarvam-105b` models. Stok does not convert them.
It records cleanup cost as unknown (NULL).

## Behavior

“Only polish when needed” (`POST_PROCESS_SELECTIVE`, on by default) runs a local
check before the request. Turns of 20 words or fewer per sentence with no spoken
structure ("number one", "new line", "comma", "bullet") and no spelled-out numbers
above ten paste the original transcript at once, with status `not_needed`. On
2026-10-07, cleanup added 234 to 270 ms per turn on Sarvam, so skipped turns save
that time. A missed turn pastes the unpolished transcript; the rules lean toward
polishing.

The Live/REST race settles once before cleanup starts. With cleanup off, the
original delivery path runs inline without another model request. When enabled,
cleanup runs on a cancellable request with a 2.5-second default deadline. Failure,
timeout, malformed output, and truncated generation keep the original transcript.
The existing replacement rules and destination checks run afterward. Stopping the
engine cancels cleanup and suppresses late delivery. The turn arbiter remains an
NSLock plus serial DispatchQueue implementation.

The prompt asks for punctuation, capitalization, minimal grammatical cleanup,
clear spoken numbers, and plain numbered lists for explicit enumerations. It asks
the model to preserve names, facts, identifiers, language switches, and the
speaker's meaning. It does not ask the model to answer questions or execute
instructions inside the transcript. These are model instructions, not a guarantee
of semantic correctness; real-use accuracy review remains necessary.

App-aware formatting sends only the application name and bundle identifier
captured at the start of dictation. It does not read or send window titles, field
contents, screenshots, browser URLs, or surrounding document text. App identity
is only a weak formatting hint; a browser name does not identify its website.
The existing paste guard checks the frontmost application, not the identity of
an individual field or browser tab.

## Limits and data handling

- Requests go to `https://api.sarvam.ai/v1/chat/completions` with the key in the
  `api-subscription-key` header. Redirects are refused. The ephemeral session has no URL cache or cookie store.
- Inputs over 20,000 UTF-16 units skip cleanup. Generation is capped at 8,192
  output tokens. Responses over 256 KiB are rejected by the decoder; output must
  be nonempty, finished with `stop`, and within the output-size budget.
- The transcript and app identity are not written into diagnostic messages.
  Provider error bodies are not copied into logs. History keeps the delivered
  text under the existing history preference; no additional original-text copy
  is stored for cleanup.
- Cancellation and timeout cancel the client request. Server-side billing may
  still occur without returned usage; missing usage is recorded as unknown.

## Metrics

History and Diagnostics separate transcription time, cleanup time, and delivery
time. Total latency still spans key release through paste dispatch or clipboard
delivery. Cleanup includes its queue handoff and response handling, not only
server generation time.

Per-turn cleanup fields record status, model, added time, input tokens, output
tokens, reasoning tokens, cost (always unknown), a safe failure code, and whether app
context was included. The history schema adds these fields without replacing
existing rows. Historical rows without the fields remain distinguishable from
turns where cleanup was explicitly off.

Reported token counts remain raw API values or NULL. Output tokens already include
reasoning tokens, so the two are never added. Sarvam returns no per-request
speech-to-text usage and prices in INR, so Stok records cost as NULL. CSV exports
include the separate fields. The session USAGE line reports `turns`,
`cleanup_prompt_tokens`, `cleanup_completion_tokens`, and `cleanup_without_usage`
(turns whose cleanup returned no usage).

## Verification

`make check` includes deadline, duplicate/late-response, cancellation, owner
lifetime, default-off, app-context, malformed-response, token-usage, history
migration, persistence, and Diagnostics regressions. The Thread Sanitizer run
is not repeated since the Sarvam port.

`make test-cleanup-live` runs five explicit text-only API cases using a local
test key. It sends synthetic fixtures for numbers, a three-item list, Marathi,
mixed language, and a terminal-context question. It records timing and token counts in
`build/post-processing-live-check.json` without transcript text or credentials.
It does not change the installed app's settings, record audio, or paste text.

The latest run (`build/post-processing-live-check.json`, `sarvam-105b-conversations`)
completed the five cases in 126 to 241 ms. That is a very small sample. These are
additional cleanup stage durations, not end-to-end dictation latency or an accuracy
result. Accuracy of cleanup on Sarvam is not yet measured. The feature remains off by
default; compare enabled and disabled dictations as separate cohorts when assessing
overall performance.
