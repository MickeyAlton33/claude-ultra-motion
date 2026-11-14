#!/usr/bin/env python3
"""tts.py — Kokoro TTS: text file + voice -> WAV, prints exact durations.

Each paragraph (blank-line separated) of the input is one beat. Writes:
  OUT.wav             24 kHz mono, beats joined with --gap seconds of silence
  OUT.beats.json      {"duration", "beats": [{"beat", "text", "start", "end", "words"}], "words": [...]}
                      "words" are Kokoro's own per-word timings (exact for this audio; English voices
                      only), which captions.sh prefers over whisper when present.

Network: the first use of a voice (or a fresh machine) downloads it from Hugging Face
(hexgrad/Kokoro-82M, Apache-2.0) into ~/.ultra-motion/hf. Otherwise runs offline.
Runs itself under ~/.ultra-motion/venv if the current Python lacks kokoro.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import warnings

UM_HOME = os.environ.get("ULTRA_MOTION_HOME", os.path.expanduser("~/.ultra-motion"))
VENV = os.path.join(UM_HOME, "venv")
VENV_PY = os.path.join(VENV, "bin", "python")
REPO = "hexgrad/Kokoro-82M"
SR = 24000

LANGS = {
    "a": "American English", "b": "British English", "e": "Spanish", "f": "French",
    "h": "Hindi", "i": "Italian", "j": "Japanese", "p": "Brazilian Portuguese", "z": "Mandarin",
}
INSTALL_HINT = (
    f"uv venv --python 3.12 {VENV} && "
    f"uv pip install --python {VENV_PY} 'kokoro>=0.9.4' soundfile pip   (and: brew install espeak-ng)"
)


def ensure_kokoro_python() -> None:
    """Re-exec under the Ultra Motion venv when kokoro isn't importable here."""
    import importlib.util

    if importlib.util.find_spec("kokoro") and importlib.util.find_spec("soundfile"):
        return
    if os.path.realpath(sys.prefix) != os.path.realpath(VENV) and os.access(VENV_PY, os.X_OK):
        os.execv(VENV_PY, [VENV_PY, os.path.abspath(__file__), *sys.argv[1:]])
    sys.exit(f"tts.py: kokoro is not installed. Fix: {INSTALL_HINT}")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Kokoro TTS: text file (one paragraph per beat) -> WAV + beats JSON; prints durations.",
        epilog="Voices: af_heart af_bella am_michael am_fenrir bf_emma bm_george ... "
        "(full list: https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md). "
        "Language defaults to the voice's first letter: " + ", ".join(f"{k}={v}" for k, v in LANGS.items()),
    )
    p.add_argument("input", help="UTF-8 text file, or - for stdin")
    p.add_argument("-o", "--output", required=True, help="output .wav path")
    p.add_argument("-v", "--voice", default="af_heart", help="Kokoro voice (default: af_heart)")
    p.add_argument("-l", "--lang", default=None, help="Kokoro lang code (default: first letter of voice)")
    p.add_argument("-s", "--speed", type=float, default=1.0, help="speaking rate, 0.5–2.0 (default 1.0)")
    p.add_argument("-g", "--gap", type=float, default=0.35, help="silence between beats in seconds (default 0.35)")
    return p.parse_args()


def read_beats(path: str) -> list[str]:
    text = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
    beats = [" ".join(par.split()) for par in text.replace("\r\n", "\n").split("\n\n")]
    beats = [b for b in beats if b]
    if not beats:
        sys.exit("tts.py: input has no text")
    return beats


def voice_cached(voice: str) -> bool:
    hub = os.path.join(os.environ["HF_HOME"], "hub", "models--hexgrad--Kokoro-82M", "snapshots")
    if not os.path.isdir(hub):
        return False
    for snap in os.listdir(hub):
        d = os.path.join(hub, snap)
        if os.path.exists(os.path.join(d, "kokoro-v1_0.pth")) and os.path.exists(os.path.join(d, "voices", f"{voice}.pt")):
            return True
    return False


