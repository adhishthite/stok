# Copyright 2026 Adhish Thite
# SPDX-License-Identifier: Apache-2.0

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts"))

import harness_clips  # noqa: E402
import harness_report  # noqa: E402


def row(arm, round_, position, total, start, wer=0.0, words=10, **extra):
    return {
        "run_id": "r1", "round": round_, "turn_in_block": position, "arm": arm,
        "outcome": "success", "total_ms": total, "capture_start_ms": start,
        "accuracy": {"wer": wer, "reference_words": words, "first_word_hit": True,
                     "last_word_hit": wer == 0.0},
        **extra,
    }


class HarnessReportTests(unittest.TestCase):
    def test_pooled_wer_weights_by_reference_words(self):
        rows = [row("baseline", 0, 0, 500, 200, wer=1.0, words=2),
                row("baseline", 0, 1, 500, 200, wer=0.0, words=18)]
        self.assertAlmostEqual(harness_report.pooled_wer(rows), 2 / 20)

    def test_code_switched_clips_do_not_count_toward_wer(self):
        rows = [row("baseline", 0, 0, 500, 200, wer=1.0, code_switch=True),
                row("baseline", 0, 1, 500, 200, wer=0.0)]
        self.assertEqual(harness_report.pooled_wer(rows), 0.0)

    def test_other_languages_stay_out_of_the_headline_wer(self):
        rows = [row("baseline", 0, 0, 500, 200, wer=1.0, language="mr"),
                row("baseline", 0, 1, 500, 200, wer=0.0)]
        self.assertEqual(harness_report.pooled_wer(rows), 0.0)
        self.assertEqual(harness_report.pooled_wer(rows, english_only=False), 0.5)

    def test_romanized_transcript_of_devanagari_is_flagged(self):
        self.assertTrue(harness_report.romanized(
            {"reference": "मी थोड्या वेळात पोहोचतो.", "hypothesis": "Mi thodya velat pohochto."}))
        self.assertFalse(harness_report.romanized(
            {"reference": "मी थोड्या वेळात पोहोचतो.", "hypothesis": "मी थोड्या वेळात पोहोचतो."}))

    def test_paired_deltas_match_round_and_position(self):
        rows = [row("baseline", 0, 0, 600, 200), row("baseline", 0, 1, 700, 210),
                row("warm90", 0, 0, 550, 3), row("warm90", 0, 1, 690, 2),
                row("warm90", 1, 0, 100, 1)]
        self.assertEqual(sorted(harness_report.paired_deltas(rows, "warm90", "total_ms")),
                         [-50, -10])

    def test_direct_and_acoustic_rows_are_not_pooled(self):
        rows = [row("baseline", 0, i, 600, 200, run_id="a", mode="acoustic") for i in range(6)]
        rows += [row("baseline", 0, i, None, None, run_id="d", mode="direct",
                     roundtrip_ms=400) for i in range(6)]
        rows += [row("flush0", 0, i, None, None, run_id="d", mode="direct",
                     roundtrip_ms=320) for i in range(6)]
        report = harness_report.build_report(rows)
        self.assertEqual(set(report["arms"]),
                         {"baseline [acoustic]", "baseline [direct]", "flush0 [direct]"})
        self.assertEqual(report["paired"]["flush0 [direct]/roundtrip_ms"]["median_delta"], -80)
        self.assertEqual(set(report["by_language"]), {"[acoustic] en", "[direct] en"})

    def test_unsettled_turns_are_not_paired(self):
        rows = [row("baseline", 0, 0, 600, 200), {**row("aligned", 0, 0, 400, 200),
                                                   "outcome": "empty"}]
        self.assertEqual(harness_report.paired_deltas(rows, "aligned", "total_ms"), [])

    def test_report_renders_with_every_section(self):
        rows = [row("baseline", 0, i, 600 + i, 200, mic_state_at_keydown="cold")
                for i in range(6)]
        rows += [row("warm90", 0, i, 590 + i, 3, mic_state_at_keydown="warm") for i in range(6)]
        text = harness_report.render(harness_report.build_report(rows))
        for heading in ("Latency by arm", "Word accuracy", "Capture start", "Paired against"):
            self.assertIn(heading, text)


