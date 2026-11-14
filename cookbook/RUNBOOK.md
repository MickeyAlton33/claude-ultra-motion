Claude Code Runbook — "Ultra Motion" Pipeline: Free Stack + Skill + Personal Repo

For Claude Code: Read this whole file first, then execute the phases in order. Use a task list. Goal: (1) install a free, local motion-design stack, (2) package my pipeline as a Claude Code plugin (skill + subagent + command + scripts + cookbook), (3) push it to my personal GitHub repo as a plugin marketplace, (4) install it from that repo, so that whenever I ask for a motion design video, Claude asks: "Ultra Motion Design pipeline or default mode?" and then acts accordingly.

Rules:

🛑 = stop and ask me. Ask before sudo, Homebrew installs, or large downloads (> 2 GB).
These commands may be out of date. Before each install, check the tool's official repo/docs (use Context7 or the web).
Check the current Claude Code plugin/skill/marketplace file formats in the official Claude Code docs before writing the manifests. The structure below is the intent; the docs define the exact schema.
Never commit secrets, tokens, model weights, renders or large media. The repo is private unless I say otherwise.
Machine: macOS. Check with uname -m and adapt.
Phase 0 — Preflight
Report: claude --version, node -v (≥ 20), python3 --version, uv --version, ffmpeg -version, gh --version, git config user.name, gh auth status, uname -m.
If gh isn't authenticated: 🛑 tell me to run gh auth login.
Run claude mcp list and claude plugin list and show me the output.
Phase 1 — Remove paid tools

🛑 Show me which of these exist and ask before removing: MCPs elevenlabs, fal, runway, heygen (claude mcp remove <name> -s user). Remotion: 🛑 ask whether to keep it (free only for personal use or companies with ≤ 3 employees). Default is to remove it. Resolve Studio / After Effects MCPs: leave them alone and just report them.

Phase 2 — Install the free stack
Purpose    Tool (license)    Install (verify against official docs)
Animation engine    HyperFrames (Apache-2.0)    claude plugin marketplace add heygen-com/hyperframes → claude plugin install hyperframes@hyperframes
Animation skills    GSAP skills (free)    claude plugin marketplace add greensock/gsap-skills → claude plugin install gsap-skills@gsap-skills
Technical explainers    Manim Community (MIT)    system deps (cairo, pango, a minimal LaTeX like BasicTeX) → uv tool install manim
3D    Blender (GPL) + mcp-for-blender (MIT)    🛑 ask if I want 3D. uvx mcp-for-blender setup; set env BLENDER_MCP_SAFE_MODE=1; don't use the paid generators inside it
Voiceover    Kokoro TTS (Apache-2.0)    uv venv ~/.ultra-motion/venv → install kokoro soundfile there; brew install espeak-ng
Captions    whisper.cpp (MIT)    brew install whisper-cpp + download a small model to ~/.ultra-motion/models/
Images (optional)    mflux + FLUX.1 schnell (Apache-2.0)    🛑 ask (~20–30 GB). Apple Silicon only. Never FLUX dev (non-commercial)
Encode / mux    FFmpeg    already present, or brew install ffmpeg

Model weights and venvs live in ~/.ultra-motion/, never in the repo. Verify: one smoke command per tool. Report a table: tool | version | ✅/❌.

Phase 3 — Create the repo locally

🛑 Ask me for the repo name. Suggest claude-ultra-motion. Create it in ~/code/<repo>:

