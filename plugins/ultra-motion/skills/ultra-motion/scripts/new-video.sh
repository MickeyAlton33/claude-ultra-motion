#!/usr/bin/env bash
# new-video.sh — scaffold an Ultra Motion video project:
# HyperFrames project + script.md, storyboard.md, assets/, audio/, renders/, review/, credits.md,
# a CLAUDE.md that starts with the style contract, and a git repo with a first commit.
# Network: `npx hyperframes init` fetches the HyperFrames CLI from npm if it isn't cached.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF_DIR="$(cd "$SCRIPT_DIR/../references" && pwd)"

usage() {
  cat <<'EOF'
Usage: new-video.sh <name> [--dir PARENT] [--resolution landscape|portrait|square] [--no-git]

  <name>          project folder name: lowercase letters, digits and dashes (e.g. coffee-teaser)
  --dir PARENT    where to create it (default: current directory)
  --resolution    HyperFrames canvas preset (default: landscape = 1920x1080)
  --no-git        don't git init / commit

Creates PARENT/<name>/ and prints the next steps.
EOF
}

NAME=""; PARENT="$PWD"; RES="landscape"; GIT=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dir) PARENT="${2:?--dir needs a path}"; shift 2 ;;
    --resolution) RES="${2:?--resolution needs a value}"; shift 2 ;;
    --no-git) GIT=0; shift ;;
    -*) echo "new-video.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) [[ -z "$NAME" ]] || { echo "new-video.sh: only one name allowed" >&2; exit 2; }; NAME="$1"; shift ;;
  esac
done
[[ -n "$NAME" ]] || { usage >&2; exit 2; }
[[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "new-video.sh: name must be lowercase letters, digits, dashes" >&2; exit 2; }
case "$RES" in landscape|portrait|square) ;; *) echo "new-video.sh: --resolution must be landscape, portrait or square" >&2; exit 2 ;; esac

for dep in npx git; do
  command -v "$dep" >/dev/null 2>&1 || { echo "new-video.sh: missing dependency: $dep (run doctor.sh)" >&2; exit 1; }
done
[[ -d "$PARENT" ]] || { echo "new-video.sh: parent dir does not exist: $PARENT" >&2; exit 1; }
PROJ="$PARENT/$NAME"
[[ ! -e "$PROJ" ]] || { echo "new-video.sh: $PROJ already exists — pick another name" >&2; exit 1; }

echo "→ hyperframes init $NAME ($RES)"
( cd "$PARENT" && npx --yes hyperframes init "$NAME" --non-interactive --example blank --resolution "$RES" --skip-skills >/dev/null )
[[ -f "$PROJ/index.html" ]] || { echo "new-video.sh: hyperframes init did not create $PROJ/index.html" >&2; exit 1; }

mkdir -p "$PROJ"/{assets,audio,renders,review}
touch "$PROJ/assets/.gitkeep" "$PROJ/audio/.gitkeep"

cat > "$PROJ/script.md" <<'EOF'
# Script

Target duration: __ s · VO: yes/no · voice: __ · language: __
Words ≈ seconds × 2.5. Put the VO text (one paragraph per beat) in `audio/vo.txt`.

| # | Target s | Purpose of the beat | VO line | On-screen text (≤ 7 words) |
|---|---------:|---------------------|---------|----------------------------|
| 1 |          |                     |         |                            |
EOF

cp "$REF_DIR/storyboard-template.md" "$PROJ/storyboard.md"

cat > "$PROJ/credits.md" <<'EOF'
# Credits & licences

Every third-party file used in this video. Prefer CC0. No NC licences for commercial work.

| File | Title | Author | Source URL | Licence | Licence URL | Downloaded | Used for |
|------|-------|--------|------------|---------|-------------|------------|----------|

## Generated locally (no third-party rights)
- VO: Kokoro-82M (Apache-2.0)
EOF

cat > "$PROJ/.gitignore" <<'EOF'
node_modules/
renders/
review/
.debug/
.DS_Store
*.mp4
*.mov
*.webm
*.gif
*.wav
*.mp3
*.m4a
*.aiff
.env*
EOF

# CLAUDE.md: Ultra Motion header + style contract on top, HyperFrames' own guidance kept below.
HF_CLAUDE="$(cat "$PROJ/CLAUDE.md" 2>/dev/null || true)"
{
  echo "# $NAME — Ultra Motion project"
  echo
  echo "Pipeline: ultra-motion skill. Scripts: $SCRIPT_DIR"
  echo "(If that path is stale after a plugin update: ls -d ~/.claude/plugins/cache/*/ultra-motion/*/skills/ultra-motion/scripts | tail -1)"
  echo
  echo "Files: script.md · storyboard.md · audio/vo.txt · audio/vo.wav · audio/vo.beats.json · audio/vo.words.json · credits.md"
  echo "Renders go to renders/ (final) and review/ (drafts, contact sheets). Commit after each stage."
  echo
  sed "s/{{PROJECT}}/$NAME/g" "$REF_DIR/style-contract.md"
  echo
  echo "---"
  echo
  printf '%s\n' "$HF_CLAUDE"
} > "$PROJ/CLAUDE.md.new"
mv "$PROJ/CLAUDE.md.new" "$PROJ/CLAUDE.md"

if [[ $GIT -eq 1 ]]; then
  ( cd "$PROJ" && git init -q && git add -A && git commit -q -m "Scaffold $NAME (ultra-motion)" )
  echo "→ git repo initialised with first commit"
fi

cat <<EOF

✅ Project ready: $PROJ
Next:
  1. Fill in script.md and audio/vo.txt (one paragraph per beat)
  2. Propose directions → fill the style contract at the top of CLAUDE.md
  3. VO:       $SCRIPT_DIR/tts.py audio/vo.txt -o audio/vo.wav --voice af_heart
  4. Captions: $SCRIPT_DIR/captions.sh audio/vo.wav -o audio/vo
  5. Preview:  (cd $PROJ && npx hyperframes preview)
EOF
