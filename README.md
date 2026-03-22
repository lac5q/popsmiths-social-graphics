# PopSmiths Social Graphics Pipeline

Shared image generation + posting pipeline for PopSmiths social media.
Used by Paperclip agents, OpenClaw agents, and Claude Code.

## Quick Start

```bash
# Instagram (lifestyle staging, real art preserved)
./scripts/generate-post.sh --platform instagram --style wabi_sabi --product canvas --vibe movie_night

# Pinterest (lifestyle staging, vertical format)
./scripts/generate-post.sh --platform pinterest --style holographic --product blanket

# X/Twitter (graphic treatment, faster cycle)
./scripts/generate-post.sh --platform x --style celestial_map --product mug
```

Output lands in `./output/{platform}-{style}-{product}-{timestamp}/`:
- `composed.jpg` — final image at platform dimensions
- `caption.txt` — brand-voice caption
- `hashtags.txt` — platform-optimized hashtags
- `post-meta.json` — all metadata for agent posting

## Image Strategy

- **Instagram + Pinterest**: Gemini stages real PopSmiths sample art into lifestyle scenes.
  The illustration is preserved exactly — Gemini adds context (scene, lighting, environment).
- **X**: Gemini creates a graphic/text-driven composition using the art as a strong visual reference.
  Slightly looser treatment OK for fast-moving platform.

## Art Source (Mandatory)

All art comes from `~/github/popsmiths_app/public/samples/{style}/{product}.jpg`.
Never use stock photos, AI-generated images, or external sources.

## Brand Rules

- All posts link ONLY to `popsmiths.com`
- Forbidden words: AI, prompt, generate, easy, simple, upload, discover
- Required framing: "Gallery-quality", "Statement piece", "uniquely yours"
- Instagram + Pinterest: requires marketing-qa signoff before posting
- X: Luis approval or direct post OK

## Publishing

- **Instagram**: Agent with Zapier MCP uses `post-meta.json` to call `instagram_for_business_publish_photo_s`
- **Pinterest**: Uses `pin-data.csv` for bulk upload via approved pinterest-mass-processor
- **X**: `post.sh` calls `xurl` CLI directly

## Pipeline Steps

```
select-art.py → stage-art.py → compose.sh → generate-caption.py → qa-check.py → post.sh
```

## Requirements

```bash
pip install google-genai pillow anthropic
brew install imagemagick
```

GEMINI_API_KEY must be set in environment.
