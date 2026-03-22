#!/usr/bin/env bash
# post.sh — Routes a prepared PopSmiths post to the correct publisher.
#
# Usage:
#   ./post.sh --platform <instagram|pinterest|x> --image <path> \
#             --caption <path> [--hashtags <path>] [--output-dir <dir>] [--dry-run]
#
# Publishing:
#   instagram  → Prints Zapier MCP instructions for the calling agent to execute
#   pinterest  → Writes pin-data.csv in output-dir for bulk upload
#   x          → Posts directly via xurl CLI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BRAND_CONFIG="$REPO_DIR/config/popsmiths-brand.json"

# ── Parse args ───────────────────────────────────────────────────────────────
PLATFORM=""
IMAGE_PATH=""
CAPTION_PATH=""
HASHTAGS_PATH=""
OUTPUT_DIR=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)    PLATFORM="$2";      shift 2 ;;
    --image)       IMAGE_PATH="$2";    shift 2 ;;
    --caption)     CAPTION_PATH="$2";  shift 2 ;;
    --hashtags)    HASHTAGS_PATH="$2"; shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2";    shift 2 ;;
    --dry-run)     DRY_RUN=true;       shift 1 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── Validate ─────────────────────────────────────────────────────────────────
[[ -z "$PLATFORM" ]] && { echo "ERROR: --platform required" >&2; exit 1; }
[[ -z "$IMAGE_PATH" ]] && { echo "ERROR: --image required" >&2; exit 1; }
[[ -z "$CAPTION_PATH" ]] && { echo "ERROR: --caption required" >&2; exit 1; }
[[ ! -f "$IMAGE_PATH" ]] && { echo "ERROR: Image not found: $IMAGE_PATH" >&2; exit 1; }
[[ ! -f "$CAPTION_PATH" ]] && { echo "ERROR: Caption not found: $CAPTION_PATH" >&2; exit 1; }

CAPTION=$(cat "$CAPTION_PATH")
HASHTAGS=""
[[ -n "$HASHTAGS_PATH" && -f "$HASHTAGS_PATH" ]] && HASHTAGS=$(cat "$HASHTAGS_PATH")

# Full caption = caption + hashtags (for platforms that want them combined)
FULL_CAPTION="$CAPTION"
[[ -n "$HASHTAGS" ]] && FULL_CAPTION="$CAPTION

$HASHTAGS"

# ── Publish ──────────────────────────────────────────────────────────────────