class ScriptAwareWerTests(unittest.TestCase):
    def test_native_and_romanized_renderings_match(self):
        cases = [
            ("मी थोड्या वेळात पोहोचतो.", "Mi thodya velat pohochto."),
            ("Ship it.", "शिप इट।"),
            ("Kaalni meeting saanje che.", "કાલની મીટિંગ સાંજે છે."),
            ("Naalaikku koottam maalaiyil.", "நாளைக்கு கூட்டம் மாலையில்."),
            ("Bhai kal ki meeting ke liye ek short deck banana hai.",
             "भाई कल की मीटिंग के लिए एक शॉर्ट डेक बनाना है।"),
        ]
        for reference, hypothesis in cases:
            with self.subTest(reference=reference):
                self.assertEqual(harness_report.script_aware_wer(reference, hypothesis)[0], 0.0)

    def test_english_spelled_in_devanagari_mostly_matches(self):
        wer, words = harness_report.script_aware_wer(
            "Listen, mujhe ek quick summary chahiye of today's standup.",
            "लिसन, मुझे एक क्विक समरी चाहिए ऑफ टुडेज स्टँडअप.")
        self.assertEqual(words, 9)
        self.assertLessEqual(wer, 1 / 9)

    def test_different_words_still_count_as_errors(self):
        self.assertEqual(harness_report.script_aware_wer("Ship it.", "Shipment.")[0], 1.0)
        self.assertAlmostEqual(
            harness_report.script_aware_wer("the cat sat", "the dog sat")[0], 1 / 3)
        self.assertEqual(harness_report.script_aware_wer("Sounds good.", "")[0], 1.0)

    def test_numbers_are_spelled_like_the_harness_scorer(self):
        self.assertEqual(
            harness_report.script_aware_wer("Call me at 5 pm", "call me at five pm")[0], 0.0)
        self.assertEqual(harness_report.script_tokens("२०२६"), ["two", "thousand", "twenty", "six"])

    def test_vowel_signs_do_not_split_words(self):
        self.assertEqual(harness_report.script_tokens("मी थोड्या वेळात."), ["मी", "थोड्या", "वेळात"])

    def test_report_shows_raw_and_script_aware_wer_separately(self):
        rows = [row("baseline", 0, i, 600, 200, wer=1.0, words=4, language="mr",
                    reference="मी थोड्या वेळात पोहोचतो.",
                    hypothesis="Mi thodya velat pohochto.") for i in range(6)]
        report = harness_report.build_report(rows)
        summary = report["arms"]["baseline"]
        self.assertEqual(summary["pooled_wer_all"], 1.0)
        self.assertEqual(summary["script_wer_all"], 0.0)
        self.assertEqual(report["by_language"]["mr"]["script_wer"], 0.0)
        text = harness_report.render(report)
        self.assertIn("script-aware", text)

    def test_pairing_can_use_another_baseline_arm(self):
        rows = [row("fast", 0, i, None, None, mode="direct", roundtrip_ms=240) for i in range(6)]
        rows += [row("simulated", 0, i, None, None, mode="direct", roundtrip_ms=170)
                 for i in range(6)]
        try:
            harness_report.use_baseline("fast")
            report = harness_report.build_report(rows)
        finally:
            harness_report.use_baseline("baseline")
        self.assertEqual(report["paired"]["simulated/roundtrip_ms"]["median_delta"], -70)
        self.assertIsNone(report["arms"]["fast"]["stream_type"])
        tagged = [{**r, "stream_type": "simulated"} for r in rows if r["arm"] == "simulated"]
        self.assertEqual(harness_report.arm_summary(tagged)["stream_type"], "simulated")
        self.assertNotIn("fast/roundtrip_ms", report["paired"])