def main() -> None:
    args = parse_args()
    if not 0.5 <= args.speed <= 2.0:
        sys.exit("tts.py: --speed must be between 0.5 and 2.0")
    if args.gap < 0:
        sys.exit("tts.py: --gap must be >= 0")
    lang = args.lang or args.voice[0]
    if lang not in LANGS:
        sys.exit(f"tts.py: unknown lang '{lang}'. Use one of: {', '.join(LANGS)}")
    beats = read_beats(args.input)

    os.environ.setdefault("HF_HOME", os.path.join(UM_HOME, "hf"))
    if voice_cached(args.voice):
        os.environ.setdefault("HF_HUB_OFFLINE", "1")
    else:
        print(f"tts.py: downloading Kokoro weights/voice '{args.voice}' from Hugging Face (first use)…", file=sys.stderr)

    ensure_kokoro_python()
    warnings.filterwarnings("ignore")
    import numpy as np
    import soundfile as sf
    from kokoro import KPipeline

    pipe = KPipeline(lang_code=lang, repo_id=REPO)
    gap = np.zeros(int(round(args.gap * SR)), dtype=np.float32)
    chunks: list[np.ndarray] = []
    meta = []
    all_words: list[dict] = []
    t = 0.0
    for i, beat in enumerate(beats, 1):
        parts = []
        beat_words: list[dict] = []
        chunk_t = 0.0  # where the current Kokoro chunk starts inside this beat
        for result in pipe(beat, voice=args.voice, speed=args.speed):
            audio = result.audio if hasattr(result, "audio") else result[2]
            if audio is None:
                continue
            arr = audio.detach().cpu().numpy() if hasattr(audio, "detach") else np.asarray(audio)
            for tok in (getattr(result, "tokens", None) or []):
                if tok.start_ts is None or tok.end_ts is None or not tok.text.strip():
                    continue
                if beat_words and not re.match(r"\w", tok.text):  # punctuation: glue to the previous word
                    beat_words[-1]["text"] += tok.text
                    continue
                beat_words.append({"text": tok.text, "start": chunk_t + tok.start_ts, "end": chunk_t + tok.end_ts})
            parts.append(arr)
            chunk_t += len(arr) / SR
        if not parts:
            sys.exit(f"tts.py: Kokoro produced no audio for beat {i}: {beat[:60]!r}")
        a = np.concatenate(parts).astype(np.float32)
        if i > 1 and len(gap):
            chunks.append(gap)
            t += len(gap) / SR
        start = t
        chunks.append(a)
        t += len(a) / SR
        for w in beat_words:
            w["start"] = round(start + w["start"], 3)
            w["end"] = round(start + w["end"], 3)
            w["i"] = len(all_words)
            all_words.append(w)
        meta.append({"beat": i, "text": beat, "start": round(start, 3), "end": round(t, 3),
                     "duration": round(t - start, 3), "words": beat_words})

    out = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    full = np.concatenate(chunks)
    peak = float(np.max(np.abs(full))) if len(full) else 0.0
    if peak > 0.98:  # keep true peak under ~-0.2 dBFS; deliver.sh does final loudness
        full = full * (0.98 / peak)
    sf.write(out, full, SR, subtype="PCM_16")
    beats_path = os.path.splitext(out)[0] + ".beats.json"
    with open(beats_path, "w", encoding="utf-8") as f:
        json.dump({"voice": args.voice, "lang": lang, "speed": args.speed, "sample_rate": SR,
                   "duration": round(t, 3), "beats": meta,
                   "words_source": "kokoro" if all_words else None,
                   "words": [{"i": w["i"], "text": w["text"], "start": w["start"], "end": w["end"]} for w in all_words]},
                  f, indent=1, ensure_ascii=False)

    for m in meta:
        print(f"beat {m['beat']:>2}  {m['start']:7.3f} → {m['end']:7.3f}  ({m['duration']:.3f}s)  {m['text'][:60]}")
    print(f"wav={out}")
    print(f"beats={beats_path}")
    print(f"words={len(all_words)} (kokoro timings)" if all_words else "words=0 (this language has no Kokoro timings; captions.sh will use whisper)")
    print(f"duration={t:.3f}s")


if __name__ == "__main__":
    main()
