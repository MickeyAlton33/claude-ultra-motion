---
description: Make a motion design video with the full Ultra Motion Design pipeline (skips the Ultra/default question)
argument-hint: <brief: what the video is, length, formats, brand, VO>
---
The user ran `/ultra-motion`, so they have already chosen the **Ultra Motion Design pipeline**.
Do not ask the Step 0 "Ultra or default" question.

Load the `ultra-motion` skill from this plugin with the Skill tool and run it in Ultra mode, starting at
"Pipeline (Ultra mode)": doctor.sh first, then the brief.

Brief from the user:

$ARGUMENTS

If the brief above is empty, start pipeline step 1 by asking for it (max 3 questions in one AskUserQuestion).
