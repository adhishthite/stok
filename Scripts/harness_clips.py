#!/usr/bin/env python3
# Copyright 2026 Adhish Thite
# SPDX-License-Identifier: Apache-2.0

"""Generate the latency harness clip bank with Sarvam Bulbul TTS.

Reads Tools/Harness/phrases.json, renders each phrase in several speaker and pace
variants with bulbul:v3, trims and peak-normalizes the audio, and validates each
clip by transcribing it once over the speech-to-text REST route with the REST_MODEL
setting. A clip whose validation transcript misses too many words is regenerated, so a
TTS mistake is never scored later as an engine mistake. Phrases in a language Bulbul
does not speak are skipped with a notice.

Output: build/harness/clips/<clip_id>.wav and build/harness/clips/manifest.json.
The API key is read from SARVAM_API_KEY or the repo .env by key name. It is never
printed.
"""

from __future__ import annotations

import argparse
import array
import base64
import io
import json
import math
import os
import random
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import wave
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PHRASES = ROOT / "Tools" / "Harness" / "phrases.json"
OUT = ROOT / "build" / "harness" / "clips"
TTS_URL = "https://api.sarvam.ai/text-to-speech"
STT_URL = "https://api.sarvam.ai/speech-to-text"
AUTH_HEADER = "api-subscription-key"
TTS_MODELS = ("bulbul:v3",)
# Clips match the app's capture format: 16 kHz mono 16-bit PCM in a WAV container.
SAMPLE_RATE = 16000
# Phrase language to the BCP-47 code Bulbul takes. A phrase in any other language is
# skipped, because Bulbul speaks only Indian languages and English.
LANGUAGE_CODES = {
    "en": "en-IN", "hi": "hi-IN", "mr": "mr-IN", "ta": "ta-IN", "bn": "bn-IN",
    "gu": "gu-IN",
}
# bulbul:v3 speakers (short names, verified against the live speaker list of the API; an
# unknown name returns 400 with that list). They serve every v3 language, so each
# language gets a different slice of the roster. The v4-flash persona IDs
# (voice_language_style) answer 422 "beta, not available" on a standard key.
SPEAKERS = {
    "en": (
        "shubh", "simran", "ishita", "neha", "roopa", "dev", "rohan", "varun",
        "sunny", "ritu", "aditya", "amit", "kabir", "priya", "rahul", "sumit",
    ),
    "code_switch": ("shubh", "simran", "ishita", "sunny", "ritu", "aditya"),
    "hi": (
        "shubh", "ritu", "aditya", "priya", "neha", "rahul", "amit", "kavya",
        "ashutosh", "manan",
    ),
    "mr": ("ritu", "rupali", "soham", "shubh"),
    "ta": ("gokul", "vijay", "shruti"),
    "bn": ("roopa", "shreya", "anand"),
    "gu": ("pooja", "kavya", "ratan"),
}
# Clips per phrase: English gets the most, for speaker coverage.
VARIANTS = {"en": 4, "code_switch": 2, "hi": 3, "mr": 3, "paragraph": 2}
DEFAULT_VARIANTS = 2
UNSPACED_LANGUAGES = {"ja", "zh"}
# Style id, Bulbul pace (0.5 to 2.0), weight. Bulbul takes no free-text direction, so
# style is pace only.
STYLES = (
    ("conversational", 1.0, 4),
    ("brisk", 1.25, 2),
    ("deliberate", 0.8, 1),
    ("mid_pause", 0.95, 1),
    ("trailing", 0.9, 1),
)

FRAME_S = 0.01
ONSET_BELOW_PEAK_DB = 40.0
TRIM_LEAD_S = 0.03
TRIM_TAIL_S = 0.12
TARGET_PEAK_DBFS = -3.0
MAX_VALIDATION_WER = 0.2
# Outside English only gross failures are rejected: the validator may answer in another
# script or spelling, which is a finding to report, not a broken clip.
MAX_VALIDATION_WER_OTHER = 0.5
MIN_WORDS_PER_S, MAX_WORDS_PER_S = 1.0, 5.0


def api_key() -> str:
    key = os.environ.get("SARVAM_API_KEY", "")
    env = ROOT / ".env"
    if not key and env.exists():
        for line in env.read_text().splitlines():
            name, sep, value = line.partition("=")
            if sep and name.strip() == "SARVAM_API_KEY":
                key = value.strip().strip("'\"")
    if not key:
        sys.exit("SARVAM_API_KEY is not set in the environment or .env.")
    return key


