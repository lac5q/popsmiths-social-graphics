#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "google-genai>=1.0.0",
#     "pillow>=10.0.0",
# ]
# ///
"""
stage-art.py — Stage a PopSmiths art sample into a lifestyle/marketing scene.

Uses the Gemini API to add contextual scene/environment around the product image
while preserving the illustration exactly as-is.

Usage:
    python stage-art.py \\
        --input samples/moody_botanical/canvas.jpg \\
        --platform instagram \\
        --product canvas \\
        --style moody_botanical \\
        --output output/staged.png

    python stage-art.py \\
        --input samples/vintage_travel_poster/mug.jpg \\
        --platform pinterest \\
        --vibe morning_coffee \\
        --product mug \\
        --style vintage_travel_poster \\
        --output output/mug-staged.png
"""

import argparse
import io
import os
import random
import sys
from pathlib import Path

from google import genai
from google.genai import types
from PIL import Image

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PLATFORMS = ("instagram", "pinterest", "x")

PRODUCT_DISPLAY = {
    "canvas": "Canvas Print",
    "mug": "Mug",
    "blanket": "Throw Blanket",
    "framed": "Framed Print",
    "tshirt": "T-Shirt",
    "hoodie": "Hoodie",
    "pillow": "Throw Pillow",
    "prints": "Art Print",
    "puzzle": "Jigsaw Puzzle",
    "iphone": "iPhone Case",
    "samsung": "Samsung Case",
    "totebag": "Tote Bag",
    "greetingcard": "Greeting Card",
    "laptopsleeve": "Laptop Sleeve",
    "mousepad": "Mouse Pad",
    "socks": "Socks",
    "sticker": "Sticker",
    "sweatshirt": "Sweatshirt",
    "tanktop": "Tank Top",
    "waterbottle": "Water Bottle",
    "ornament": "Ornament",
    "kidstshirt": "Kids T-Shirt",
    "kidshoodie": "Kids Hoodie",
}

# Vibe name -> human-readable scene description used inside the prompt
VIBE_DESCRIPTIONS = {
    "movie_night": "cozy living room with movie playing in background, warm blanket, popcorn bowl",
    "cozy_kitchen": "bright modern kitchen, morning light, coffee steaming, breakfast spread",
    "gallery_wall": "modern living room gallery wall, white walls, warm ambient lighting",
    "morning_coffee": "sunlit home office desk, steaming coffee mug, notebook, morning light",
    "office_desk": "clean minimal desk setup, natural light, plants, professional aesthetic",
    "bedroom": "stylish bedroom, soft morning light, linen bedding, plants",
    "outdoor": "sunny outdoor patio or garden, natural setting",
    "holiday": "cozy holiday setting, warm lights, seasonal decor",
}

# Fallback description when vibe is None or not in the map
DEFAULT_VIBE_DESCRIPTION = "stylish modern home, warm natural light, premium lifestyle aesthetic"

# Product -> preferred vibe(s).  A list means random choice at runtime.
PRODUCT_DEFAULT_VIBES: dict[str, list[str]] = {
    "mug": ["morning_coffee"],
    "waterbottle": ["morning_coffee"],
    "blanket": ["movie_night", "bedroom"],
    "pillow": ["movie_night", "bedroom"],
    "canvas": ["gallery_wall"],
    "framed": ["gallery_wall"],
    "prints": ["gallery_wall"],
    "tshirt": ["outdoor"],
    "hoodie": ["outdoor"],
    "sweatshirt": ["outdoor"],
    "tanktop": ["outdoor"],
    "kidstshirt": ["outdoor"],
    "kidshoodie": ["outdoor"],
    "iphone": ["office_desk"],
    "samsung": ["office_desk"],
    "laptopsleeve": ["office_desk"],
    "mousepad": ["office_desk"],
    "puzzle": ["holiday"],
    "greetingcard": ["holiday"],
    "ornament": ["holiday"],
}

# Platform -> Gemini resolution string
PLATFORM_RESOLUTION = {
    "instagram": "2K",
    "pinterest": "2K",
    "x": "1K",
}

# Platform -> nominal aspect ratio string (for the prompt)
PLATFORM_ASPECT_RATIO = {
    "instagram": "4:5 portrait",
    "pinterest": "2:3 portrait",
    "x": "16:9 landscape",
}

