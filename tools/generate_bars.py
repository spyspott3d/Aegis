#!/usr/bin/env python3
"""
Generate .tga textures for Aegis bar shapes.

Each shape produces two files:
  <Name>.tga    — fill texture, white silhouette with full alpha. Tinted at
                  runtime via SetVertexColor in Lua.
  <Name>BG.tga  — background variant, dark grey with moderate alpha, used
                  behind the fill so the empty portion of the bar is visible.

Output goes to Aegis/Textures/.

WoW 3.3.5a constraints honoured:
  - Power-of-2 dimensions on both axes (default 64x256).
  - 32-bit RGBA, uncompressed Targa (PIL's default for RGBA images).

Curve geometry: the bar's spine (center line) follows a circular arc whose
chord is the canvas's vertical centerline and whose sagitta is the requested
bulge. The bar has constant thickness perpendicular to that spine. Top and
bottom are flat (the bar runs full canvas height) so a TexCoord-based
bottom-up fill cuts cleanly across the shape at any percentage.

Usage:
    python tools/generate_bars.py
    python tools/generate_bars.py --width 128 --height 512
"""

import argparse
import math
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow required: pip install Pillow")


# Render at SUPER x supersampling, then downscale with Lanczos for AA edges.
SUPER = 4

# Subdivisions per curved silhouette edge. 64 keeps the polygon smooth even
# at large supersampled sizes; the cost is trivial compared to the rasterizer.
SAMPLES = 64

# Base color for the fill texture. The actual displayed color is determined
# at runtime by texture:SetVertexColor; white as a base preserves any tint.
FILL_RGBA = (255, 255, 255, 255)

# Background variant: dark grey at moderate alpha, sits behind the fill so
# the empty portion of the bar reads as "track".
BG_RGBA = (26, 26, 26, 200)


def spine_x(y, sh, cx, bulge):
    """X coordinate of the spine at vertical position y.

    The spine is a circular arc through (cx, 0), (cx + bulge, sh/2), (cx, sh).
    Derivation: chord c = sh, sagitta s = |bulge|, radius r = (c^2+4s^2)/(8s).
    """
    if abs(bulge) < 0.5:
        return cx
    sign = 1 if bulge > 0 else -1
    s = abs(bulge)
    r = (sh * sh + 4 * s * s) / (8 * s)
    dy = y - sh / 2
    inside = r * r - dy * dy
    if inside < 0:
        return cx
    return cx + sign * (math.sqrt(inside) - (r - s))


def edge_x(y, sh, cx, bulge):
    """X coordinate at vertical position y of an arc through (cx, 0) /
    (cx + bulge, sh/2) / (cx, sh). Same math as spine_x; reused here for
    each edge of the bar in lens modes."""
    return spine_x(y, sh, cx, bulge)