def env_value(name: str, default: str) -> str:
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            key, sep, value = line.partition("=")
            if sep and key.strip() == name and value.strip():
                return value.strip().strip("'\"")
    return default


def send(request: urllib.request.Request, label: str, timeout: float = 120) -> dict:
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code in (429, 500, 503) and attempt < 3:
                time.sleep(2 ** (attempt + 1))
                continue
            detail = error.read()[:300].decode(errors="replace")
            raise RuntimeError(f"{label} HTTP {error.code}: {detail}") from None
        except (urllib.error.URLError, TimeoutError):
            if attempt < 3:
                time.sleep(2 ** (attempt + 1))
                continue
            raise
    raise RuntimeError("unreachable")


def tts_request(clip: dict, key: str) -> urllib.request.Request:
    """The POST /text-to-speech request for one clip. The key goes only in the header."""
    body = {
        "text": clip["text"],
        "language_code": clip["language_code"],
        "model": clip["tts_model"],
        "speaker": clip["voice"],
        "pace": clip["pace"],
        "speech_sample_rate": SAMPLE_RATE,
        "output_audio_codec": "wav",
        "enable_preprocessing": False,
    }
    return urllib.request.Request(
        TTS_URL,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", AUTH_HEADER: key},
    )


def stt_request(
    wav: bytes, key: str, model: str, language_code: str | None
) -> urllib.request.Request:
    """The POST /speech-to-text multipart request that validates one clip. The language
    is omitted for detection, as the app does when several languages are set."""
    boundary = "stok-harness-" + os.urandom(8).hex()
    fields = {"model": model, "mode": "verbatim"}
    if language_code:
        fields["language_code"] = language_code
    body = b"".join(
        f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'
        .encode()
        for name, value in fields.items()
    )
    body += (
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
        'filename="audio.wav"\r\nContent-Type: audio/wav\r\n\r\n'
    ).encode() + wav + f"\r\n--{boundary}--\r\n".encode()
    return urllib.request.Request(
        STT_URL,
        data=body,
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            AUTH_HEADER: key,
        },
    )


def decode_audio(response: dict) -> tuple[array.array, int]:
    """Returns mono int16 samples and the sample rate from a TTS response body."""
    audios = response.get("audios")
    if not audios:
        raise RuntimeError("TTS response has no audio")
    raw = base64.b64decode(audios[0])
    if raw[:4] != b"RIFF":
        raise RuntimeError("TTS audio is not a WAV file")
    with wave.open(io.BytesIO(raw)) as audio:
        if audio.getsampwidth() != 2:
            raise RuntimeError(f"unsupported sample width {audio.getsampwidth()}")
        rate, channels = audio.getframerate(), audio.getnchannels()
        samples = array.array("h", audio.readframes(audio.getnframes()))
    if sys.byteorder == "big":
        samples.byteswap()
    if channels > 1:
        samples = array.array("h", samples[::channels])
    if rate != SAMPLE_RATE:
        raise RuntimeError(f"expected {SAMPLE_RATE} Hz audio, got {rate} Hz")
    return samples, rate


def speech_bounds(samples: array.array, rate: int) -> tuple[int, int]:
    """First and last sample of frames within ONSET_BELOW_PEAK_DB of the loudest frame."""
    frame = max(1, int(rate * FRAME_S))
    levels = []
    for start in range(0, len(samples), frame):
        chunk = samples[start : start + frame]
        rms = math.sqrt(sum(s * s for s in chunk) / len(chunk)) if chunk else 0.0
        levels.append(20 * math.log10(rms / 32768) if rms > 0 else -120.0)
    if not levels:
        raise RuntimeError("empty audio")
    floor = max(levels) - ONSET_BELOW_PEAK_DB
    loud = [i for i, level in enumerate(levels) if level > floor]
    return loud[0] * frame, min(len(samples), (loud[-1] + 1) * frame)


