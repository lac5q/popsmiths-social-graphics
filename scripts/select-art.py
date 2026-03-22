#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""
select-art.py — Select a PopSmiths art image from the sample gallery.

Sample gallery root: /Users/lcalderon/github/popsmiths_app/public/samples/
Structure: {root}/{style}/{product}.jpg
"""

import argparse
import json
import os
import random
import sys
from datetime import date
from pathlib import Path

GALLERY_ROOT = Path("/root/github/popsmiths-art-app/public/style-previews/v3")

MIN_FILE_BYTES = 5000

KNOWN_STYLES = [
    "abstract_color_field",
    "art_deco_geometric",
    "block_print_folk",
    "celestial_map",
    "chinoiserie",
    "coastal_seascape",
    "comic_halftone",
    "continuous_line_pop",
    "duotone_split",
    "gilded_baroque",
    "holographic",
    "liquid_chrome",
    "moody_botanical",
    "single_accent_minimalist",
    "terrazzo_organic",
    "vintage_travel_poster",
    "wabi_sabi",
]

KNOWN_PRODUCTS = [
    "blanket",
    "canvas",
    "framed",
    "greetingcard",
    "hoodie",
    "iphone",
    "kidshoodie",
    "kidstshirt",
    "laptopsleeve",
    "mousepad",
    "mug",
    "ornament",
    "pillow",
    "prints",
    "puzzle",
    "samsung",
    "socks",
    "sticker",
    "sweatshirt",
    "tanktop",
    "totebag",
    "tshirt",
    "waterbottle",
]

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


def style_display(style: str) -> str:
    """Convert underscore_case style name to Title Case display."""
    return " ".join(word.capitalize() for word in style.split("_"))


def product_display(product: str) -> str:
    """Map product key to human-readable display name."""
    if product in PRODUCT_DISPLAY:
        return PRODUCT_DISPLAY[product]
    return product.capitalize()


def get_available_styles() -> list[str]:
    """Return list of style directories that exist under GALLERY_ROOT."""
    styles = []
    for name in sorted(KNOWN_STYLES):
        path = GALLERY_ROOT / name
        if path.is_dir():
            styles.append(name)
    return styles


def get_valid_products(style: str) -> list[str]:
    """
    Return products available for the given style that pass the minimum
    file size filter (>= MIN_FILE_BYTES).
    """
    style_dir = GALLERY_ROOT / style
    valid = []
    for product in KNOWN_PRODUCTS:
        filepath = style_dir / f"{product}.jpg"
        if filepath.is_file() and filepath.stat().st_size >= MIN_FILE_BYTES:
            valid.append(product)
    return valid


def make_rng(style: str, product: str | None) -> random.Random:
    """
    Return a Random instance seeded on today's date + style.
    When product is not specified the same style picks the same product
    each calendar day, providing consistent daily posts.
    """
    today = date.today().isoformat()  # e.g. "2026-03-22"
    seed_str = f"{today}:{style}"
    return random.Random(seed_str)


def build_result(style: str, product: str) -> dict:
    filepath = GALLERY_ROOT / style / f"{product}.jpg"
    return {
        "art_path": str(filepath.resolve()),
        "style": style,
        "product": product,
        "style_display": style_display(style),
        "product_display": product_display(product),
        "file_size_bytes": filepath.stat().st_size,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Select a PopSmiths art image from the sample gallery."
    )
    parser.add_argument(
        "--style",
        metavar="STYLE",
        help="Specific style name. Omit to pick randomly.",
    )
    parser.add_argument(
        "--product",
        metavar="PRODUCT",
        help="Specific product name. Omit to pick randomly from the style.",
    )
    parser.add_argument(
        "--list-styles",
        action="store_true",
        help="Print all available styles (one per line) and exit.",
    )
    parser.add_argument(
        "--list-products",
        action="store_true",
        help="Print all products available for --style and exit.",
    )
    parser.add_argument(
        "--output-json",
        action="store_true",
        default=True,
        help="Print result as JSON to stdout (default).",
    )
    args = parser.parse_args()

    # --list-styles
    if args.list_styles:
        for s in get_available_styles():
            print(s)
        sys.exit(0)

    # --list-products requires --style
    if args.list_products:
        if not args.style:
            print("Error: --list-products requires --style", file=sys.stderr)
            sys.exit(1)
        style = args.style
        if not (GALLERY_ROOT / style).is_dir():
            print(f"Error: style '{style}' not found", file=sys.stderr)
            sys.exit(1)
        products = get_valid_products(style)
        if not products:
            print(
                f"Error: no valid products found for style '{style}'",
                file=sys.stderr,
            )
            sys.exit(1)
        for p in products:
            print(p)
        sys.exit(0)

    # Resolve style
    if args.style:
        style = args.style
        if not (GALLERY_ROOT / style).is_dir():
            print(f"Error: style '{style}' not found", file=sys.stderr)
            sys.exit(1)
    else:
        available_styles = get_available_styles()
        if not available_styles:
            print("Error: no styles found in gallery root", file=sys.stderr)
            sys.exit(1)
        rng = make_rng("__style__", None)
        style = rng.choice(available_styles)

    # Resolve product
    if args.product:
        product = args.product
        filepath = GALLERY_ROOT / style / f"{product}.jpg"
        if not filepath.is_file():
            print(
                f"Error: product '{product}' not found for style '{style}'",
                file=sys.stderr,
            )
            sys.exit(1)
        if filepath.stat().st_size < MIN_FILE_BYTES:
            print(
                f"Error: product '{product}' for style '{style}' is a placeholder "
                f"(file too small: {filepath.stat().st_size} bytes)",
                file=sys.stderr,
            )
            sys.exit(1)
    else:
        valid_products = get_valid_products(style)
        if not valid_products:
            print(
                f"Error: no valid products found for style '{style}'",
                file=sys.stderr,
            )
            sys.exit(1)
        rng = make_rng(style, None)
        product = rng.choice(valid_products)

    result = build_result(style, product)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