GEMINI_MODEL = "gemini-3-pro-image-preview"

# ---------------------------------------------------------------------------
# Prompt builders
# ---------------------------------------------------------------------------

INSTAGRAM_PINTEREST_PROMPT = """\
You are a professional lifestyle photographer and art director for PopSmiths, a premium art print brand.

Your task: Stage the product shown in this image into an aspirational lifestyle scene.

CRITICAL RULES:
1. The art/illustration on the product MUST remain visually identical. Do NOT redraw, modify, reinterpret, or stylize the artwork.
2. Show the product naturally placed in a real-world environment.
3. Scene should feel warm, aspirational, and premium — like a high-end lifestyle magazine.
4. Lighting: soft, warm, natural light preferred.
5. No text, no watermarks, no additional overlays.

Product: {product_display}
Art style: {style_display}
Scene vibe: {vibe_description}
Target aspect ratio: {aspect_ratio}

Create a beautiful, magazine-quality lifestyle photo showing this {product_display} in its natural setting.\
"""

X_PROMPT = """\
You are a creative director for PopSmiths, a premium art brand.

Your task: Create a compelling graphic composition featuring the art shown in this image.

CRITICAL RULES:
1. The art/illustration MUST be prominently featured and recognizable.
2. You may use the art more graphically (cropped details, bold composition, repeating pattern) but it must remain faithful to the original.
3. Style: bold, eye-catching, scroll-stopping. Think museum poster meets social media.
4. Clean background. No text overlays (text will be added separately).
5. Make the art the hero.

Product: {product_display}
Art style: {style_display}
Target aspect ratio: {aspect_ratio}

Create a striking, graphic composition that makes this art impossible to scroll past.\
"""


