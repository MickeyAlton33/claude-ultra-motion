# claude-ultra-motion

A Claude Code plugin marketplace with one plugin, **ultra-motion**: a free, local motion-design video pipeline.
Ask Claude for any motion video and it first asks **"Ultra Motion Design pipeline or default mode?"**.

## Install (any machine)
```bash
claude plugin marketplace add MickeyAlton33/claude-ultra-motion
claude plugin install ultra-motion@claude-ultra-motion
```
Then install the free tool stack (asks before Homebrew installs and big downloads):
```bash
git clone https://github.com/MickeyAlton33/claude-ultra-motion ~/code/claude-ultra-motion
~/code/claude-ultra-motion/setup/install.sh
```
Check it any time from Claude: the skill runs `doctor.sh` first, or run it yourself:
`$(ls -d ~/.claude/plugins/cache/*/ultra-motion/*/skills/ultra-motion/scripts | tail -1)/doctor.sh`

## Use
- "Make me a 10-second motion design teaser for a coffee brand" → Claude asks Ultra or default.
- `/ultra-motion <brief>` → straight into the Ultra pipeline.

## What's inside
```
.claude-plugin/marketplace.json          this repo is a marketplace
plugins/ultra-motion/
  .claude-plugin/plugin.json
  skills/ultra-motion/SKILL.md           the pipeline (Step 0 question, 12 stages, quality bar)
  skills/ultra-motion/references/        style contract, storyboard template, motion language, audio sources
  skills/ultra-motion/scripts/           doctor, new-video, tts.py, captions, contact-sheet, img, deliver
  agents/motion-reviewer.md              frame-only creative-director review → APPROVED / CHANGES REQUIRED
  commands/ultra-motion.md               /ultra-motion <brief>
cookbook/                                README (stack + licences), COOKBOOK (recipes), RUNBOOK
setup/install.sh                         idempotent installer for the tool stack
```
Model weights and venvs live in `~/.ultra-motion/`, never in this repo.

## Update
```bash
cd ~/code/claude-ultra-motion && git commit -am "…" && git push
claude plugin marketplace update claude-ultra-motion
claude plugin update ultra-motion@claude-ultra-motion
```
Then restart Claude Code.
