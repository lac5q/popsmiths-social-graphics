#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "pillow>=10.0.0",
# ]
# ///
"""
qa-check.py — Quality gate for PopSmiths social graphics.

Runs a series of checks on a composed image and its caption before the post
is allowed to go live. Exits 0 on PASS, 1 on FAIL.

Usage:
    python qa-check.py \\
        --image  /path/to/composed.jpg \\
        --caption /path/to/caption.txt \\
        --platform instagram \\
        [--output-dir /path/to/run-dir] \\
        [--strict]
"""

import argparse
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Platform constraints
# ---------------------------------------------------------------------------

# (min_width, min_height) in pixels
MIN_DIMENSIONS: dict[str, tuple[int, int]] = {
    "instagram": (1080, 1350),
    "pinterest": (1000, 1500),
    "x": (1200, 675),
}

# Maximum caption character counts
MAX_CAPTION_CHARS: dict[str, int] = {
    "instagram": 2200,
    "pinterest": 500,
    "x": 280,
}

# Minimum image file size in bytes (catch placeholders / corrupt files)
MIN_IMAGE_BYTES = 100 * 1024  # 100 KB

# ---------------------------------------------------------------------------
# Brand copy rules
# ---------------------------------------------------------------------------

# These terms are hard blockers — post must not be published if any are found
FORBIDDEN_TERMS: list[str] = [
    "artificial intelligence",
    "a.i.",
    " prompt",
    "generat",  # catches: generate, generated, generates, generation
    " easy ",
    " simple ",
    " upload",
    "discover",
    "algorithm",
]

# "ai" alone needs word-boundary treatment to avoid false positives
# (e.g., "AItch", "said", "paid"). We handle it as a special case below.
FORBIDDEN_WORD_AI = "ai"

# These terms warrant a warning but do not block posting
WARN_TERMS: list[str] = [
    "technology",
    "digital",
]

REQUIRED_URL = "popsmiths.com"

# ---------------------------------------------------------------------------
# Result accumulator
# ---------------------------------------------------------------------------


class QAResult:
    def __init__(self) -> None:
        self.lines: list[str] = []
        self.fail_count = 0
        self.warn_count = 0

    def passed(self, check: str) -> None:
        self.lines.append(f"✓ PASS: {check}")

    def failed(self, check: str, reason: str) -> None:
        self.lines.append(f"✗ FAIL: {check} — {reason}")
        self.fail_count += 1

    def warned(self, check: str, reason: str) -> None:
        self.lines.append(f"⚠ WARN: {check} — {reason}")
        self.warn_count += 1

    @property
    def passed_overall(self) -> bool:
        return self.fail_count == 0

    def summary_line(self) -> str:
        if self.passed_overall:
            return "QA RESULT: PASS"
        return f"QA RESULT: FAIL — {self.fail_count} issue(s) found"

    def render(self) -> str:
        return "\n".join(self.lines + ["", self.summary_line()])


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------


def check_image_exists(image_path: Path, result: QAResult) -> bool:
    """Returns True only if the file exists so subsequent image checks can proceed."""
    if not image_path.exists():
        result.failed("Image file exists", f"file not found: {image_path}")
        return False
    result.passed("Image file exists")
    return True


def check_image_valid(image_path: Path, result: QAResult) -> bool:
    """
    Returns True only if PIL can open the file so dimension checks can proceed.
    Importing PIL here keeps the top-level import lightweight.
    """
    try:
        from PIL import Image  # type: ignore[import]

        with Image.open(image_path) as img:
            img.verify()  # raises on corrupt files
        result.passed("Image is valid (PIL can open)")
        return True
    except ImportError:
        result.warned(
            "Image validity",
            "Pillow not installed — skipping image checks. Install with: pip install Pillow",
        )
        return False
    except Exception as exc:  # noqa: BLE001
        result.failed("Image is valid (PIL can open)", str(exc))
        return False


def check_image_dimensions(
    image_path: Path, platform: str, result: QAResult
) -> None:
    from PIL import Image  # type: ignore[import]

    min_w, min_h = MIN_DIMENSIONS[platform]
    with Image.open(image_path) as img:
        width, height = img.size

    if width >= min_w and height >= min_h:
        result.passed(f"Image dimensions ({width}x{height} >= {min_w}x{min_h})")
    else:
        result.failed(
            "Image dimensions",
            f"got {width}x{height}, minimum for {platform} is {min_w}x{min_h}",
        )