<repo>/
├── .claude-plugin/
│   └── marketplace.json            # this repo is a plugin marketplace
├── plugins/
│   └── ultra-motion/
│       ├── .claude-plugin/plugin.json
│       ├── skills/
│       │   └── ultra-motion/
│       │       ├── SKILL.md        # the pipeline (content in Phase 4)
│       │       ├── references/
│       │       │   ├── style-contract.md
│       │       │   ├── storyboard-template.md
│       │       │   ├── motion-language.md   # easing, timing, transitions cheat sheet
│       │       │   └── audio-sources.md     # free music/SFX libraries + license rules
│       │       └── scripts/
│       │           ├── new-video.sh      # scaffold project (HyperFrames init + folders + CLAUDE.md)
│       │           ├── tts.py            # Kokoro: text file + voice → WAV, prints duration
│       │           ├── captions.sh       # whisper.cpp: audio → .srt + word-timestamps JSON
│       │           ├── contact-sheet.sh  # ffmpeg 1fps tile grid
│       │           ├── img.sh            # mflux schnell (no-op with a message if not installed)
│       │           ├── deliver.sh        # master → 16:9, 9:16, 1:1, GIF; loudnorm -14 LUFS
│       │           └── doctor.sh         # checks that every dependency is installed; prints fixes
│       ├── agents/
│       │   └── motion-reviewer.md
│       └── commands/
│           └── ultra-motion.md           # /ultra-motion <brief> = force the pipeline, skip the question
├── cookbook/
│   ├── README.md                   # what this is, the stack, licenses, costs (all free)
│   ├── COOKBOOK.md                 # recipes: product teaser, explainer (Manim), social reel, logo sting, captions-only
│   └── RUNBOOK.md                  # a copy of this file
├── setup/
│   └── install.sh                  # idempotent installer for Phase 2 on a fresh Mac (asks before brew/large downloads)
├── .gitignore                      # *.mp4 *.mov *.wav renders/ audio/ models/ .venv/ node_modules/ .env*
└── README.md                       # install: `claude plugin marketplace add <me>/<repo>` + `claude plugin install ultra-motion@<marketplace>`

Every script: set -euo pipefail, a usage message, checks its own dependencies, uses no network except where stated, and is executable.

Phase 4 — Write SKILL.md (use this content; adjust the frontmatter to the current schema)
(The SKILL.md content lives in plugins/ultra-motion/skills/ultra-motion/SKILL.md.)

Also write the referenced files with real, useful content: a concise style contract template, a storyboard table template, a motion-language cheat sheet (easing families with GSAP names, durations for UI vs cinematic, transition types and when to use them), and the audio-sources list with license rules (prefer CC0; log everything).

Phase 5 — The subagent and the command

agents/motion-reviewer.md: a senior motion designer / creative director that reviews contact sheets and key frames
against the project's style contract, returns ranked concrete fixes and a verdict (APPROVED or CHANGES REQUIRED),
and judges from frames only, never from code.

commands/ultra-motion.md: takes $ARGUMENTS as the brief, invokes the ultra-motion skill in Ultra mode, and skips Step 0.

Phase 6 — Make the trigger reliable

Skills trigger on their description, which usually works. As a backstop, append this to ~/.claude/CLAUDE.md (create the file if missing; show me the diff first):

## Motion design videos
Whenever I ask for a motion design / animated / explainer / promo video, use the ultra-motion skill:
first ask "Ultra Motion Design pipeline or default mode?" (unless I already chose), then follow my answer.

Also add allow rules to ~/.claude/settings.json for the pipeline's commands (ffmpeg, ffprobe, npx hyperframes, manim, whisper-cli/whisper-cpp, and the plugin's scripts). Show me the diff first.

Phase 7 — Push to my personal repo
git init, add, and commit ("Ultra Motion plugin: skill, reviewer, scripts, cookbook").
Make sure nothing large or secret gets committed: git ls-files | xargs du -ch | tail -1, and grep for "key", "token" and "secret".
🛑 Confirm the repo name and visibility (default private), then: gh repo create <repo> --private --source=. --remote=origin --push
Report the repo URL.
Phase 8 — Install from the repo (so the repo is the source of truth)
If any earlier copies of these skills/agents exist under ~/.claude/skills, ~/.claude/agents or ~/.claude/templates/motion-project: 🛑 list them and ask before removing, to avoid duplicates.
claude plugin marketplace add <github-user>/<repo> (private repos use my gh/git credentials; if that fails, fall back to adding the local path and tell me).
claude plugin install ultra-motion@<marketplace-name>
Verify with claude plugin list, and confirm that the ultra-motion skill, the motion-reviewer agent and the /ultra-motion command are visible.
Phase 9 — End-to-end test
In a fresh session-equivalent test, from /tmp/um-test: simulate the request "make me a 10-second motion design teaser for a coffee brand" and confirm the skill would ask the Ultra/default question. Report the behavior.
Run Ultra mode for that 10-second teaser: Kokoro VO line, word-synced captions, a GSAP title, a placeholder music bed at −20 dB, contact sheet + reviewer pass, deliver 16:9 + 9:16.
Report file paths and anything that failed. Fix any bugs in the plugin, commit, and push.
Phase 10 — Final report
Table: component | status | license | notes.
Repo URL plus the two install commands for another machine.
How I update it later: edit in ~/code/<repo> → commit → push → claude plugin marketplace update (verify the exact command) → restart Claude Code.
Anything still waiting on me.
