#!/usr/bin/env bash
# compose.sh — Add brand overlays to a staged image and resize to platform dimensions.
#
# Usage:
#   ./compose.sh --input <path> --platform <instagram|pinterest|x> --output <path> [--text "overlay text"]
#
# Brand assets used:
#   Circular logo : .../popsmiths_brand/assets/logos/PopSmithsCircularLogo.png   (2000×2000, RGBA)
#   Horizontal logo: .../popsmiths_brand/assets/logos/PopSmiths0218desktoplogov6.png (2000×800)

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BRAND_DIR="/Users/lcalderon/github/mkt-brands/popsmiths_brand/assets/logos"
CIRCULAR_LOGO="${BRAND_DIR}/PopSmithsCircularLogo.png"
HORIZONTAL_LOGO="${BRAND_DIR}/PopSmiths0218desktoplogov6.png"
SITE_URL="popsmiths.com"

# ---------------------------------------------------------------------------
# Resolve ImageMagick binary (prefer 'magick', fall back to 'convert')
# ---------------------------------------------------------------------------
if command -v magick &>/dev/null; then
    IM="magick"
elif command -v convert &>/dev/null; then
    IM="convert"
else
    echo "[compose] ERROR: ImageMagick not found. Install it with: brew install imagemagick" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[compose] $*" >&2; }
die() { echo "[compose] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
INPUT=""
PLATFORM=""
OUTPUT=""
OVERLAY_TEXT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)    INPUT="$2";        shift 2 ;;
        --platform) PLATFORM="$2";    shift 2 ;;
        --output)   OUTPUT="$2";      shift 2 ;;
        --text)     OVERLAY_TEXT="$2"; shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate required args
# ---------------------------------------------------------------------------
[[ -z "$INPUT" ]]    && die "--input is required"
[[ -z "$PLATFORM" ]] && die "--platform is required (instagram | pinterest | x)"
[[ -z "$OUTPUT" ]]   && die "--output is required"

[[ -f "$INPUT" ]] || die "Input file not found: $INPUT"

case "$PLATFORM" in
    instagram|pinterest|x) ;;
    *) die "Unknown platform '$PLATFORM'. Must be: instagram | pinterest | x" ;;
esac

# Ensure output directory exists
OUTPUT_DIR="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Platform dimensions
# ---------------------------------------------------------------------------
case "$PLATFORM" in
    instagram) CANVAS_W=1080; CANVAS_H=1350 ;;
    pinterest) CANVAS_W=1000; CANVAS_H=1500 ;;
    x)         CANVAS_W=1200; CANVAS_H=675  ;;
esac

log "Platform: $PLATFORM (${CANVAS_W}×${CANVAS_H})"
log "Input:    $INPUT"
log "Output:   $OUTPUT"

# ---------------------------------------------------------------------------
# Temp directory (cleaned up on exit)
# ---------------------------------------------------------------------------
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

STAGE1="${TMPDIR_WORK}/stage1_resized.png"
STAGE2="${TMPDIR_WORK}/stage2_logo.png"
STAGE3="${TMPDIR_WORK}/stage3_badge.png"

# ---------------------------------------------------------------------------
# Step 1 — Resize + crop to exact platform dimensions
# ---------------------------------------------------------------------------
log "Step 1: Resizing + cropping to ${CANVAS_W}×${CANVAS_H}..."

$IM "$INPUT" \
    -resize "${CANVAS_W}x${CANVAS_H}^" \
    -gravity Center \
    -extent "${CANVAS_W}x${CANVAS_H}" \
    "$STAGE1"

log "Step 1 complete."

# ---------------------------------------------------------------------------
# Step 2 — Brand logo overlay
# ---------------------------------------------------------------------------

# Helper: composite a logo file onto a base image at a given gravity/offset/opacity.
# Usage: composite_logo <base> <logo_src> <logo_w> <logo_h> <gravity> <x_offset> <y_offset> <opacity_pct> <out>
composite_logo() {
    local base="$1"
    local logo_src="$2"
    local logo_w="$3"
    local logo_h="$4"
    local gravity="$5"
    local x_off="$6"
    local y_off="$7"
    local opacity="$8"   # 0–100
    local out="$9"

    local resized_logo="${TMPDIR_WORK}/logo_resized.png"
    local dissolved_logo="${TMPDIR_WORK}/logo_dissolved.png"

    # Resize logo to target dimensions
    $IM "$logo_src" \
        -resize "${logo_w}x${logo_h}" \
        "$resized_logo"

    # Apply opacity by modulating the alpha channel
    $IM "$resized_logo" \
        -alpha set \
        -channel Alpha \
        -evaluate multiply "$(echo "scale=4; $opacity / 100" | bc)" \
        +channel \
        "$dissolved_logo"

    # Composite onto base
    $IM "$base" \
        "$dissolved_logo" \
        -gravity "$gravity" \
        -geometry "+${x_off}+${y_off}" \
        -compose Over \
        -composite \
        "$out"
}

