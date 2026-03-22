#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "anthropic>=0.20.0",
# ]
# ///
"""
generate-caption.py — Generate a brand-voice caption + hashtags for a PopSmiths social post.

Uses the Anthropic Claude API (claude-haiku-4-5-20251001) to produce platform-specific
copy that follows PopSmiths brand rules. Writes caption.txt and hashtags.txt to --output-dir.
"""

import argparse
import os
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Platform-specific instructions injected into the prompt
# ---------------------------------------------------------------------------

PLATFORM_INSTRUCTIONS: dict[str, str] = {
    "instagram": (
        "Write 100-150 words. Conversational tone. Use 1-3 emojis maximum. "
        "End the caption with popsmiths.com. "
        "Return 25-30 relevant hashtags (space-separated, each starting with #)."
    ),
    "pinterest": (
        "Write 50-80 words. Descriptive, keyword-rich copy optimised for search discovery. "
        "End the caption with popsmiths.com. "
        "Return 15-20 relevant hashtags (space-separated, each starting with #)."
    ),
    "x": (
        "Write a maximum of 240 characters INCLUDING spaces (leave room for an attached image). "
        "Punchy, witty, single-sentence energy. "
        "Include popsmiths.com at the very end. "
        "Return 1-2 hashtags only."
    ),
}

PROMPT_TEMPLATE = """\
You are a copywriter for PopSmiths, a premium art print brand with a fun, nostalgic, celebratory personality.

Write a social media caption for {platform} featuring our {product_display} in the {style_display} art style.

BRAND RULES:
- NEVER use these words: AI, artificial intelligence, prompt, generate, generated, easy, simple, upload, discover, algorithm
- ALWAYS include popsmiths.com in the caption
- Tone: warm, premium, celebratory, gallery-quality
- Must include at least one of: "Gallery-quality", "Statement piece", "uniquely yours", "We did the hard work", "Instant Art"
- Product is a {product_display} featuring the {style_display} art style{vibe_line}

PLATFORM: {platform}
{platform_specific_instructions}

Return ONLY:
CAPTION:
[caption here]

HASHTAGS:
[hashtags here, space-separated, each starting with #]
"""

# ---------------------------------------------------------------------------
# Fallback caption when the API call fails
# ---------------------------------------------------------------------------

FALLBACK_CAPTIONS: dict[str, str] = {
    "instagram": (
        "Gallery-quality art, uniquely yours. Our {style_display} {product_display} turns "
        "any space into something worth talking about. We did the hard work — you get all "
        "the compliments. Shop now at popsmiths.com"
    ),
    "pinterest": (
        "Statement piece alert. Our {style_display} {product_display} brings "
        "gallery-quality art into your everyday life. popsmiths.com"
    ),
    "x": (
        "Gallery-quality {style_display} {product_display} — uniquely yours. "
        "popsmiths.com #PopSmiths #ArtPrints"
    ),
}

