#!/usr/bin/env python3
"""
Generate the GitHub social preview / Open Graph card for claude-context-tick.

Produces a 1280x640 PNG at assets/social-preview.png matching the GitHub
social preview spec (also rendered as the og:image on link unfurls).

Design language:
  - Pure type + color block. No clip art, no logos, no gradients.
  - Background: GitHub dark (#0D1117) — blends into the GitHub repo page.
  - Hero glyph is the literal <context-tick> marker the tool injects, so the
    card *is* a sample of the tool's output.
  - Anthropic terracotta (#CC785C) used sparingly: only the angle brackets
    of the open/close tags are tinted. Everything else is soft white.

Usage:
    python3 scripts/generate-social-preview.py

Re-runnable: overwrites assets/social-preview.png each invocation.

Requires Pillow:
    pip install Pillow
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Canvas — GitHub social preview spec
CANVAS_W = 1280
CANVAS_H = 640

# Output path (relative to repo root)
REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "assets" / "social-preview.png"

# Colors
BG_COLOR = (0x0D, 0x11, 0x17)           # GitHub dark
TEXT_PRIMARY = (0xF0, 0xF0, 0xF0)       # soft white for hero glyph + repo name
TEXT_SECONDARY = (0x9D, 0xA5, 0xB4)     # muted gray for tagline
ACCENT = (0xCC, 0x78, 0x5C)             # Anthropic terracotta — angle brackets only

# Font sizes (hero is auto-shrunk to fit HERO_MAX_WIDTH)
HERO_SIZE_MAX = 58              # try this first; auto-shrink if needed
HERO_SIZE_MIN = 24              # don't shrink below this
HERO_MAX_WIDTH = 1140           # leave ~70px padding each side
REPO_NAME_SIZE = 42
TAGLINE_SIZE = 26

# Hero glyph parts (split so we can tint the brackets independently)
HERO_OPEN = "<"
HERO_OPEN_TAG = "context-tick"
HERO_CLOSE_GT = ">"
HERO_PAYLOAD = "2026-05-06 · 14:41 CDT"   # middle dot U+00B7
HERO_CLOSE_OPEN = "</"
HERO_CLOSE_TAG = "context-tick"
HERO_CLOSE_GT2 = ">"

# Repo + tagline
REPO_NAME = "claude-context-tick"
TAGLINE = "wall-clock time for Claude Code agents"

# Font fallback chain — first found wins.
# Tilde paths are expanded so user-installed fonts are picked up portably.
FONT_CANDIDATES = [
    # JetBrains Mono (preferred — common Nerd Font + standard installs)
    "~/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf",
    "~/Library/Fonts/JetBrainsMono-Regular.ttf",
    "/Library/Fonts/JetBrainsMono-Regular.ttf",
    "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Regular.ttf",
    # SF Mono (macOS system)
    "/System/Library/Fonts/SFNSMono.ttf",
    "/Library/Fonts/SF-Mono-Regular.otf",
    "/System/Applications/Utilities/Terminal.app/Contents/Resources/Fonts/SFMono-Regular.otf",
    # Menlo (macOS fallback)
    "/System/Library/Fonts/Menlo.ttc",
    # DejaVu Sans Mono (Linux)
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
]


# ---------------------------------------------------------------------------
# Font loading
# ---------------------------------------------------------------------------

def find_font_path() -> str | None:
    """Return the first existing font path (after `~` expansion), or None."""
    for path in FONT_CANDIDATES:
        expanded = os.path.expanduser(path)
        if os.path.isfile(expanded):
            return expanded
    return None


def load_font(path: str | None, size: int) -> ImageFont.ImageFont:
    """Load a TTF/OTF at the given size, or fall back to PIL's default."""
    if path is None:
        return ImageFont.load_default()
    try:
        return ImageFont.truetype(path, size)
    except (OSError, ValueError):
        return ImageFont.load_default()


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