apply_logo() {
    local base="$1"
    local out="$2"

    case "$PLATFORM" in
        instagram)
            # Circular logo — bottom-right, 10% of canvas width, 20px margin, 85% opacity
            local LOGO_SIZE=$(( CANVAS_W * 10 / 100 ))
            if [[ -f "$CIRCULAR_LOGO" ]]; then
                log "Step 2: Compositing circular logo (bottom-right, ${LOGO_SIZE}px, 85% opacity)..."
                composite_logo \
                    "$base" "$CIRCULAR_LOGO" \
                    "$LOGO_SIZE" "$LOGO_SIZE" \
                    SouthEast 20 20 85 "$out"
            else
                log "Step 2: WARNING — circular logo not found, skipping logo step."
                cp "$base" "$out"
            fi
            ;;

        pinterest)
            # Horizontal logo — bottom-center, 30% of canvas width, 30px bottom margin, 90% opacity
            local LOGO_W=$(( CANVAS_W * 30 / 100 ))
            # Preserve aspect ratio: source is 2000×800 → height = width * 800/2000 = width * 2/5
            local LOGO_H=$(( LOGO_W * 2 / 5 ))
            if [[ -f "$HORIZONTAL_LOGO" ]]; then
                log "Step 2: Compositing horizontal logo (bottom-center, ${LOGO_W}×${LOGO_H}px, 90% opacity)..."
                composite_logo \
                    "$base" "$HORIZONTAL_LOGO" \
                    "$LOGO_W" "$LOGO_H" \
                    South 0 30 90 "$out"
            else
                log "Step 2: WARNING — horizontal logo not found, skipping logo step."
                cp "$base" "$out"
            fi
            ;;

        x)
            # Circular logo — top-left, 8% of canvas width, 15px margin, 80% opacity
            local LOGO_SIZE=$(( CANVAS_W * 8 / 100 ))
            if [[ -f "$CIRCULAR_LOGO" ]]; then
                log "Step 2: Compositing circular logo (top-left, ${LOGO_SIZE}px, 80% opacity)..."
                composite_logo \
                    "$base" "$CIRCULAR_LOGO" \
                    "$LOGO_SIZE" "$LOGO_SIZE" \
                    NorthWest 15 15 80 "$out"
            else
                log "Step 2: WARNING — circular logo not found, skipping logo step."
                cp "$base" "$out"
            fi
            ;;
    esac
}

apply_logo "$STAGE1" "$STAGE2"
log "Step 2 complete."

# ---------------------------------------------------------------------------
# Step 3 — URL badge ("popsmiths.com")
# ---------------------------------------------------------------------------

# Calculate text metrics to size the pill background dynamically.
# We draw the pill first using a fixed padding, then composite the text on top.
add_url_badge() {
    local base="$1"
    local out="$2"

    case "$PLATFORM" in
        instagram|pinterest)
            # White text in a semi-transparent dark pill, bottom-center
            local FONT_SIZE=30
            local PADDING_X=22   # horizontal padding inside pill
            local PADDING_Y=10   # vertical padding inside pill
            local MARGIN_BOTTOM=22

            # Estimate text width (Helvetica ~0.55 char-width ratio at given pt size is unreliable;
            # use ImageMagick's -format %[fx:...] to measure precisely).
            local TXT_W
            TXT_W=$($IM -font Helvetica -pointsize "$FONT_SIZE" \
                label:"$SITE_URL" \
                -format '%w' info: 2>/dev/null || echo "160")

            local TXT_H
            TXT_H=$($IM -font Helvetica -pointsize "$FONT_SIZE" \
                label:"$SITE_URL" \
                -format '%h' info: 2>/dev/null || echo "36")

            local PILL_W=$(( TXT_W + PADDING_X * 2 ))
            local PILL_H=$(( TXT_H + PADDING_Y * 2 ))

            # Pill x/y relative to bottom-center of canvas
            local PILL_X=$(( (CANVAS_W - PILL_W) / 2 ))
            local PILL_Y=$(( CANVAS_H - PILL_H - MARGIN_BOTTOM ))

            # Corner radius = half pill height for fully rounded ends
            local RADIUS=$(( PILL_H / 2 ))

            # Build the roundrectangle draw command:
            #   roundrectangle x0,y0 x1,y1 rx,ry
            local RX0="$PILL_X"
            local RY0="$PILL_Y"
            local RX1=$(( PILL_X + PILL_W ))
            local RY1=$(( PILL_Y + PILL_H ))

            log "Step 3: Drawing URL badge pill (${PILL_W}×${PILL_H} at ${PILL_X},${PILL_Y})..."

            $IM "$base" \
                -fill 'rgba(0,0,0,0.55)' \
                -draw "roundrectangle ${RX0},${RY0} ${RX1},${RY1} ${RADIUS},${RADIUS}" \
                -font Helvetica \
                -pointsize "$FONT_SIZE" \
                -fill white \
                -gravity South \
                -annotate "+0+${MARGIN_BOTTOM}" "$SITE_URL" \
                "$out"
            ;;

        x)
            # Small white text, bottom-right, no pill background
            local FONT_SIZE=22
            local MARGIN_RIGHT=18
            local MARGIN_BOTTOM=15

            log "Step 3: Adding URL text (bottom-right, ${FONT_SIZE}px white)..."

            $IM "$base" \
                -font Helvetica \
                -pointsize "$FONT_SIZE" \
                -fill white \
                -gravity SouthEast \
                -annotate "+${MARGIN_RIGHT}+${MARGIN_BOTTOM}" "$SITE_URL" \
                "$out"
            ;;
    esac
}

