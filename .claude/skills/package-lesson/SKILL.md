---
name: package-lesson
description: Create a complete lesson package from a topic description. Generates lesson.json, fetches images, and deploys to wwwroot.
user_invocable: true
---

# Package a Lesson

You are creating a lesson package for the SlicedBread.ca educational lessons system.

## Input

The user will describe a lesson topic (e.g., "French colors", "solar system planets", "multiplication tables"). They may also specify:
- Language (default: French for vocabulary, English for other subjects)
- Number of concepts (default: 8-12)
- Which game screens to include (default: all 4 types)

## Lesson JSON Schema (Version 1)

```json
{
  "version": 1,
  "id": "{lesson-id}",
  "title": "Display Title",
  "subject": "Subject Area",
  "icon": "Map|Calendar|Science|Music|Book",
  "concepts": [
    {
      "name": "Concept Name",
      "properties": { "key": "value" },
      "image": "images/filename.svg",
      "order": 1
    }
  ],
  "screens": [
    { "style": "multiple-choice", "ask": "propertyKey", "answer": "propertyKey", "count": 5 },
    { "style": "fill-in-blank", "prompt": "Template with {name} or {key} ___", "answer": "propertyKey", "count": 4 },
    { "style": "drag-to-slot", "ask": "propertyKey", "answer": "propertyKey", "count": 4 },
    { "style": "sorting", "orderBy": "order", "label": "name", "count": 6 }
  ],
  "awards": {
    "completion": { "name": "Award Name", "icon": "IconName" },
    "perfect": { "name": "Perfect Award Name", "icon": "Star" }
  }
}
```

### Rules
- `"name"` is always the concept's display name (built-in, not in `properties`)
- Any key in `properties` can be used as `ask`, `answer`, or `{placeholder}` in prompts
- Distractors are auto-generated from sibling concepts — ensure enough distinct values
- `order` field on concepts is used by the sorting screen
- For French lessons: use French property keys (e.g., `capitale`, `saison`), French prompts, French award names
- Keep `count` values reasonable: 4-6 for most screens, up to 8 for sorting

## Step-by-Step Process

### 1. Author lesson.json

Create the lesson definition at: `lessons/{lesson-id}/lesson.json`

The `lesson-id` should be a URL-safe kebab-case slug (e.g., `couleurs-en-francais`, `solar-system`).

Include `"lastModifiedDate": null` in the lesson.json (after `publishedDate`). When updating an existing lesson, set `lastModifiedDate` to today's date in both `lesson.json` and `index.json`.

Design screens that test the concepts from different angles:
- **multiple-choice**: Good for recognition. Use different ask/answer combos for variety (e.g., screen 1: ask name → answer property, screen 2: ask property → answer name)
- **fill-in-blank**: Good for recall and spelling practice. Use `{placeholder}` templates.
- **drag-to-slot**: Good for matching pairs. Works best with 4 items.
- **sorting**: Good for ordering. Requires meaningful `order` values on concepts.

#### Screen Confidence Check

After designing each screen, evaluate it against this checklist. Any failed check downgrades confidence:

