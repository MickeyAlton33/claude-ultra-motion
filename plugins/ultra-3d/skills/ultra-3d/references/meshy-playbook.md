# Meshy playbook — prompts, preview→refine, credit discipline

Meshy runs through the **Meshy MCP bundled in the ultra-3d plugin** (`@meshy-ai/meshy-mcp-server@0.6.11`,
key in the macOS Keychain via `claude plugin configure ultra-3d@claude-ultra-motion`). Tool names appear as
`mcp__plugin_ultra-3d_meshy__<tool>`. The API needs a Meshy **Pro plan or higher**.
The official `meshy-3d-generation` / `meshy-3d-printing` skills are installed as know-how only; their
`meshy` CLI commands are NOT installed — always use the MCP tools below.

## 0. The credit rule (non-negotiable)
1. `meshy_check_balance` (free) → note the balance.
2. Write the plan as a table: tool, model, count, credits each, **total**, balance after.
3. ⛔ Ask the user to approve that total. No approval → no call.
4. Previews/drafts first; refine/texture only the one the user picks.
5. Log every task in `meshy-log.md` (date, task id, mode, prompt, credits, kept?).
6. Never auto-allow credit-spending tools in settings; they must prompt every time.

## 1. Costs (from the MCP's own tool descriptions, v0.6.11 — re-check `meshy_list_models` / docs.meshy.ai/en/api/pricing if in doubt)

| Tool | What | Credits |
|---|---|---|
| `meshy_check_balance`, `meshy_list_usage`, `meshy_list_models`, `meshy_list_tasks`, `meshy_get_task_status`, `meshy_list_animations`, `meshy_analyze_printability`, `meshy_download_model` | read / download | **0** |
| `meshy_text_to_image` / `meshy_image_to_image` | concept image | 3 (nana-2-lite) · 4 (nano-banana-2-1) · 9 (nano-banana-pro) · 9–12 (GPT Image) |
| `meshy_text_to_3d` (preview, untextured) | mesh from text | **20** (meshy-7.1 / latest / meshy-6) · **5** (meshy-6-lite, meshy-t2, meshy-t2.5) · +5 Ultra geometry |
| `meshy_text_to_3d_refine` | texture a chosen preview | **10** (15 at 8K) |
| `meshy_image_to_3d` | mesh (+texture) from 1 image | mesh 20 (7.1/6) or 5 (6-lite/t2/t2.5) **+10 texture** (15 at 8K) · +5 Ultra |
| `meshy_multi_image_to_3d` | 2–4 photos of one object | same as image-to-3D |
| `meshy_retexture` | new texture on existing mesh | 10 (15 at 8K) |
| `meshy_remesh` | retopology / target poly count | 5 |
| `meshy_convert` / `meshy_resize` | format change / rescale | 1 / 1 |
| `meshy_uv_unwrap` | UVs | 5 |
| `meshy_rig` | humanoid auto-rig (+ free walk & run clips) | 5 |
| `meshy_animate` | extra library animation | 3 per action (≤ 10 per request) |
| `meshy_text_to_motion` | animation from text | 10 (prime) · 3 (swift) |
| `meshy_repair_printability` / `meshy_process_multicolor` / `meshy_auto_split` | print prep | 10 each |
| `meshy_creative_lab` | fidget/pixel/magnet novelties | varies (e.g. 36) |
| `meshy_send_to_slicer` | hand file to a slicer | 0 (prefer our `slice.sh`) |
| `meshy_cancel_task` | cancel | PENDING → refunded · IN_PROGRESS → **not** refunded |

`meshy-7` is retired for generation on **2026-12-31** — use `meshy-7.1` / `latest`.

### Typical budgets
| Job | Plan | Credits |
|---|---|---|
| Cheap exploration | 3 × text-to-3D on meshy-6-lite | 15 |
| Decorative print (untextured) | 2 × meshy-7.1 preview → keep 1 | 40 |
| Textured hero prop | 2 × meshy-7.1 preview + 1 refine | 50 |
| Image route (best control) | 1 × concept image (4) + image-to-3D 7.1 textured (30) | 34 |
| Game character | concept image 4 + image-to-3D t2.5 + n1 tex (15) + rig (5) + 2 extra clips (6) | 30 |