def render_bar(width, height, rgba, curvature, thickness_ratio, mode,
               center_bbox=False):
    """Render a vertical bar.

    Args:
      width, height: final image size in pixels (both should be power of 2).
      rgba: silhouette color as a 4-tuple.
      curvature: bulge as a fraction of `width`. 0.0 = straight rectangle.
                  +0.30 = right bulge (silhouette like `)`).
                  -0.30 = left bulge  (silhouette like `(`).
      thickness_ratio: bar thickness at midpoint as a fraction of `width`.
      mode: how the silhouette is built.
        "offset"    — parallel offset of a single spine arc. Constant
                      perpendicular thickness; outer edge looks visibly
                      flatter than inner edge (geometrically inevitable
                      for parallel curves of a circle).
        "lens"      — inner and outer edges are independent circular arcs
                      (sagittas curvature ± thickness/2). Both edges curve
                      the same direction; bar is widest at midpoint and
                      narrows to cusps at the top and bottom. Visually
                      balanced curvature on both edges.
        "lens-flat" — like lens but with a flat horizontal top and bottom
                      cap so the bar reads as a clean status bar that
                      doesn't taper to zero width at its ends.
    """
    sw, sh = width * SUPER, height * SUPER
    img = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    bulge = curvature * sw
    thick = thickness_ratio * sw

    # Spine origin. By default the spine endpoints sit at canvas center cx
    # which means the spine bulge can poke past the canvas edge for fat
    # bars (`thick + 2*|bulge|` exceeding the canvas width gets clipped by
    # PIL silently — visible as the bar's outer edge looking artificially
    # flattened). With center_bbox=True we slide the spine sideways by
    # bulge/2 so the bar's bounding box is centered in the canvas. Trade-off:
    # the spine endpoints (top and bottom of the bar) are no longer at
    # canvas center, so the texture's "natural anchor" shifts opposite the
    # curvature direction. That is fine for status bars where the user
    # picks one shape per bar — the addon side just renders the texture as
    # is.
    if center_bbox:
        cx = sw / 2 - bulge / 2
    else:
        cx = sw / 2

    if mode == "offset":
        # Both edges = parallel offset of the spine arc by ±thick/2.
        points = []
        for i in range(SAMPLES + 1):
            y = (i / SAMPLES) * sh
            spx = spine_x(y, sh, cx, bulge)
            points.append((spx + thick / 2, y))
        for i in range(SAMPLES, -1, -1):
            y = (i / SAMPLES) * sh
            spx = spine_x(y, sh, cx, bulge)
            points.append((spx - thick / 2, y))
        draw.polygon(points, fill=rgba)

    elif mode in ("lens", "lens-flat"):
        # Outer edge bulges by (curvature + thickness/2); inner by
        # (curvature - thickness/2). Sign of `bulge` chooses left/right.
        sign = 1 if bulge >= 0 else -1
        outer_b = sign * (abs(bulge) + thick / 2)
        inner_b = sign * (abs(bulge) - thick / 2)

        if mode == "lens":
            # Cusps: both edges meet at (cx, 0) and (cx, sh).
            top_y, bot_y = 0, sh
        else:
            # Flat caps: pull the arcs inward by ~3% of height so there is a
            # short straight segment at top and bottom. Looks like a status
            # bar with rounded sides instead of pointy ends.
            cap = sh * 0.06
            top_y, bot_y = cap, sh - cap

        points = []
        # Outer edge top → bottom
        for i in range(SAMPLES + 1):
            t = i / SAMPLES
            y = top_y + (bot_y - top_y) * t
            points.append((edge_x(y, sh, cx, outer_b), y))
        # Bottom flat cap (lens-flat only adds a real segment here)
        if mode == "lens-flat":
            points.append((cx + thick / 2, sh))
            points.append((cx - thick / 2, sh))
        # Inner edge bottom → top
        for i in range(SAMPLES, -1, -1):
            t = i / SAMPLES
            y = top_y + (bot_y - top_y) * t
            points.append((edge_x(y, sh, cx, inner_b), y))
        # Top flat cap
        if mode == "lens-flat":
            points.append((cx - thick / 2, 0))
            points.append((cx + thick / 2, 0))

        draw.polygon(points, fill=rgba)

    else:
        sys.exit("unknown mode: {}".format(mode))

    return img.resize((width, height), Image.LANCZOS)


def save_tga(img, path):
    """Save as 32-bit uncompressed Targa.

    PIL writes uncompressed Targa with image type 2 and 32 bpp by default for
    RGBA images, which is the format WoW 3.3.5a's TGA loader expects.
    """
    img.save(path, format="TGA")


def validate_tga(path):
    """Reload the file and check size + mode are valid for the WoW client."""
    with Image.open(path) as im:
        w, h = im.size
        pow2 = (w & (w - 1)) == 0 and (h & (h - 1)) == 0
        return im.mode == "RGBA" and pow2, im.mode, im.size