class HarnessClipTests(unittest.TestCase):
    def test_word_error_rate_ignores_case_and_punctuation(self):
        self.assertEqual(harness_clips.word_error_rate("Ship it.", "ship it"), 0.0)
        self.assertEqual(harness_clips.word_error_rate("Ship it.", "Shipment."), 1.0)

    def test_speech_bounds_skip_leading_and_trailing_silence(self):
        import array
        rate = 1000
        samples = array.array("h", [0] * 200 + [8000] * 300 + [0] * 500)
        onset, offset = harness_clips.speech_bounds(samples, rate)
        self.assertEqual((onset, offset), (200, 500))

    def test_plan_cycles_tts_models(self):
        clips = harness_clips.plan([{"id": "a", "text": "one two"}], variants=4, seed=1)
        self.assertEqual([c["tts_model"] for c in clips],
                         [harness_clips.TTS_MODELS[i % len(harness_clips.TTS_MODELS)] for i in range(4)])

    def test_plan_uses_real_bulbul_speakers_and_languages(self):
        phrases = [
            {"id": "e", "text": "one two"},
            {"id": "h", "text": "x", "language": "hi"},
            {"id": "m", "text": "x", "language": "mr"},
            {"id": "c", "text": "kal ki meeting", "code_switch": True},
        ]
        clips = harness_clips.plan(phrases, variants=6, seed=1)
        self.assertEqual({c["language_code"] for c in clips if c["phrase_id"] == "e"},
                         {"en-IN"})
        self.assertEqual({c["language_code"] for c in clips if c["phrase_id"] == "h"},
                         {"hi-IN"})
        for clip in clips:
            kind = "code_switch" if clip["code_switch"] else clip["language"]
            self.assertIn(clip["voice"], harness_clips.SPEAKERS[kind])
            self.assertIn(clip["tts_model"], harness_clips.TTS_MODELS)
            self.assertTrue(0.5 <= clip["pace"] <= 2.0)

    def test_phrases_in_unsupported_languages_are_skipped(self):
        phrases = [{"id": "a", "text": "x"}, {"id": "s", "text": "y", "language": "es"},
                   {"id": "j", "text": "z", "language": "ja"}]
        clips = harness_clips.plan(phrases, variants=1, seed=1)
        self.assertEqual([c["phrase_id"] for c in clips], ["a"])
        self.assertEqual(harness_clips.skipped_languages(phrases), {"es": 1, "ja": 1})

    def test_tts_request_shape(self):
        clip = {"text": "Hello", "language_code": "en-IN", "tts_model": "bulbul:v3",
                "voice": "shubh", "pace": 1.25}
        request = harness_clips.tts_request(clip, "secret")
        self.assertEqual(request.full_url, "https://api.sarvam.ai/text-to-speech")
        self.assertEqual(request.get_header("Api-subscription-key"), "secret")
        self.assertIsNone(request.get_header("Authorization"))
        body = json.loads(request.data)
        self.assertEqual(body, {
            "text": "Hello", "language_code": "en-IN", "model": "bulbul:v3",
            "speaker": "shubh", "pace": 1.25, "speech_sample_rate": 16000,
            "output_audio_codec": "wav", "enable_preprocessing": False,
        })

    def test_stt_request_is_multipart_with_model_and_optional_language(self):
        with_language = harness_clips.stt_request(b"RIFFdata", "secret", "saaras:v4", "hi-IN")
        self.assertEqual(with_language.full_url, "https://api.sarvam.ai/speech-to-text")
        self.assertEqual(with_language.get_header("Api-subscription-key"), "secret")
        self.assertTrue(with_language.get_header("Content-type")
                        .startswith("multipart/form-data; boundary="))
        for needle in (b'name="model"\r\n\r\nsaaras:v4', b'name="mode"\r\n\r\nverbatim',
                       b'name="language_code"\r\n\r\nhi-IN', b"RIFFdata"):
            self.assertIn(needle, with_language.data)
        self.assertNotIn(b"secret", with_language.data)
        detected = harness_clips.stt_request(b"RIFFdata", "secret", "saaras:v4", None)
        self.assertNotIn(b"language_code", detected.data)

    def test_decode_audio_reads_base64_wav_and_rejects_other_rates(self):
        import base64
        import io
        import wave

        def wav_b64(rate):
            buffer = io.BytesIO()
            with wave.open(buffer, "wb") as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(rate)
                audio.writeframes(b"\x01\x00\x02\x00")
            return base64.b64encode(buffer.getvalue()).decode()

        samples, rate = harness_clips.decode_audio({"audios": [wav_b64(16000)]})
        self.assertEqual((list(samples), rate), ([1, 2], 16000))
        with self.assertRaises(RuntimeError):
            harness_clips.decode_audio({"audios": [wav_b64(24000)]})
        with self.assertRaises(RuntimeError):
            harness_clips.decode_audio({"audios": []})

    def test_adding_phrases_does_not_change_planned_clips(self):
        first = harness_clips.plan([{"id": "a", "text": "one two"}], None, 38)
        more = harness_clips.plan(
            [{"id": "a", "text": "one two"}, {"id": "b", "text": "x", "language": "hi"}],
            None, 38)
        self.assertEqual(first, more[: len(first)])

    def test_devanagari_words_are_not_split_at_vowel_signs(self):
        self.assertEqual(harness_clips.normalize_words("मी थोड्या वेळात.", "mr"),
                         ["मी", "थोड्या", "वेळात"])

    def test_romanized_validation_skips_the_wer_gate(self):
        result = {"language": "mr", "code_switch": False, "words": 3, "speech_s": 1.5,
                  "text": "मी थोड्या वेळात.", "validation_text": "Mi thodya velat.",
                  "validation_wer": 1.0}
        self.assertIsNone(harness_clips.acceptable(result))


if __name__ == "__main__":
    unittest.main()