FALLBACK_HASHTAGS: dict[str, str] = {
    "instagram": (
        "#PopSmiths #ArtPrints #GalleryWall #HomeDecor #WallArt #PrintableArt "
        "#InteriorDesign #ArtLovers #GalleryQuality #StatementPiece #UniqueGifts "
        "#ArtForHome #ModernArt #PrintsOfInstagram #HomeInspo #WallDecor "
        "#ArtPrint #GiftIdeas #ArtCommunity #DecorInspo #LivingRoomDecor "
        "#BedroomDecor #ArtGallery #PrintArt #HomeStyling"
    ),
    "pinterest": (
        "#PopSmiths #ArtPrints #GalleryWall #HomeDecor #WallArt "
        "#InteriorDesign #StatementPiece #PrintArt #HomeInspo #ArtForHome "
        "#GalleryQuality #UniqueGifts #WallDecor #ArtLovers #ModernArt"
    ),
    "x": "#PopSmiths #ArtPrints",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def build_prompt(
    style_display: str,
    product_display: str,
    platform: str,
    vibe: str | None,
) -> str:
    vibe_line = f"\n- Lifestyle vibe context: {vibe}" if vibe else ""
    return PROMPT_TEMPLATE.format(
        platform=platform,
        product_display=product_display,
        style_display=style_display,
        vibe_line=vibe_line,
        platform_specific_instructions=PLATFORM_INSTRUCTIONS[platform],
    )


def parse_response(text: str) -> tuple[str, str]:
    """
    Split the model response into (caption, hashtags).

    Expected format:
        CAPTION:
        <caption text>

        HASHTAGS:
        <space-separated hashtags>

    Returns empty strings for any section that cannot be parsed.
    """
    caption = ""
    hashtags = ""

    # Normalise line endings
    text = text.replace("\r\n", "\n").strip()

    if "CAPTION:" in text and "HASHTAGS:" in text:
        cap_start = text.index("CAPTION:") + len("CAPTION:")
        ht_start = text.index("HASHTAGS:")
        caption = text[cap_start:ht_start].strip()
        hashtags = text[ht_start + len("HASHTAGS:"):].strip()
    elif "CAPTION:" in text:
        caption = text[text.index("CAPTION:") + len("CAPTION:"):].strip()
    else:
        # No structured markers — treat the whole response as the caption
        caption = text

    return caption, hashtags


def call_claude(prompt: str) -> str:
    """Call the Anthropic Messages API and return the text response."""
    import anthropic  # local import so the script is importable without the package

    client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from env
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}],
    )
    return response.content[0].text


def write_outputs(
    output_dir: Path,
    caption: str,
    hashtags: str,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "caption.txt").write_text(caption, encoding="utf-8")
    (output_dir / "hashtags.txt").write_text(hashtags, encoding="utf-8")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a brand-voice PopSmiths caption + hashtags via Claude."
    )
    parser.add_argument("--style", required=True, help="Art style key (e.g. wabi_sabi)")
    parser.add_argument(
        "--style-display",
        required=True,
        dest="style_display",
        help="Human-readable style name (e.g. 'Wabi Sabi')",
    )
    parser.add_argument(
        "--product", required=True, help="Product type key (e.g. canvas)"
    )
    parser.add_argument(
        "--product-display",
        required=True,
        dest="product_display",
        help="Human-readable product name (e.g. 'Canvas Print')",
    )
    parser.add_argument(
        "--platform",
        required=True,
        choices=["instagram", "pinterest", "x"],
        help="Target social platform",
    )
    parser.add_argument(
        "--vibe",
        default=None,
        help="Optional lifestyle vibe used in staging (e.g. 'cozy reading nook')",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        dest="output_dir",
        help="Directory to write caption.txt and hashtags.txt",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    prompt = build_prompt(
        style_display=args.style_display,
        product_display=args.product_display,
        platform=args.platform,
        vibe=args.vibe,
    )

    # --- Attempt API call ---
    caption = ""
    hashtags = ""
    api_ok = False

    try:
        raw = call_claude(prompt)
        caption, hashtags = parse_response(raw)
        if caption:
            api_ok = True
    except ImportError:
        print(
            "Warning: 'anthropic' package not installed. Using fallback caption.",
            file=sys.stderr,
        )
    except Exception as exc:  # noqa: BLE001
        print(
            f"Warning: Claude API call failed ({exc}). Using fallback caption.",
            file=sys.stderr,
        )

    # --- Fallback if API did not produce usable output ---
    if not api_ok or not caption:
        template = FALLBACK_CAPTIONS[args.platform]
        caption = template.format(
            style_display=args.style_display,
            product_display=args.product_display,
        )
        hashtags = FALLBACK_HASHTAGS[args.platform]
        print("Info: Using fallback caption template.", file=sys.stderr)

    # Ensure hashtags is a clean single-line space-separated string
    hashtags = " ".join(hashtags.split())

    write_outputs(output_dir, caption, hashtags)

    print(f"Caption written to: {output_dir / 'caption.txt'}")
    print(f"Hashtags written to: {output_dir / 'hashtags.txt'}")
    print()
    print("--- CAPTION PREVIEW ---")
    print(caption)
    print()
    print("--- HASHTAGS PREVIEW ---")
    print(hashtags)


if __name__ == "__main__":
    main()