def build_prompt(
    platform: str,
    product_display: str,
    style_display: str,
    vibe: str | None,
    aspect_ratio: str,
) -> str:
    """Return the fully formatted Gemini prompt for the given platform."""
    vibe_description = VIBE_DESCRIPTIONS.get(vibe or "", DEFAULT_VIBE_DESCRIPTION)

    if platform in ("instagram", "pinterest"):
        return INSTAGRAM_PINTEREST_PROMPT.format(
            product_display=product_display,
            style_display=style_display,
            vibe_description=vibe_description,
            aspect_ratio=aspect_ratio,
        )
    else:  # x
        return X_PROMPT.format(
            product_display=product_display,
            style_display=style_display,
            aspect_ratio=aspect_ratio,
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def resolve_product_display(product: str | None) -> str:
    """Return a human-readable product name."""
    if product is None:
        return "Art Print Product"
    return PRODUCT_DISPLAY.get(product, product.capitalize())


def resolve_style_display(style: str | None) -> str:
    """Convert underscore_case style name to Title Case."""
    if style is None:
        return "Original Art"
    return " ".join(word.capitalize() for word in style.split("_"))


def resolve_vibe(product: str | None, vibe: str | None) -> str | None:
    """
    Return the effective vibe string.

    If a vibe was explicitly passed, use it.
    Otherwise, auto-select based on product type.
    Returns None (meaning fall back to default description) when there's
    no product hint and no explicit vibe.
    """
    if vibe:
        return vibe

    if product and product in PRODUCT_DEFAULT_VIBES:
        options = PRODUCT_DEFAULT_VIBES[product]
        return random.choice(options)

    return None


def load_image(path: str) -> Image.Image:
    """Open an image file and return a PIL Image."""
    img_path = Path(path)
    if not img_path.is_file():
        print(f"Error: input file not found: {path}", file=sys.stderr)
        sys.exit(1)
    return Image.open(img_path)


def save_image(image_bytes: bytes, output_path: str) -> None:
    """
    Save raw image bytes to disk.  Converts RGBA to RGB with white background
    before saving as PNG so downstream tools always get a clean RGB file.
    """
    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(io.BytesIO(image_bytes))
    if img.mode == "RGBA":
        background = Image.new("RGB", img.size, (255, 255, 255))
        background.paste(img, mask=img.split()[3])  # 3 = alpha channel
        img = background
    elif img.mode != "RGB":
        img = img.convert("RGB")

    img.save(str(out), format="PNG")


def call_gemini(
    client: genai.Client,
    pil_image: Image.Image,
    prompt: str,
    resolution: str,
) -> bytes:
    """
    Call the Gemini image generation API and return the raw image bytes.
    Exits with code 1 if the response contains no image parts.
    """
    print(f"  Sending request to {GEMINI_MODEL} (resolution={resolution})...", file=sys.stderr)

    response = client.models.generate_content(
        model=GEMINI_MODEL,
        contents=[pil_image, prompt],
        config=types.GenerateContentConfig(
            response_modalities=["TEXT", "IMAGE"],
            image_config=types.ImageConfig(image_size=resolution),
        ),
    )

    for part in response.candidates[0].content.parts:
        if part.inline_data is not None:
            return part.inline_data.data

    print(
        "Error: Gemini response contained no image parts. "
        "The model may have declined to generate an image for this input.",
        file=sys.stderr,
    )
    sys.exit(1)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Stage a PopSmiths art sample into a lifestyle/marketing scene "
            "using the Gemini image generation API."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Auto-select vibe based on product
  python stage-art.py --input samples/moody_botanical/canvas.jpg \\
      --platform instagram --product canvas --style moody_botanical \\
      --output output/staged.png

  # Explicit vibe override
  python stage-art.py --input samples/vintage_travel_poster/mug.jpg \\
      --platform pinterest --vibe morning_coffee --product mug \\
      --style vintage_travel_poster --output output/mug-staged.png

  # X/Twitter graphic treatment
  python stage-art.py --input samples/holographic/tshirt.jpg \\
      --platform x --product tshirt --style holographic \\
      --output output/tshirt-x.png
""",
    )
    parser.add_argument(
        "--input",
        required=True,
        metavar="PATH",
        help="Path to input art image (from sample gallery).",
    )
    parser.add_argument(
        "--platform",
        required=True,
        choices=PLATFORMS,
        metavar="PLATFORM",
        help="Target platform: instagram | pinterest | x",
    )
    parser.add_argument(
        "--vibe",
        default=None,
        metavar="VIBE",
        help=(
            "Lifestyle vibe hint. Options: movie_night, cozy_kitchen, gallery_wall, "
            "morning_coffee, office_desk, bedroom, outdoor, holiday. "
            "Defaults to auto-select based on --product."
        ),
    )
    parser.add_argument(
        "--product",
        default=None,
        metavar="PRODUCT",
        help="Product type key (e.g. canvas, mug, blanket). Helps auto-select vibe.",
    )
    parser.add_argument(
        "--style",
        default=None,
        metavar="STYLE",
        help="Art style name (e.g. moody_botanical). Used to guide the staging prompt.",
    )
    parser.add_argument(
        "--output",
        required=True,
        metavar="PATH",
        help="Output file path (e.g. output/staged.png).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    # Validate GEMINI_API_KEY early so the error is clear
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print(
            "Error: GEMINI_API_KEY environment variable is not set. "
            "Export your Gemini API key before running this script.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"Input:    {args.input}", file=sys.stderr)
    print(f"Platform: {args.platform}", file=sys.stderr)

    # Resolve display values and vibe
    product_disp = resolve_product_display(args.product)
    style_disp = resolve_style_display(args.style)
    effective_vibe = resolve_vibe(args.product, args.vibe)
    resolution = PLATFORM_RESOLUTION[args.platform]
    aspect_ratio = PLATFORM_ASPECT_RATIO[args.platform]

    print(f"Product:  {product_disp}", file=sys.stderr)
    print(f"Style:    {style_disp}", file=sys.stderr)
    print(f"Vibe:     {effective_vibe or '(default)'}", file=sys.stderr)
    print(f"Output:   {args.output}", file=sys.stderr)

    # Build prompt
    prompt = build_prompt(
        platform=args.platform,
        product_display=product_disp,
        style_display=style_disp,
        vibe=effective_vibe,
        aspect_ratio=aspect_ratio,
    )

    # Load input image
    print("Loading input image...", file=sys.stderr)
    pil_image = load_image(args.input)
    print(f"  Size: {pil_image.size[0]}x{pil_image.size[1]} mode={pil_image.mode}", file=sys.stderr)

    # Call Gemini
    client = genai.Client(api_key=api_key)
    image_bytes = call_gemini(client, pil_image, prompt, resolution)

    # Save output
    print(f"Saving output to {args.output}...", file=sys.stderr)
    save_image(image_bytes, args.output)
    print("Done.", file=sys.stderr)


if __name__ == "__main__":
    main()
