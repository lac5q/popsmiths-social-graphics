---
name: popsmiths-social-graphics
description: >
  Generate and publish brand-compliant social media graphics for PopSmiths.
  Stages real sample art into lifestyle scenes using Gemini. Supports Instagram,
  Pinterest, and X. Callable from Paperclip agents, OpenClaw agents, and Claude Code.
triggers:
  - "make a post"
  - "create instagram"
  - "create pinterest pin"
  - "create x post"
  - "popsmiths social"
  - "generate pin"
  - "post for popsmiths"
---

# PopSmiths Social Graphics Skill

Generate and publish awesome PopSmiths social media graphics by staging real art samples into lifestyle scenes.

## Quick Invocation

```bash
# Instagram (lifestyle scene, 1080×1350)
~/github/popsmiths-social-graphics/scripts/generate-post.sh \
  --platform instagram --style wabi_sabi --product canvas --vibe movie_night

# Pinterest (lifestyle scene, 1000×1500)
~/github/popsmiths-social-graphics/scripts/generate-post.sh \
  --platform pinterest --style holographic --product blanket

# X/Twitter (graphic treatment, 1200×675)
~/github/popsmiths-social-graphics/scripts/generate-post.sh \
  --platform x --style celestial_map --product mug

# Generate only (no posting, for preview/QA)
~/github/popsmiths-social-graphics/scripts/generate-post.sh \
  --platform instagram --style art_deco_geometric --skip-post
```

## All Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--platform` | ✅ | `instagram` \| `pinterest` \| `x` |
| `--style` | ❌ | Art style (omit for daily-seeded random pick) |
| `--product` | ❌ | Product type (omit for auto-select per style) |
| `--vibe` | ❌ | Lifestyle vibe: `movie_night`, `cozy_kitchen`, `gallery_wall`, `morning_coffee`, `office_desk`, `bedroom`, `outdoor`, `holiday` |
| `--text` | ❌ | Optional text overlay on the image (e.g., "Gallery-quality art for your home") |
| `--output-dir` | ❌ | Custom output directory (default: `output/{platform}-{style}-{product}-{timestamp}/`) |
| `--skip-post` | ❌ | Generate image + caption but don't publish |
| `--dry-run` | ❌ | Show what would be posted without actually posting |

## Available Art Styles

abstract_color_field, art_deco_geometric, block_print_folk, celestial_map, chinoiserie,
coastal_seascape, comic_halftone, continuous_line_pop, duotone_split, gilded_baroque,
holographic, liquid_chrome, moody_botanical, single_accent_minimalist, terrazzo_organic,
vintage_travel_poster, wabi_sabi

List all: `~/github/popsmiths-social-graphics/scripts/select-art.py --list-styles`

## Available Products

blanket, canvas, framed, greetingcard, hoodie, iphone, kidshoodie, kidstshirt,
laptopsleeve, mousepad, mug, ornament, pillow, prints, puzzle, samsung, socks,
sticker, sweatshirt, tanktop, totebag, tshirt, waterbottle

List products for a style: `~/github/popsmiths-social-graphics/scripts/select-art.py --list-products --style wabi_sabi`

## Pipeline Steps

```
1. select-art.py      → Pick art from ~/github/popsmiths_app/public/samples/
2. stage-art.py       → Gemini stages art into lifestyle scene (art preserved)
3. compose.sh         → ImageMagick adds brand logo, popsmiths.com, overlays
4. generate-caption.py→ Claude Haiku writes brand-voice caption + hashtags
5. qa-check.py        → Blocks posting if brand rules violated
6. post.sh            → Routes to publisher (Zapier/Pinterest CSV/xurl)
```

## Output Files

Everything lands in `output/{platform}-{style}-{product}-{timestamp}/`:
- `composed.jpg` — Final image at platform dimensions
- `caption.txt` — Brand-voice caption
- `hashtags.txt` — Platform-optimized hashtags
- `post-meta.json` — Full metadata for agent-based posting
- `qa-report.txt` — QA check results
- `art-selection.json` — Which art was selected

## Platform-Specific Behavior