def normalize_words(text: str, language: str = "en") -> list[str]:
    """Lowercased tokens with punctuation and symbols removed. Splits on whitespace
    rather than a word regex, because a regex word class breaks Devanagari and other
    Indic words at their vowel signs. Unspaced scripts compare character by character."""
    text = unicodedata.normalize("NFC", text.lower().replace("-", " "))
    cleaned = "".join(
        " " if unicodedata.category(ch)[0] in "PS" and ch != "'" else ch for ch in text
    )
    if language in UNSPACED_LANGUAGES:
        return [ch for ch in cleaned if not ch.isspace()]
    return cleaned.split()


def latin_share(text: str) -> float:
    """Share of letters in the Latin script, for spotting a romanized transcript."""
    letters = [ch for ch in text if ch.isalpha()]
    if not letters:
        return 0.0
    return sum("LATIN" in unicodedata.name(ch, "") for ch in letters) / len(letters)


def word_error_rate(reference: str, hypothesis: str, language: str = "en") -> float:
    ref = normalize_words(reference, language)
    hyp = normalize_words(hypothesis, language)
    if not ref:
        return 0.0 if not hyp else 1.0
    previous = list(range(len(hyp) + 1))
    for i, word in enumerate(ref, 1):
        current = [i] + [0] * len(hyp)
        for j, other in enumerate(hyp, 1):
            current[j] = min(
                previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (word != other)
            )
        previous = current
    return previous[-1] / len(ref)


def weighted(rng: random.Random, options):
    return rng.choices([o[:-1] for o in options], weights=[o[-1] for o in options])[0]


def plan(phrases: list[dict], variants: int | None, seed: int) -> list[dict]:
    """Every clip draws from its own seeded generator, keyed by clip id, so adding
    phrases or variants never changes the clips planned before. Phrases in a language
    without a Bulbul speaker are left out. Speakers cycle by variant so each phrase
    hears different voices."""
    clips = []
    index = 0
    for phrase in phrases:
        language = phrase.get("language", "en")
        code_switch = bool(phrase.get("code_switch"))
        if language not in LANGUAGE_CODES:
            continue
        kind = (
            "paragraph" if phrase.get("paragraph")
            else "code_switch" if code_switch else language
        )
        speakers = SPEAKERS["code_switch" if code_switch else language]
        count = variants or VARIANTS.get(kind, DEFAULT_VARIANTS)
        for variant in range(count):
            clip_id = f"{phrase['id']}-{variant}"
            rng = random.Random(f"{seed}:{clip_id}")
            style_id, pace = weighted(rng, STYLES)
            clips.append({
                "clip_id": clip_id,
                "phrase_id": phrase["id"],
                "text": phrase["text"],
                "language": language,
                "language_code": LANGUAGE_CODES[language],
                "code_switch": code_switch,
                "tts_model": TTS_MODELS[index % len(TTS_MODELS)],
                "voice": speakers[(rng.randrange(len(speakers)) + variant) % len(speakers)],
                "style": style_id,
                "pace": pace,
            })
            index += 1
    return clips


def skipped_languages(phrases: list[dict]) -> dict[str, int]:
    """Phrase count per language that plan() leaves out for lack of a Bulbul speaker."""
    counts: dict[str, int] = {}
    for phrase in phrases:
        language = phrase.get("language", "en")
        if language not in LANGUAGE_CODES:
            counts[language] = counts.get(language, 0) + 1
    return counts


def render(clip: dict, key: str, validate_model: str) -> dict:
    started = time.monotonic()
    response = send(tts_request(clip, key), f"{clip['tts_model']} TTS")
    tts_s = time.monotonic() - started
    samples, rate = decode_audio(response)
    onset, offset = speech_bounds(samples, rate)
    start = max(0, onset - int(TRIM_LEAD_S * rate))
    end = min(len(samples), offset + int(TRIM_TAIL_S * rate))
    trimmed = samples[start:end]
    peak = max(1, max(abs(s) for s in trimmed))
    gain = (32768 * 10 ** (TARGET_PEAK_DBFS / 20)) / peak
    scaled = array.array("h", (max(-32768, min(32767, int(s * gain))) for s in trimmed))
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        pcm = array.array("h", scaled)
        if sys.byteorder == "big":
            pcm.byteswap()
        audio.writeframes(pcm.tobytes())
    wav = buffer.getvalue()

    validation = send(
        stt_request(wav, key, validate_model, None if clip["code_switch"] else clip["language_code"]),
        f"{validate_model} STT",
    )
    heard = str(validation.get("transcript", "")).strip()
    speech_s = (offset - onset) / rate
    return {
        **clip,
        "wav": wav,
        "sample_rate": rate,
        "duration_s": round(len(scaled) / rate, 3),
        "speech_onset_s": round((onset - start) / rate, 3),
        "speech_offset_s": round((offset - start) / rate, 3),
        "speech_s": round(speech_s, 3),
        "words": len(normalize_words(clip["text"], clip["language"])),
        "tts_request_s": round(tts_s, 2),
        "validation_model": validate_model,
        "validation_text": heard,
        "validation_wer": round(word_error_rate(clip["text"], heard, clip["language"]), 3),
        "validation_romanized": latin_share(heard) > 0.5 > latin_share(clip["text"]),
    }