def measure(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> tuple[int, int]:
    """Return (width, height) of `text` rendered with `font`."""
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def draw_hero_line(
    draw: ImageDraw.ImageDraw,
    font: ImageFont.ImageFont,
    cx: int,
    baseline_y: int,
) -> None:
    """
    Draw the hero glyph centered horizontally on `cx`, with the visual
    baseline at `baseline_y`. Angle brackets are tinted with ACCENT;
    everything else is TEXT_PRIMARY.

    Layout (single line):
      <context-tick>2026-05-06 · 14:41 CDT</context-tick>
       ^                                  ^
       └── ACCENT brackets ───────────────┘
    """
    parts = [
        (HERO_OPEN,        ACCENT),
        (HERO_OPEN_TAG,    TEXT_PRIMARY),
        (HERO_CLOSE_GT,    ACCENT),
        (HERO_PAYLOAD,     TEXT_PRIMARY),
        (HERO_CLOSE_OPEN,  ACCENT),
        (HERO_CLOSE_TAG,   TEXT_PRIMARY),
        (HERO_CLOSE_GT2,   ACCENT),
    ]

    # Measure each segment to compute total width + per-segment x offsets.
    widths = [measure(draw, txt, font)[0] for txt, _ in parts]
    total_w = sum(widths)
    x = cx - total_w // 2

    # Use anchor "ls" (left, baseline) so all segments share the same baseline.
    for (txt, color), w in zip(parts, widths):
        draw.text((x, baseline_y), txt, font=font, fill=color, anchor="ls")
        x += w


# ---------------------------------------------------------------------------
# Main render
# ---------------------------------------------------------------------------

FULL_HERO_TEXT = (
    HERO_OPEN + HERO_OPEN_TAG + HERO_CLOSE_GT
    + HERO_PAYLOAD
    + HERO_CLOSE_OPEN + HERO_CLOSE_TAG + HERO_CLOSE_GT2
)


def fit_hero_font(
    draw: ImageDraw.ImageDraw,
    font_path: str | None,
    max_width: int,
) -> tuple[ImageFont.ImageFont, int]:
    """
    Pick the largest hero font size (between HERO_SIZE_MIN and HERO_SIZE_MAX)
    whose rendered width for FULL_HERO_TEXT fits within `max_width`.

    Returns (font, size_used).
    """
    chosen = HERO_SIZE_MIN
    for size in range(HERO_SIZE_MAX, HERO_SIZE_MIN - 1, -1):
        candidate = load_font(font_path, size)
        w, _ = measure(draw, FULL_HERO_TEXT, candidate)
        if w <= max_width:
            chosen = size
            break
    return load_font(font_path, chosen), chosen


def render() -> tuple[Path, str, int]:
    """Render the card. Returns (output_path, font_path_used, hero_size_used)."""
    font_path = find_font_path()

    img = Image.new("RGB", (CANVAS_W, CANVAS_H), BG_COLOR)
    draw = ImageDraw.Draw(img)

    hero_font, hero_size = fit_hero_font(draw, font_path, HERO_MAX_WIDTH)
    repo_font = load_font(font_path, REPO_NAME_SIZE)
    tag_font = load_font(font_path, TAGLINE_SIZE)

    cx = CANVAS_W // 2

    # Optical centering: place the hero glyph slightly above mathematical
    # center so the three-line stack feels balanced (the eye reads the
    # composition's center of mass, which sits below the hero line).
    # Spacing uses fixed constants — not derived from the auto-fit hero
    # size — so the layout breathes consistently regardless of how much
    # the hero shrinks to fit the canvas.
    hero_baseline_y = int(CANVAS_H * 0.42)          # ~268: hero baseline
    repo_baseline_y = hero_baseline_y + 110         # gap to repo name
    tag_baseline_y = repo_baseline_y + 60           # gap to tagline

    # Hero line (with selective accent on brackets)
    draw_hero_line(draw, hero_font, cx, hero_baseline_y)

    # Repo name — soft white, centered
    draw.text(
        (cx, repo_baseline_y),
        REPO_NAME,
        font=repo_font,
        fill=TEXT_PRIMARY,
        anchor="ms",  # middle, baseline
    )

    # Tagline — muted gray, centered
    draw.text(
        (cx, tag_baseline_y),
        TAGLINE,
        font=tag_font,
        fill=TEXT_SECONDARY,
        anchor="ms",
    )

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUTPUT_PATH, "PNG", optimize=True)

    return OUTPUT_PATH, font_path or "PIL default", hero_size


def main() -> int:
    out, font_used, hero_size = render()
    size_kb = out.stat().st_size / 1024
    print(f"Wrote {out} ({CANVAS_W}x{CANVAS_H}, {size_kb:.1f} KB)")
    print(f"Font: {font_used}")
    print(f"Hero size (auto-fit): {hero_size}px")
    return 0


if __name__ == "__main__":
    sys.exit(main())