def check_image_size(image_path: Path, result: QAResult) -> None:
    size = image_path.stat().st_size
    if size >= MIN_IMAGE_BYTES:
        result.passed(f"Image file size ({size // 1024} KB >= 100 KB)")
    else:
        result.failed(
            "Image file size",
            f"only {size} bytes — likely a placeholder or corrupt file",
        )


def check_caption_url(caption: str, result: QAResult) -> None:
    if REQUIRED_URL in caption.lower():
        result.passed(f"Caption contains '{REQUIRED_URL}'")
    else:
        result.failed(
            "Caption contains required URL",
            f"'{REQUIRED_URL}' not found in caption",
        )


def check_caption_forbidden_words(caption: str, result: QAResult) -> None:
    lower = caption.lower()
    violations: list[str] = []

    # Check plain substring terms
    for term in FORBIDDEN_TERMS:
        if term in lower:
            violations.append(f'"{term}"')

    # Check "ai" as a whole word to avoid false positives
    import re

    if re.search(r"\bai\b", lower):
        violations.append('"ai" (as a standalone word)')

    if violations:
        result.failed(
            "Caption forbidden words",
            "found banned term(s): " + ", ".join(violations),
        )
    else:
        result.passed("Caption forbidden words")

    # Warnings for borderline terms
    for term in WARN_TERMS:
        if term in lower:
            result.warned(
                "Caption borderline term",
                f'"{term}" found — review to ensure it fits brand voice',
            )


def check_caption_length(caption: str, platform: str, result: QAResult) -> None:
    length = len(caption)
    max_len = MAX_CAPTION_CHARS[platform]
    if length <= max_len:
        result.passed(f"Caption length ({length} chars <= {max_len})")
    else:
        result.failed(
            "Caption length",
            f"{length} chars exceeds {platform} limit of {max_len}",
        )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Quality gate for PopSmiths social post images and captions."
    )
    parser.add_argument("--image", required=True, help="Path to composed image file")
    parser.add_argument(
        "--caption", required=True, help="Path to caption.txt"
    )
    parser.add_argument(
        "--platform",
        required=True,
        choices=["instagram", "pinterest", "x"],
        help="Target social platform",
    )
    parser.add_argument(
        "--output-dir",
        dest="output_dir",
        default=None,
        help="Optional directory to write qa-report.txt",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Enable strict mode (note: Gemini vision checks not yet implemented)",
    )
    args = parser.parse_args()

    if args.strict:
        print(
            "Info: --strict mode requested — Gemini vision checks not yet implemented. "
            "Running standard checks only.",
            file=sys.stderr,
        )

    image_path = Path(args.image)
    caption_path = Path(args.caption)
    result = QAResult()

    # --- Check 1: Image exists ---
    image_present = check_image_exists(image_path, result)

    # --- Check 2 & 3: Image validity and size (only if file exists) ---
    pil_ok = False
    if image_present:
        pil_ok = check_image_valid(image_path, result)
        check_image_size(image_path, result)

    # --- Check 4: Image dimensions (only if PIL succeeded) ---
    if image_present and pil_ok:
        check_image_dimensions(image_path, args.platform, result)

    # --- Load caption ---
    if not caption_path.exists():
        result.failed("Caption file exists", f"file not found: {caption_path}")
        caption_text = ""
    else:
        result.passed("Caption file exists")
        caption_text = caption_path.read_text(encoding="utf-8").strip()

    # --- Check 5: Required URL ---
    if caption_text:
        check_caption_url(caption_text, result)

    # --- Check 6: Forbidden words ---
    if caption_text:
        check_caption_forbidden_words(caption_text, result)

    # --- Check 7: Caption length ---
    if caption_text:
        check_caption_length(caption_text, args.platform, result)

    # --- Output ---
    report = result.render()
    print(report)

    if args.output_dir:
        output_dir = Path(args.output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "qa-report.txt").write_text(report + "\n", encoding="utf-8")
        print(f"\nQA report written to: {output_dir / 'qa-report.txt'}")

    sys.exit(0 if result.passed_overall else 1)


if __name__ == "__main__":
    main()
