#!/usr/bin/env bash
# captions.sh — audio -> phrase-level .srt + word-timestamps JSON. No network.
# Word timings come from (1) Kokoro's exact timings in <audio>.beats.json when tts.py made the audio,
# else (2) whisper.cpp, with word edges snapped to the audio energy envelope.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: captions.sh <audio> [-o PREFIX] [-m MODEL] [-l LANG] [--max-words N] [--max-sec S] [--whisper]

  <audio>         any audio/video file ffmpeg can read
  -o PREFIX       output prefix (default: audio path without extension)
  -m MODEL        whisper ggml model (default: ~/.ultra-motion/models/ggml-small.bin)
  -l LANG         whisper language code, or auto (default: en)
  --max-words N   max words per caption line in the .srt (default 6)
  --max-sec S     max seconds per caption line (default 2.8)
  --whisper       ignore Kokoro timings in <audio>.beats.json and transcribe with whisper

Writes:
  PREFIX.srt          phrase captions (split on punctuation, pauses > 0.5 s, N words, S seconds)
  PREFIX.words.json   {"source", "language", "duration", "words": [{"i", "text", "start", "end"}]} (seconds)
EOF
}

AUDIO=""; PREFIX=""; LANG_CODE="en"; MAXW=6; MAXS=2.8; FORCE_WHISPER=0
MODEL="${UM_WHISPER_MODEL:-${ULTRA_MOTION_HOME:-$HOME/.ultra-motion}/models/ggml-small.bin}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -o) PREFIX="${2:?-o needs a value}"; shift 2 ;;
    -m) MODEL="${2:?-m needs a value}"; shift 2 ;;
    -l) LANG_CODE="${2:?-l needs a value}"; shift 2 ;;
    --max-words) MAXW="${2:?}"; shift 2 ;;
    --max-sec) MAXS="${2:?}"; shift 2 ;;
    --whisper) FORCE_WHISPER=1; shift ;;
    -*) echo "captions.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) AUDIO="$1"; shift ;;
  esac
done
[[ -n "$AUDIO" ]] || { usage >&2; exit 2; }
[[ -f "$AUDIO" ]] || { echo "captions.sh: no such file: $AUDIO" >&2; exit 1; }
for dep in ffmpeg ffprobe python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "captions.sh: missing $dep (run doctor.sh)" >&2; exit 1; }
done
[[ -n "$PREFIX" ]] || PREFIX="${AUDIO%.*}"
mkdir -p "$(dirname "$PREFIX")"
BEATS="${AUDIO%.*}.beats.json"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ffmpeg -nostdin -hide_banner -loglevel error -y -i "$AUDIO" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$TMP/a16.wav"

SOURCE="whisper"
if [[ $FORCE_WHISPER -eq 0 && -f "$BEATS" ]] && python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("words") else 1)' "$BEATS" 2>/dev/null; then
  SOURCE="kokoro"
else
  command -v whisper-cli >/dev/null 2>&1 || { echo "captions.sh: missing whisper-cli (brew install whisper-cpp)" >&2; exit 1; }
  [[ -s "$MODEL" ]] || { echo "captions.sh: whisper model not found: $MODEL (run doctor.sh)" >&2; exit 1; }
  # -ml 1 + -sow: one segment per word, split on word boundaries.
  whisper-cli -m "$MODEL" -f "$TMP/a16.wav" -l "$LANG_CODE" -ml 1 -sow -ojf -of "$TMP/w" -np \
    -t "$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo 4)" >/dev/null 2>"$TMP/whisper.log" \
    || { echo "captions.sh: whisper-cli failed:" >&2; tail -5 "$TMP/whisper.log" >&2; exit 1; }
  [[ -s "$TMP/w.json" ]] || { echo "captions.sh: whisper produced no JSON" >&2; exit 1; }
fi