add_url_badge "$STAGE2" "$STAGE3"
log "Step 3 complete."

# ---------------------------------------------------------------------------
# Step 4 — Optional text overlay
# ---------------------------------------------------------------------------
FINAL_STAGE="$STAGE3"

if [[ -n "$OVERLAY_TEXT" ]]; then
    STAGE4="${TMPDIR_WORK}/stage4_text.png"

    # Wrap long text: split at word boundary near the midpoint so it fits on 2 lines.
    # ImageMagick does automatic line-wrapping within a pango: or caption: pseudo-image,
    # but for a simple -annotate approach we rely on the caller keeping text concise.
    local_font_size=36
    local_shadow_offset=2

    case "$PLATFORM" in
        instagram|pinterest)
            # Upper area: place text ~12% from top, centered, white bold with drop shadow
            log "Step 4: Adding text overlay (upper area, bold white + shadow)..."

            # Draw shadow pass (dark, slightly offset)
            $IM "$STAGE3" \
                -font Helvetica-Bold \
                -pointsize "$local_font_size" \
                -fill 'rgba(0,0,0,0.65)' \
                -gravity North \
                -annotate "+${local_shadow_offset}+$((CANVAS_H * 12 / 100 + local_shadow_offset))" \
                "$OVERLAY_TEXT" \
                "${TMPDIR_WORK}/stage4_shadow.png"

            # Draw text pass (white) on top of shadow
            $IM "${TMPDIR_WORK}/stage4_shadow.png" \
                -font Helvetica-Bold \
                -pointsize "$local_font_size" \
                -fill white \
                -gravity North \
                -annotate "+0+$((CANVAS_H * 12 / 100))" \
                "$OVERLAY_TEXT" \
                "$STAGE4"
            ;;

        x)
            # Bottom area (above the URL badge): centered white text
            log "Step 4: Adding text overlay (bottom area, white)..."

            $IM "$STAGE3" \
                -font Helvetica-Bold \
                -pointsize 28 \
                -fill 'rgba(0,0,0,0.55)' \
                -gravity South \
                -annotate "+2+$((CANVAS_H * 15 / 100 + 2))" \
                "$OVERLAY_TEXT" \
                "${TMPDIR_WORK}/stage4_shadow.png"

            $IM "${TMPDIR_WORK}/stage4_shadow.png" \
                -font Helvetica-Bold \
                -pointsize 28 \
                -fill white \
                -gravity South \
                -annotate "+0+$((CANVAS_H * 15 / 100))" \
                "$OVERLAY_TEXT" \
                "$STAGE4"
            ;;
    esac

    FINAL_STAGE="$STAGE4"
    log "Step 4 complete."
else
    log "Step 4: No --text provided, skipping text overlay."
fi

# ---------------------------------------------------------------------------
# Step 5 — Write final JPEG at 90% quality
# ---------------------------------------------------------------------------
log "Step 5: Writing JPEG output at 90% quality → $OUTPUT"

$IM "$FINAL_STAGE" \
    -quality 90 \
    -format jpeg \
    "$OUTPUT"

log "Done. Output: $OUTPUT"