| Check | Applies to |
|-|-|
| Every concept in the pool has a unique `order` value | sorting |
| Ranking criterion is factually unambiguous (pH scale, distance, sequential steps — NOT subjective descriptors like "moderately populated") | sorting |
| Pool is homogeneous — all concepts are the same entity type (not process steps mixed with chemical compounds) | sorting |
| Instruction names only entity types actually in the pool (don't say "planets" if pool includes stars and moons) | sorting |
| Concept `name` does not contain or strongly imply the answer category | classify |
| Displayed field (`ask`) does not reveal the answer through notation or symbols (e.g., operator symbol revealing operation type) | classify, multiple-choice |
| Each category has >= 2 concepts in the pool | classify |
| `ask` != `answer` property | multiple-choice, drag-to-slot |
| Pool has >= 4 concepts for distractor generation | multiple-choice |
| `instruction` field is present and states the criterion explicitly | all |

**Confidence levels:**
- All checks pass → **HIGH** — proceed automatically
- Any check fails → **NOT HIGH** — the screen is **blocked from output**

Only HIGH-confidence screens are written to the lesson file. Students only see content that passed all checks or was manually verified by the user.

When any check fails:
1. State which check(s) failed and why
2. Propose a concrete fix (rename concepts, change ask/answer fields, replace screen type)
3. **Do not write the screen.** Wait for the user to approve the fix or provide an alternative
4. Re-evaluate the fixed screen against the checklist before writing

#### Reading Review Feedback

Before generating a new lesson, check for `review.json` files in existing lessons:

1. Prompt the user: "Review feedback exists for previous lessons. Read it to improve this session? (y/n)"
2. If yes, scan `src/SBC.Web/wwwroot/lessons/*/review.json` for flagged screens
3. Summarize patterns in the feedback (e.g., "3 classify screens flagged as 'answer is obvious'")
4. Use these patterns as additional guardrails for the current lesson — treat recurring feedback categories as HIGH-priority checks

When rewriting flagged screens in an existing lesson:
1. Read the lesson's `review.json` for all screens with status `flagged`
2. For each flagged screen, read the feedback category and comment
3. Regenerate the screen addressing the specific feedback
4. Reset the screen's status to `unreviewed` in `review.json`
5. Run the confidence checklist on the rewritten screen before writing

The `review.json` schema (preliminary — BRF-002 will finalize):
```json
{
  "screens": [
    { "index": 0, "status": "approved" },
    { "index": 1, "status": "flagged", "category": "bad-question", "comment": "..." }
  ]
}
```
Gracefully skip lessons that don't have a `review.json` file or where the file is malformed.

#### Confidence Calibration

If a screen generated with HIGH confidence is later flagged in review, that signals a gap in the checklist:
1. Identify which check should have caught the issue
2. Add a new check to the table above or refine an existing one
3. Note the calibration update in the commit message

### 2. Fetch images from Twemoji

Images come from Twitter's Twemoji library (MIT license) on GitHub:
```
https://raw.githubusercontent.com/twitter/twemoji/master/assets/svg/{codepoint}.svg
```

Find the Unicode codepoint for an appropriate emoji for each concept. Common codepoints:
- Look up emoji at https://emojipedia.org and use the Unicode codepoint
- Codepoint format: lowercase hex without U+ prefix (e.g., `2744` for snowflake, `1f34e` for red apple)

Download each SVG with curl:
```bash
curl -sL "https://raw.githubusercontent.com/twitter/twemoji/master/assets/svg/{codepoint}.svg" -o lessons/{lesson-id}/images/{name}.svg
```

Verify each download is valid SVG (starts with `<svg`).

### 3. Copy to wwwroot

```bash
# Copy the entire lesson package
cp -r lessons/{lesson-id} src/SBC.Web/wwwroot/lessons/{lesson-id}
```

### 4. Register in index.json

Add an entry to `src/SBC.Web/wwwroot/lessons/index.json`:
```json
{
  "id": "{lesson-id}",
  "title": "Display Title",
  "subject": "Subject Area",
  "icon": "Map|Calendar|Science|Music|Book",
  "lastModifiedDate": null,
  "hasInteractive": true
}
```

- `hasInteractive`: set to `true` if any screen uses an interactive style (`hotspot`, `province-puzzle`, `drag-to-slot`, `sorting`, `classify`, `step-builder`, `gear-sim`, `pulley-sim`, `inequality-explorer`); `false` otherwise.
- `lastModifiedDate`: `null` for new lessons. Set to today's date when updating an existing lesson.

### 5. Verify

```bash
# Check the JSON is valid
curl -s http://localhost:5054/lessons/{lesson-id}/lesson.json | head -5

# Check images serve
curl -s -o /dev/null -w "%{http_code}" http://localhost:5054/lessons/{lesson-id}/images/{first-image}.svg
```

## Icon Options

For the lesson `icon` field, supported values that map to MudBlazor Material icons:
- `Map` — geography/places
- `Calendar` — time/dates
- `Science` — science topics
- `Music` — music/arts
- `Book` — general/default

### 6. Commit

Always commit the lesson after packaging:
```bash
git add lessons/{lesson-id}/ src/SBC.Web/wwwroot/lessons/{lesson-id}/ src/SBC.Web/wwwroot/lessons/index.json
git commit -m "lesson: {lesson-id} — brief description"
```

## Output

When done, summarize:
- Lesson title and ID
- Number of concepts
- Screens included
- Images downloaded (count and source)
- Deployment status (copied to wwwroot, registered in index.json, committed)