python3 -I - "$SOURCE" "$TMP" "$BEATS" "$PREFIX" "$MAXW" "$MAXS" "$LANG_CODE" <<'PY'
import array, json, math, re, sys, wave
source, tmp, beats_path, prefix = sys.argv[1:5]
maxw, maxs, lang = int(sys.argv[5]), float(sys.argv[6]), sys.argv[7]

with wave.open(f"{tmp}/a16.wav") as w:
    sr = w.getframerate()
    pcm = array.array("h", w.readframes(w.getnframes()))
dur = len(pcm) / sr

if source == "kokoro":
    d = json.load(open(beats_path, encoding="utf-8"))
    words = [{"text": x["text"], "start": x["start"], "end": x["end"]} for x in d["words"]]
    lang = d.get("lang", lang)
else:
    data = json.load(open(f"{tmp}/w.json", encoding="utf-8"))
    lang = data.get("result", {}).get("language", lang)
    words = []
    for seg in data.get("transcription", []):
        text = seg.get("text", "").strip()
        if not text or re.fullmatch(r"\[.*\]|\(.*\)", text):        # blanks and [MUSIC]-style tags
            continue
        s, e = seg["offsets"]["from"] / 1000.0, seg["offsets"]["to"] / 1000.0
        if words and not re.match(r"\w", text):                      # punctuation piece: glue to previous word
            words[-1]["text"] += text
            continue
        words.append({"text": text, "start": s, "end": e})
    # 1) whisper sometimes gives a word ~zero length and the next word the whole span: share it by characters
    for i in range(len(words) - 1):
        a, b = words[i], words[i + 1]
        if a["end"] - a["start"] < 0.08 and abs(a["end"] - b["start"]) < 0.02:
            la, lb = len(a["text"]), len(b["text"])
            cut = a["start"] + (b["end"] - a["start"]) * la / max(1, la + lb)
            a["end"], b["start"] = cut, cut
    # 2) snap word edges to the energy envelope (whisper starts words where the previous one ended)
    hop = sr // 100                                                 # 10 ms frames
    rms = [math.sqrt(sum(v * v for v in pcm[k:k + hop]) / hop) for k in range(0, len(pcm) - hop + 1, hop)]
    thr = max(rms) * 0.06 if rms else 0
    voiced = [r > thr for r in rms]
    for wd in words:
        f0, f1 = int(wd["start"] * 100), min(len(voiced), int(math.ceil(wd["end"] * 100)))
        idx = [k for k in range(f0, f1) if voiced[k]]
        if idx:
            wd["start"] = idx[0] / 100
            wd["end"] = max((idx[-1] + 1) / 100, wd["start"] + 0.06)

words = [{"i": i, "text": w["text"], "start": round(w["start"], 3), "end": round(w["end"], 3)} for i, w in enumerate(words)]
json.dump({"source": source, "language": lang, "duration": round(dur, 3), "words": words},
          open(prefix + ".words.json", "w", encoding="utf-8"), indent=1, ensure_ascii=False)

def ts(t):
    ms = int(round(t * 1000)); h, ms = divmod(ms, 3600000); m, ms = divmod(ms, 60000); s, ms = divmod(ms, 1000)
    return f"{h:02}:{m:02}:{s:02},{ms:03}"

lines, cur = [], []
for j, w in enumerate(words):
    cur.append(w)
    nxt = words[j + 1] if j + 1 < len(words) else None
    if (nxt is None or re.search(r"[.!?;:,]$", w["text"]) or nxt["start"] - w["end"] > 0.5
            or len(cur) >= maxw or w["end"] - cur[0]["start"] >= maxs):
        lines.append(cur); cur = []
with open(prefix + ".srt", "w", encoding="utf-8") as f:
    for n, ln in enumerate(lines, 1):
        f.write(f"{n}\n{ts(ln[0]['start'])} --> {ts(ln[-1]['end'])}\n{' '.join(w['text'] for w in ln)}\n\n")
print(f"source={source} words={len(words)} lines={len(lines)} duration={dur:.3f}s")
PY
echo "srt=$PREFIX.srt"
echo "words=$PREFIX.words.json"