## 2. Model choice (Meshy's own "choose by project" guide)
- Detailed hero asset, product render, cinematic prop → **meshy-7.1 + meshy-7** texture (PBR, up to 8K)
- Character to rig/animate → **meshy-t2.5** (smart topology, set `target_polycount` 10–30k) + **meshy-n1**
- Many props / UGC → **meshy-t2** + meshy-n1
- Real object from 2–4 photos → **meshy-7.1 multi-image** + meshy-7
- 3D print → **meshy-7.1 + no texture** (or meshy-7 texture for colour prints)
- Many cheap drafts → **meshy-6-lite**

**Prefer the image route** for anything that matters: `meshy_text_to_image` (3–9 cr) → user approves the image →
`meshy_image_to_3d` with `input_task_id`. A picture is cheaper to reject than a mesh.

## 3. Prompt patterns
Structure: **subject + form + material/finish + style + framing constraints**. 30–80 words. One object.

```
A <subject>, <key form words: proportions, silhouette, pose>, <material + finish>,
<style: realistic | stylized PBR | low-poly | figurine>, single object, centered,
<symmetry if wanted>, clean solid base, no text, no background objects
```
Write 2–3 variants that differ in ONE axis (style, silhouette, or material) so the previews are comparable:

- *Realistic:* "A ceramic owl figurine, compact rounded body, large forward-facing eyes, folded wings with
  carved feather grooves, matte speckled stoneware glaze in warm sand tones, realistic, single object,
  standing on a flat oval base, symmetric front view, no text"
- *Stylized:* same subject, "stylized chunky shapes, smooth simplified feathers, soft pastel matte glaze"
- *Graphic:* same subject, "faceted low-poly planes, crisp edges, single-colour satin finish"

For printing add: "solid, thick features, no thin protrusions, no floating parts, flat bottom".
For rigging add: "A-pose (or T-pose), arms away from body, legs apart, neutral expression, no cape/hair strands touching body".
Negative ideas go in words ("no text", "no background"), not as a separate field unless the tool exposes one.

## 4. Flow
1. **Concept** (optional, recommended): 1–2 concept images → user picks.
2. **Previews**: 2–3 `meshy_text_to_3d` (or image-to-3D untextured) → `meshy_get_task_status` until SUCCEEDED →
   `meshy_download_model` into `assets/meshy/<task>/` → `render.sh <glb> --quick --stills hero --turntable 0
   --preset clay` → show the user side by side.
3. **Refine/texture** only the pick (`meshy_text_to_3d_refine`, 10 cr).
4. **Post**: remesh for web/rig (`meshy_remesh` 5 cr *or* Blender decimate — free), rig/animate if needed.
5. **Bring home**: Blender cleanup (see blender-recipes.md §Cleanup), set real-world scale, then per-track export.

## 5. When NOT to use Meshy
- Anything that must fit something (→ CAD). AI dimensions drift ±5–10 % and surfaces are never planar.
- Text, logos, numbers, UI, labels (→ CAD / decals).
- Precise symmetry or repetition (gears, grilles, threads) (→ CAD, arrays).
- Exact likeness of a real, specific product or trademarked character (→ decline / user-supplied assets).
- When a free CC0 model on Poly Haven already fits (check `https://api.polyhaven.com/assets?type=models`).
- When the budget is tight and a blockout of primitives would answer the question.

## 6. Quality checks on every Meshy result
- Scale: Meshy GLBs are ~1–2 m tall regardless of the prompt → always rescale to the brief's real size.
- Origin/orientation: Y-up glTF; put origin at bottom centre, face −Y in Blender.
- Floating debris & internal faces → `mesh_check` bodies count; `mesh_fix.py --drop-small 1`.
- Texture: check base colour for baked lighting/shadows (looks "dirty" under studio light) → retexture or de-light.
- Topology: for animation, verify edge loops at elbows/knees/shoulders on a wireframe render before rigging.
