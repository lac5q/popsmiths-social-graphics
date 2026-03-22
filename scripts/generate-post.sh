#!/usr/bin/env bash
# generate-post.sh — Main orchestrator for the PopSmiths social graphics pipeline.
#
# Runs: select-art → stage-art → compose → generate-caption → qa-check → post
#
# Usage:
#   ./generate-post.sh --platform <instagram|pinterest|x> \
#     [--style <style_name>] [--product <product_name>] \
#     [--vibe <vibe>] [--text <overlay_text>] \
#     [--skip-post] [--dry-run] [--output-dir <dir>]
#
# Examples:
#   ./generate-post.sh --platform instagram --style wabi_sabi --product canvas --vibe movie_night
#   ./generate-post.sh --platform pinterest --style holographic --product blanket
#   ./generate-post.sh --platform x --style celestial_map --product mug
#   ./generate-post.sh --platform instagram --skip-post   # generate but don't post

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ── Parse args ───────────────────────────────────────────────────────────────
PLATFORM=""
STYLE=""
PRODUCT=""
VIBE=""
OVERLAY_TEXT=""
SKIP_POST=false
DRY_RUN=false
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)    PLATFORM="$2";       shift 2 ;;
    --style)       STYLE="$2";          shift 2 ;;
    --product)     PRODUCT="$2";        shift 2 ;;
    --vibe)        VIBE="$2";           shift 2 ;;
    --text)        OVERLAY_TEXT="$2";   shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2";     shift 2 ;;
    --skip-post)   SKIP_POST=true;      shift 1 ;;
    --dry-run)     DRY_RUN=true;        shift 1 ;;
    --help|-h)
      grep "^# " "$0" | head -20 | sed 's/^# //'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── Validate ─────────────────────────────────────────────────────────────────
if [[ -z "$PLATFORM" ]]; then
  echo "ERROR: --platform required (instagram | pinterest | x)" >&2
  exit 1
fi

if [[ ! "$PLATFORM" =~ ^(instagram|pinterest|x)$ ]]; then
  echo "ERROR: Platform must be: instagram | pinterest | x" >&2
  exit 1
fi

# ── Output directory ─────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
STYLE_SLUG="${STYLE:-random}"
PRODUCT_SLUG="${PRODUCT:-random}"

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$REPO_DIR/output/${PLATFORM}-${STYLE_SLUG}-${PRODUCT_SLUG}-${TIMESTAMP}"
fi
mkdir -p "$OUTPUT_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
echo "🍿 PopSmiths Social Graphics Pipeline" >&2
echo "   Platform: $PLATFORM | Style: ${STYLE:-auto} | Product: ${PRODUCT:-auto}" >&2
echo "   Output:   $OUTPUT_DIR" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

# ── Step 1: Select art ────────────────────────────────────────────────────────
echo "" >&2
echo "Step 1/6: Selecting art from sample gallery..." >&2

SELECT_ARGS=()
[[ -n "$STYLE" ]] && SELECT_ARGS+=(--style "$STYLE")
[[ -n "$PRODUCT" ]] && SELECT_ARGS+=(--product "$PRODUCT")

ART_JSON=$(python3 "$SCRIPT_DIR/select-art.py" --output-json "${SELECT_ARGS[@]}")
echo "$ART_JSON" > "$OUTPUT_DIR/art-selection.json"

ART_PATH=$(echo "$ART_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['art_path'])")
STYLE_NAME=$(echo "$ART_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['style'])")
PRODUCT_NAME=$(echo "$ART_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['product'])")
STYLE_DISPLAY=$(echo "$ART_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['style_display'])")
PRODUCT_DISPLAY=$(echo "$ART_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['product_display'])")

echo "   ✓ Art: $STYLE_DISPLAY / $PRODUCT_DISPLAY" >&2
echo "     Path: $ART_PATH" >&2

# ── Step 2: Stage art with Gemini ─────────────────────────────────────────────
echo "" >&2
echo "Step 2/6: Staging art into lifestyle scene (Gemini)..." >&2

STAGED_IMAGE="$OUTPUT_DIR/staged.png"

STAGE_ARGS=(
  --input "$ART_PATH"
  --platform "$PLATFORM"
  --product "$PRODUCT_NAME"
  --style "$STYLE_NAME"
  --output "$STAGED_IMAGE"
)
[[ -n "$VIBE" ]] && STAGE_ARGS+=(--vibe "$VIBE")

python3 "$SCRIPT_DIR/stage-art.py" "${STAGE_ARGS[@]}"

if [[ ! -f "$STAGED_IMAGE" ]]; then
  echo "ERROR: Staging failed — no output image produced." >&2
  exit 1
fi
echo "   ✓ Staged image: $STAGED_IMAGE" >&2

# ── Step 3: Compose (brand overlays + resize) ─────────────────────────────────
echo "" >&2
echo "Step 3/6: Applying brand overlays and resizing..." >&2

COMPOSED_IMAGE="$OUTPUT_DIR/composed.jpg"

COMPOSE_ARGS=(
  --input "$STAGED_IMAGE"
  --platform "$PLATFORM"
  --output "$COMPOSED_IMAGE"
)
[[ -n "$OVERLAY_TEXT" ]] && COMPOSE_ARGS+=(--text "$OVERLAY_TEXT")

bash "$SCRIPT_DIR/compose.sh" "${COMPOSE_ARGS[@]}"