def acceptable(result: dict) -> str | None:
    if result["language"] not in UNSPACED_LANGUAGES:
        rate = result["words"] / max(0.1, result["speech_s"])
        if not MIN_WORDS_PER_S <= rate <= MAX_WORDS_PER_S:
            return f"speech rate {rate:.1f} words/s"
    elif result["speech_s"] > 0.35 * result["words"]:
        # Characters, not words: a read-aloud direction tag shows as a long clip.
        return f"clip too long for {result['words']} characters"
    if result["code_switch"]:
        return None
    if latin_share(result["validation_text"]) > 0.5 > latin_share(result["text"]):
        # Romanized answer to a native-script clip: the words cannot be compared.
        return None
    limit = MAX_VALIDATION_WER if result["language"] == "en" else MAX_VALIDATION_WER_OTHER
    if result["validation_wer"] > limit:
        return f"validation WER {result['validation_wer']:.2f}"
    return None


def build_clip(clip: dict, key: str, validate_model: str, attempts: int) -> dict:
    last = None
    for attempt in range(attempts):
        result = render(clip, key, validate_model)
        problem = acceptable(result)
        if problem is None:
            result["attempts"] = attempt + 1
            return result
        last = problem
    raise RuntimeError(f"{clip['clip_id']} rejected after {attempts} attempts: {last}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--variants", type=int,
                        help="clips per phrase (default: per language, see VARIANTS)")
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--attempts", type=int, default=3)
    parser.add_argument("--seed", type=int, default=38)
    parser.add_argument("--limit", type=int, help="only the first N clips (smoke test)")
    parser.add_argument("--force", action="store_true", help="regenerate existing clips")
    args = parser.parse_args(argv)

    key = api_key()
    validate_model = env_value("REST_MODEL", "saaras:v4")
    phrases = json.loads(PHRASES.read_text())
    for language, count in sorted(skipped_languages(phrases).items()):
        print(f"skipping {count} '{language}' phrase(s): no Bulbul speaker for that language")
    clips = plan(phrases, args.variants, args.seed)
    if args.limit:
        clips = clips[: args.limit]
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "manifest.json"
    existing = {}
    if manifest_path.exists() and not args.force:
        existing = {c["clip_id"]: c for c in json.loads(manifest_path.read_text())["clips"]}
    todo = [c for c in clips if c["clip_id"] not in existing
            or not (OUT / f"{c['clip_id']}.wav").exists()]
    print(f"{len(clips)} clips planned, {len(todo)} to generate, validation by {validate_model}")

    failures = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(build_clip, c, key, validate_model, args.attempts): c for c in todo}
        for done, future in enumerate(as_completed(futures), 1):
            clip = futures[future]
            try:
                result = future.result()
            except Exception as error:  # noqa: BLE001 - report and continue with the rest
                failures.append(f"{clip['clip_id']}: {error}")
                print(f"[{done}/{len(todo)}] {clip['clip_id']} FAILED: {error}", flush=True)
                continue
            (OUT / f"{result['clip_id']}.wav").write_bytes(result.pop("wav"))
            existing[result["clip_id"]] = result
            print(
                f"[{done}/{len(todo)}] {result['clip_id']} {result['tts_model']} "
                f"{result['speech_s']:.1f}s wer={result['validation_wer']:.2f} "
                f"attempts={result['attempts']}",
                flush=True,
            )
    ordered = [existing[c["clip_id"]] for c in clips if c["clip_id"] in existing]
    manifest_path.write_text(json.dumps({"clips": ordered}, indent=2) + "\n")
    print(f"manifest: {len(ordered)} clips, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