### Instagram
- Dimensions: 1080×1350 (4:5 portrait)
- Staging: Gemini lifestyle scene — art preserved exactly
- **Publishing**: Requires agent with Zapier MCP access
  - `post.sh` outputs instructions + `post-meta.json`
  - Agent calls `instagram_for_business_publish_photo_s` (Account ID: 17841480110854714)
  - Image must be uploaded to public URL first (Wasabi S3 → CloudFront)
- **QA signoff required** before posting

### Pinterest
- Dimensions: 1000×1500 (2:3 vertical)
- Staging: Gemini lifestyle scene — art preserved exactly
- **Publishing**: `post.sh` generates `pin-data.csv` for bulk upload
  - Board: "PopSmiths Art Prints"
  - Image must be uploaded to public URL first
- **QA signoff required** before posting

### X (Twitter)
- Dimensions: 1200×675 (16:9 landscape)
- Staging: Gemini graphic/museum-poster composition — art is hero, slightly bolder treatment
- **Publishing**: `post.sh` calls `xurl` CLI directly (OAuth as @ilovepopsmiths)
- No QA signoff required (Luis approval or direct post OK)

## Brand Rules (Enforced by qa-check.py)

❌ NEVER use: AI, prompt, generate, easy, simple, upload, discover, algorithm
✅ ALWAYS include: `popsmiths.com` in every caption
✅ USE at least one: "Gallery-quality", "Statement piece", "uniquely yours", "We did the hard work", "Instant Art"
✅ Art source: ONLY `~/github/popsmiths_app/public/samples/` — never stock photos or externally generated images

## Image Generation Approach

**The core rule:** PopSmiths sample art = the product. Gemini stages it, never redraws it.

- **Instagram + Pinterest**: Gemini receives the product photo (art on canvas/mug/blanket/etc.) and places it naturally in a lifestyle scene (warm living room, kitchen, gallery wall). The illustration itself remains pixel-identical.
- **X**: Gemini creates a bold, graphic composition with the art as the visual hero. Slight reinterpretation is OK for maximum scroll-stopping impact.

This is the same approach as the video pipeline (Nano Banana Pro / Gemini staging).

## Calling from Paperclip Agents

When a Paperclip task involves social media image creation:

```
Task description: "Create Instagram post for wabi_sabi canvas, movie night vibe"

Agent steps:
1. Parse task: platform=instagram, style=wabi_sabi, product=canvas, vibe=movie_night
2. Run: ~/github/popsmiths-social-graphics/scripts/generate-post.sh \
         --platform instagram --style wabi_sabi --product canvas --vibe movie_night \
         --skip-post
3. Review output/*/composed.jpg for quality
4. If approved: share post-meta.json with marketing-qa agent for signoff
5. After signoff: upload image to Wasabi S3, call Zapier MCP to post
```

## Calling from OpenClaw Agents

marketing-specialist or graphic-designer agents can call the pipeline as a shell command:

```
Message to agent: "Create an Instagram post for the holographic art on a blanket"

Agent executes:
~/github/popsmiths-social-graphics/scripts/generate-post.sh \
  --platform instagram --style holographic --product blanket --skip-post

Then returns the output path and composed.jpg for review.
```

## Environment Requirements

```bash
# Required env vars
GEMINI_API_KEY    # Already set in ~/.zshrc
ANTHROPIC_API_KEY # Already set

# Required tools
pip install google-genai pillow anthropic
brew install imagemagick
# xurl CLI must be in PATH (for X posting)
# AWS CLI must be configured (for S3 image uploads)
```

## Common Workflows

### Daily Instagram post (auto-select art)
```bash
~/github/popsmiths-social-graphics/scripts/generate-post.sh \
  --platform instagram --skip-post
# Review, then share post-meta.json with marketing-qa
```

### Batch: create all three platforms for one art
```bash
STYLE=wabi_sabi PRODUCT=canvas
for platform in instagram pinterest x; do
  ~/github/popsmiths-social-graphics/scripts/generate-post.sh \
    --platform $platform --style $STYLE --product $PRODUCT --skip-post
done
```

### Quick X post (no QA needed)
```bash
~/github/popsmiths-social-graphics/scripts/generate-post.sh \
  --platform x --style celestial_map --product mug --dry-run
# Review, then re-run without --dry-run to post
```