def generate_canonical(width, height):
    """Regenerate the two canonical bar texture sets shipped with the addon.

    These two sets were chosen after side-by-side WoW testing:
      Thin: thickness=0.30, offset mode, center_bbox.
            Slim parenthesis silhouette; both edges visually parallel.
      Wide: thickness=0.40, offset mode, center_bbox.
            Slightly fatter; both edges still well-balanced thanks to the
            bbox-centered spine that keeps the outer edge clear of the
            canvas border.
    Both use curvature=±0.30 for the arc variants. To explore alternatives,
    drop --canonical and use the explicit --thickness / --mode flags.
    """
    canonical = [
        ("Thin", 0.30),
        ("Wide", 0.40),
    ]
    shapes = [
        ("Bar",      0.00),
        ("ArcRight", +0.30),
        ("ArcLeft",  -0.30),
    ]
    for set_name, thickness in canonical:
        out = Path("Aegis/Textures") / set_name
        out.mkdir(parents=True, exist_ok=True)
        print("Writing {} (thickness={:.2f})".format(out.resolve(), thickness))
        for name, curv in shapes:
            for variant, color in (("", FILL_RGBA), ("BG", BG_RGBA)):
                img = render_bar(width, height, color, curv,
                                 thickness, "offset", center_bbox=True)
                path = out / "{}{}.tga".format(name, variant)
                save_tga(img, path)
                ok, mode, size = validate_tga(path)
                tag = "ok  " if ok else "FAIL"
                print("  [{}] {}  {} {}x{}".format(tag, path.name, mode,
                                                   size[0], size[1]))


def main():
    ap = argparse.ArgumentParser(description="Generate .tga bar shape textures.")
    ap.add_argument("--out", default="Aegis/Textures",
                    help="Output directory (relative to repo root or absolute)")
    ap.add_argument("--width", type=int, default=64,
                    help="Texture width in pixels (power of 2)")
    ap.add_argument("--height", type=int, default=256,
                    help="Texture height in pixels (power of 2)")
    ap.add_argument("--thickness", type=float, default=0.6,
                    help="Bar thickness as a fraction of canvas width")
    ap.add_argument("--mode", choices=("offset", "lens", "lens-flat"),
                    default="offset",
                    help="Edge geometry: parallel offset (default), lens "
                         "(both edges curve same direction, cusps at ends), "
                         "or lens-flat (lens with a flat top/bottom cap)")
    ap.add_argument("--center-bbox", action="store_true",
                    help="Slide the spine sideways so the bar's bounding "
                         "box is centered in the canvas. Avoids canvas-edge "
                         "clipping when thickness + 2*|bulge| exceeds the "
                         "canvas width.")
    ap.add_argument("--canonical", action="store_true",
                    help="Regenerate the two canonical sets shipped with "
                         "the addon (Aegis/Textures/Thin and "
                         "Aegis/Textures/Wide). Ignores --thickness, "
                         "--mode, --center-bbox and --out.")
    args = ap.parse_args()

    if args.canonical:
        return generate_canonical(args.width, args.height)

    # Sanity-check power-of-2 inputs early — silently failing in WoW is the
    # worst outcome (texture just doesn't draw, no error in chat).
    for label, v in (("--width", args.width), ("--height", args.height)):
        if v <= 0 or (v & (v - 1)) != 0:
            sys.exit("{} must be a positive power of 2 (got {})".format(label, v))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    shapes = [
        ("Bar",      0.00),  # straight rectangle, sanity baseline
        ("ArcRight", +0.30),
        ("ArcLeft",  -0.30),
    ]

    print("Writing to {}/  (mode: {}, center_bbox: {})".format(
        out.resolve(), args.mode, args.center_bbox))
    for name, curv in shapes:
        for variant, color in (("", FILL_RGBA), ("BG", BG_RGBA)):
            img = render_bar(args.width, args.height, color, curv,
                             args.thickness, args.mode, args.center_bbox)
            path = out / "{}{}.tga".format(name, variant)
            save_tga(img, path)
            ok, mode, size = validate_tga(path)
            tag = "ok  " if ok else "FAIL"
            print("  [{}] {}  {} {}x{}".format(tag, path.name, mode, size[0], size[1]))


if __name__ == "__main__":
    main()