if [[ ! -f "$COMPOSED_IMAGE" ]]; then
  echo "ERROR: Composition failed — no output image produced." >&2
  exit 1
fi
echo "   ✓ Composed image: $COMPOSED_IMAGE" >&2

# ── Step 4: Generate caption ──────────────────────────────────────────────────
echo "" >&2
echo "Step 4/6: Generating brand-voice caption..." >&2

CAPTION_ARGS=(
  --style "$STYLE_NAME"
  --style-display "$STYLE_DISPLAY"
  --product "$PRODUCT_NAME"
  --product-display "$PRODUCT_DISPLAY"
  --platform "$PLATFORM"
  --output-dir "$OUTPUT_DIR"
)
[[ -n "$VIBE" ]] && CAPTION_ARGS+=(--vibe "$VIBE")

python3 "$SCRIPT_DIR/generate-caption.py" "${CAPTION_ARGS[@]}"

CAPTION_FILE="$OUTPUT_DIR/caption.txt"
HASHTAGS_FILE="$OUTPUT_DIR/hashtags.txt"

if [[ ! -f "$CAPTION_FILE" ]]; then
  echo "ERROR: Caption generation failed." >&2
  exit 1
fi
echo "   ✓ Caption generated" >&2
echo "   Preview: $(head -1 "$CAPTION_FILE")..." >&2

# ── Step 5: QA check (blocks posting if fails) ────────────────────────────────
echo "" >&2
echo "Step 5/6: Running QA gate..." >&2

QA_ARGS=(
  --image "$COMPOSED_IMAGE"
  --caption "$CAPTION_FILE"
  --platform "$PLATFORM"
  --output-dir "$OUTPUT_DIR"
)

set +e
python3 "$SCRIPT_DIR/qa-check.py" "${QA_ARGS[@]}"
QA_EXIT=$?
set -e

if [[ $QA_EXIT -ne 0 ]]; then
  echo "" >&2
  echo "🚫 QA FAILED — Post blocked. See $OUTPUT_DIR/qa-report.txt" >&2
  echo "   Fix the issues above and re-run, or use --skip-post to save assets without posting." >&2
  if [[ "$SKIP_POST" == "false" ]]; then
    exit 1
  else
    echo "   (--skip-post set: continuing to save assets despite QA failure)" >&2
  fi
else
  echo "   ✓ QA passed" >&2
fi

# ── Write post-meta.json ──────────────────────────────────────────────────────
CAPTION_CONTENT=$(cat "$CAPTION_FILE")
HASHTAGS_CONTENT=""
[[ -f "$HASHTAGS_FILE" ]] && HASHTAGS_CONTENT=$(cat "$HASHTAGS_FILE")

python3 - <<PYEOF
import json
meta = {
    "platform": "$PLATFORM",
    "style": "$STYLE_NAME",
    "style_display": "$STYLE_DISPLAY",
    "product": "$PRODUCT_NAME",
    "product_display": "$PRODUCT_DISPLAY",
    "vibe": "${VIBE:-auto}",
    "art_path": "$ART_PATH",
    "staged_image": "$STAGED_IMAGE",
    "composed_image": "$COMPOSED_IMAGE",
    "caption_file": "$CAPTION_FILE",
    "hashtags_file": "$HASHTAGS_FILE",
    "output_dir": "$OUTPUT_DIR",
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "qa_passed": $([ $QA_EXIT -eq 0 ] && echo "true" || echo "false"),
    "ready_to_post": $([ "$SKIP_POST" == "false" ] && [ $QA_EXIT -eq 0 ] && echo "true" || echo "false")
}
with open("$OUTPUT_DIR/post-meta.json", "w") as f:
    json.dump(meta, f, indent=2)
print("✓ post-meta.json written")
PYEOF

# ── Step 6: Post ──────────────────────────────────────────────────────────────
if [[ "$SKIP_POST" == "true" ]]; then
  echo "" >&2
  echo "Step 6/6: Skipped (--skip-post)" >&2
else
  echo "" >&2
  echo "Step 6/6: Publishing..." >&2

  POST_ARGS=(
    --platform "$PLATFORM"
    --image "$COMPOSED_IMAGE"
    --caption "$CAPTION_FILE"
    --output-dir "$OUTPUT_DIR"
  )
  [[ -f "$HASHTAGS_FILE" ]] && POST_ARGS+=(--hashtags "$HASHTAGS_FILE")
  [[ "$DRY_RUN" == "true" ]] && POST_ARGS+=(--dry-run)

  bash "$SCRIPT_DIR/post.sh" "${POST_ARGS[@]}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo "" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
echo "✅ Pipeline complete!" >&2
echo "" >&2
echo "   Output directory: $OUTPUT_DIR" >&2
echo "   ├── composed.jpg       ← final image" >&2
echo "   ├── caption.txt        ← brand-voice caption" >&2
echo "   ├── hashtags.txt       ← platform hashtags" >&2
echo "   ├── post-meta.json     ← full metadata for agent posting" >&2
echo "   ├── qa-report.txt      ← QA results" >&2
echo "   └── art-selection.json ← which art was used" >&2
echo "" >&2

if [[ "$PLATFORM" == "instagram" || "$PLATFORM" == "pinterest" ]]; then
  echo "   ⚠ NEXT STEP: Marketing QA signoff required before publishing." >&2
  echo "   Share post-meta.json with the marketing-qa agent for review." >&2
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