case "$PLATFORM" in

  # ─── Instagram ─────────────────────────────────────────────────────────────
  # Zapier MCP requires an active Claude Code session with Zapier MCP access.
  # This script outputs a structured JSON file + clear instructions for the
  # calling agent to execute the Zapier MCP tool.
  instagram)
    echo "📸 Instagram: Preparing post assets..." >&2

    IG_ACCOUNT_ID="17841480110854714"
    POST_META=""
    [[ -n "$OUTPUT_DIR" ]] && POST_META="$OUTPUT_DIR/post-meta.json"

    # Write structured metadata for the agent
    META_JSON=$(cat <<EOF
{
  "platform": "instagram",
  "account_id": "$IG_ACCOUNT_ID",
  "image_path": "$IMAGE_PATH",
  "caption": $(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$FULL_CAPTION"),
  "zapier_tool": "instagram_for_business_publish_photo_s",
  "mcp_call": {
    "tool": "mcp__zapier__instagram_for_business_publish_photo_s",
    "note": "Upload image_path to a public URL first (e.g., Cloudflare R2 or Wasabi), then pass the URL as the image parameter."
  },
  "dry_run": $DRY_RUN,
  "status": "ready_to_post"
}
EOF
)

    if [[ -n "$POST_META" ]]; then
      echo "$META_JSON" > "$POST_META"
      echo "✓ Post metadata written to: $POST_META" >&2
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📸 INSTAGRAM POST READY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Image:   $IMAGE_PATH"
    echo ""
    echo "Caption:"
    echo "$FULL_CAPTION"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "AGENT ACTION REQUIRED:"
    echo ""
    echo "1. Upload the image to a public URL:"
    echo "   aws s3 cp '$IMAGE_PATH' s3://turnedyellowimages/popsmiths/social/\$(basename $IMAGE_PATH) \\"
    echo "     --endpoint-url https://s3.us-east-2.wasabisys.com --acl public-read"
    echo "   IMAGE_URL=https://d3ok1s6o7a5ag4.cloudfront.net/turnedyellowimages/popsmiths/social/\$(basename $IMAGE_PATH)"
    echo ""
    echo "2. Call Zapier MCP:"
    echo "   Tool: instagram_for_business_publish_photo_s"
    echo "   Account ID: $IG_ACCOUNT_ID"
    echo "   Image URL: \$IMAGE_URL"
    echo "   Caption: [see above]"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY RUN] Would post to Instagram. Exiting without posting." >&2
      exit 0
    fi

    echo "POST_STATUS=instagram_ready"
    ;;

  # ─── Pinterest ─────────────────────────────────────────────────────────────
  # Generates a CSV row compatible with Pinterest bulk uploader.
  # Image must be uploaded to public URL first (same S3/CloudFront as video pipeline).
  pinterest)
    echo "📌 Pinterest: Preparing pin data..." >&2

    BOARD="PopSmiths Art Prints"
    PIN_TITLE=$(head -1 "$CAPTION_PATH")  # First line of caption as pin title
    PIN_DESC="$FULL_CAPTION"

    CSV_FILE=""
    [[ -n "$OUTPUT_DIR" ]] && CSV_FILE="$OUTPUT_DIR/pin-data.csv"

    # Pinterest CSV format: Title,Media URL,Pinterest Board,Description,Link,Keywords
    IMAGE_FILENAME=$(basename "$IMAGE_PATH")
    PLACEHOLDER_URL="UPLOAD_TO_PUBLIC_URL_FIRST"

    if [[ -n "$CSV_FILE" ]]; then
      # Write CSV header if file doesn't exist
      if [[ ! -f "$CSV_FILE" ]]; then
        echo "Title,Media URL,Pinterest Board,Description,Link,Keywords" > "$CSV_FILE"
      fi
      # Escape quotes in CSV fields
      SAFE_TITLE=$(echo "$PIN_TITLE" | sed 's/"/""/g')
      SAFE_DESC=$(echo "$PIN_DESC" | sed 's/"/""/g')
      echo "\"$SAFE_TITLE\",\"$PLACEHOLDER_URL\",\"$BOARD\",\"$SAFE_DESC\",\"https://popsmiths.com\",\"$HASHTAGS\"" >> "$CSV_FILE"
      echo "✓ Pin data written to: $CSV_FILE" >&2
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌 PINTEREST PIN READY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Image:    $IMAGE_PATH"
    echo "Board:    $BOARD"
    echo "Title:    $PIN_TITLE"
    echo ""
    echo "Description:"
    echo "$PIN_DESC"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "AGENT ACTION REQUIRED:"
    echo ""
    echo "1. Upload image to public URL (same S3 as video pipeline):"
    echo "   aws s3 cp '$IMAGE_PATH' s3://turnedyellowimages/popsmiths/pinterest/\$(basename $IMAGE_PATH) \\"
    echo "     --endpoint-url https://s3.us-east-2.wasabisys.com --acl public-read"
    echo ""
    echo "2. Update pin-data.csv Media URL column with the CloudFront URL"
    echo ""
    echo "3. Use Pinterest bulk uploader or pinterest-mass-processor.js to upload"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY RUN] Would create Pinterest pin. Exiting without posting." >&2
      exit 0
    fi

    echo "POST_STATUS=pinterest_ready"
    ;;

  # ─── X / Twitter ───────────────────────────────────────────────────────────
  # Posts directly via xurl CLI (OAuth2 configured as ilovepopsmiths).
  x)
    echo "🐦 X/Twitter: Checking xurl..." >&2

    if ! command -v xurl &>/dev/null; then
      echo "ERROR: xurl CLI not found. Install from ~/.xurl or check PATH." >&2
      exit 1
    fi

    # X: caption only (no hashtags in body, or 1-2 inline)
    X_TEXT="$CAPTION"
    [[ -n "$HASHTAGS" ]] && X_TEXT="$X_TEXT $(echo "$HASHTAGS" | awk '{print $1, $2}')"

    # Truncate to 280 chars if needed
    X_TEXT="${X_TEXT:0:280}"

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "🐦 X/TWITTER POST" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "Text (${#X_TEXT} chars): $X_TEXT" >&2
    echo "Image: $IMAGE_PATH" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY RUN] Would post to X. Command would be:" >&2
      echo "  xurl post /2/tweets -d '{\"text\":\"$X_TEXT\"}' [with media upload]" >&2
      echo "POST_STATUS=x_dry_run"
      exit 0
    fi

    # Upload media first, then post tweet with media ID
    echo "📤 Uploading media to X..." >&2
    MEDIA_RESPONSE=$(xurl post /1.1/media/upload.json \
      --form "media=@$IMAGE_PATH" \
      --form "media_category=tweet_image" 2>/dev/null || echo "")

    if [[ -z "$MEDIA_RESPONSE" ]]; then
      echo "⚠ Media upload failed. Posting text-only tweet." >&2
      xurl post /2/tweets -d "{\"text\":\"$X_TEXT\"}"
    else
      MEDIA_ID=$(echo "$MEDIA_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('media_id_string',''))" 2>/dev/null || echo "")
      if [[ -n "$MEDIA_ID" ]]; then
        echo "✓ Media uploaded: $MEDIA_ID" >&2
        xurl post /2/tweets -d "{\"text\":\"$X_TEXT\",\"media\":{\"media_ids\":[\"$MEDIA_ID\"]}}"
      else
        echo "⚠ Could not parse media ID. Posting text-only." >&2
        xurl post /2/tweets -d "{\"text\":\"$X_TEXT\"}"
      fi
    fi

    echo "✓ Posted to X" >&2
    echo "POST_STATUS=x_posted"
    ;;

  *)
    echo "ERROR: Unknown platform '$PLATFORM'. Use: instagram | pinterest | x" >&2
    exit 1
    ;;
esac
