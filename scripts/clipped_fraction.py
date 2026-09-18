"""How much of a hero's FACE is blown out to white, as a number.

Bead godot-test1-z3e.14 (the authored faces clipped to paper white; the owner
could not make out a nose or a pair of lips). The fix was judged on this, not on
opinion: the fraction of face pixels whose Rec.709 luma is >= `THRESHOLD` in a
`17_head_face` frame. Run it again the day anyone touches a hero palette,
`scripts/toon_shading.gd` or the environment block in `scenes/main.tscn` — and on
an ENGINE UPGRADE, which is the fourth thing that moves it: the numbers behind
this bead were taken on Godot 4.5, and `ToonShading.style()` carries a
Compatibility workaround that a later engine could turn into a double decode.

    # take the frames first (WINDOWED, one at a time, bounded — --headless hangs)
    perl -e 'alarm 600; exec @ARGV' godot --path . scenes/style_shots.tscn \
        -- /tmp/after/windman_fp hero=windman only=17_head_face hide=weather,fauna
    perl -e 'alarm 600; exec @ARGV' godot --rendering-method gl_compatibility \
        --path . scenes/style_shots.tscn -- /tmp/after/windman_web \
        hero=windman only=17_head_face hide=weather,fauna web
    # teibi's face is on the skinned body: add `body=skinned`
    python3 scripts/clipped_fraction.py windman /tmp/after/windman_fp/17_head_face.png
    python3 scripts/clipped_fraction.py 0.377,0.489,0.498,0.636 frame.png   # own rect
    # the dragon is judged on `flat`, not on `clipped`, and is selected by COLOUR
    # and not by a rect — see `measure` and `COLOUR_REGIONS`
    python3 scripts/clipped_fraction.py phoboman_dragon /tmp/after/pho_web/18_body_3m.png

THE RECT IS THE WHOLE TRICK. It is given in FRACTIONS of the frame, so it follows
the framing at any resolution, and each hero's is chosen to lie ENTIRELY INSIDE
the face — no sky, no ground, no collar. The printed fraction is then exactly
"how much of the face is clipped" with nothing to argue about, and the same rect
must be used before and after or the comparison means nothing. `17_head_face`
frames crown-relative, so they hold for any build of these heroes.

No PIL on the machine this was written for, hence the ~40 lines of zlib below;
`Image.get_pixel` in GDScript would have been the other way round.
"""

import struct
import sys
import zlib

# Rec.709 luma on the DISPLAYED (sRGB-encoded) pixel, which is what an eye
# judges, and the level above which a face has stopped showing its shape.
THRESHOLD = 0.97

# hero -> (x0, y0, x1, y1) as fractions of the frame; see the module docstring.
#
# `phoboman`'s is the VISOR INTERIOR and not a face, because his face is a bowl of
# soup behind a porthole and the MakeHuman head under the helmet is never seen
# (bead godot-test1-9k9n.5). Same rule as the other three all the same: the rect
# lies entirely inside the thing being judged — inscribed in the porthole, clear of
# the glass bevel and the brass rim — so the fraction is "how much of the visor is
# blown out" with nothing to argue about.
FACE_RECTS = {
    "windman": (0.377, 0.489, 0.498, 0.636),
    "primm": (0.445, 0.533, 0.570, 0.689),
    "teibi": (0.460, 0.498, 0.600, 0.711),
    "phoboman": (0.5525, 0.510, 0.6825, 0.770),
}

# ...AND ONE REGION THAT IS NOT A RECT (bead godot-test1-9k9n.8). A rect works for
# a face because `17_head_face` frames crown-relative: the same fractions land on
# the same face in any build at any resolution. `18_body_3m` does not — it frames
# a whole body from a settle, and MEASURED across three builds of the same hero
# the figure moved ~10% of frame height between runs, so a rect inscribed in his
# dragon on one frame sits on his blue belly shell on the next and the number
# silently becomes a measurement of something else. A colour mask has no framing
# to drift with: it selects the serpent by BEING the serpent, which is honest
# here precisely because nothing else in this cast is red.
#
# `measure()` takes either, so a key in this table is used instead of a rect.
def _red_dominant(r, g, b):
    """The dragon: a red that leads both other channels by a clear margin. 60 is
    far above the ~25 counts of hue spread the cloth bake puts across one flat
    colour, and far below the ~200 that separates the serpent from the blue shell
    it lies on."""
    return r > 120 and r > g + 60 and r > b + 60


COLOUR_REGIONS = {"phoboman_dragon": _red_dominant}


def read_rgb(path):
    """(width, height, channels, pixels) from an 8-bit RGB/RGBA PNG."""
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "%s is not a PNG" % path
    pos, idat, width, height, nch = 8, b"", 0, 0, 3
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and ctype in (2, 6), "8-bit RGB/RGBA only"
            nch = 3 if ctype == 2 else 4
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * nch
    out = bytearray(height * stride)
    prev = bytearray(stride)
    at = 0
    for y in range(height):
        # PNG filters, per scanline (0 none, 1 sub, 2 up, 3 average, 4 paeth).
        f = raw[at]
        at += 1
        line = bytearray(raw[at:at + stride])
        at += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                left = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                c = prev[i - nch] if i >= nch else 0
                b = prev[i]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, nch, out


def measure(path, region, threshold=THRESHOLD):
    """(clipped fraction, flat-channel fraction, mean luma, pixel count) in `region`.

    `region` is a rect as fractions of the frame, or a predicate on (r, g, b) —
    see `COLOUR_REGIONS` for why the second kind exists. `n` is what the region
    actually selected, so it is also the sanity check on a mask: a dragon that
    renders 25,000 pixels in one build and 300 in the next was not measured, it
    was missed.

    TWO NUMBERS BECAUSE THERE ARE TWO FAILURES (the second added by bead
    godot-test1-9k9n.8). `clipped` is the original one and the one a FACE is
    judged by: luma at or over `THRESHOLD`, i.e. the pixel has gone to paper
    white and the shape is gone. `flat` is the one a SATURATED colour fails
    instead — a channel pegged at 255 on a pixel that is NOT white, which never
    moves the luma and never trips the first number. Phoboman's dragon was 99.9%
    flat on red over its own rect and 0.00% clipped: a scarlet serpent whose whole
    red channel was one value, so every fold in it was drawn by green and blue
    alone.

    THE TWO ARE DISJOINT BY CONSTRUCTION, by the `elif` below, and it has to be
    that way round: paper white has all three channels at 255, so a bare
    `max(...) >= 255` counts every clipped FACE pixel as flat as well and the two
    numbers stop telling apart the two failures they exist to separate: every
    pixel `clipped` counts is a pixel with three channels at 255, so on the
    pre-9k9n.5 `phoboman` visor the bare predicate would have reported that
    51.37% as a saturated colour whose shading had collapsed.
    """
    width, height, nch, px = read_rgb(path)
    pick = region if callable(region) else None
    if pick is None:
        x0, x1 = int(region[0] * width), int(region[2] * width)
        y0, y1 = int(region[1] * height), int(region[3] * height)
    else:
        x0, y0, x1, y1 = 0, 0, width, height
    clipped, flat, total, n = 0, 0, 0.0, 0
    for y in range(y0, y1):
        row = y * width * nch
        for x in range(x0, x1):
            i = row + x * nch
            if pick is not None and not pick(px[i], px[i + 1], px[i + 2]):
                continue
            luma = (0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]) / 255.0
            total += luma
            n += 1
            if luma >= threshold:
                clipped += 1
            elif max(px[i], px[i + 1], px[i + 2]) >= 255:
                flat += 1
    assert n, "the region selected no pixel at all"
    return clipped / n, flat / n, total / n, n


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: clipped_fraction.py <hero|x0,y0,x1,y1> <png>...")
    key = sys.argv[1]
    if key in COLOUR_REGIONS:
        region, label = COLOUR_REGIONS[key], key
    elif key in FACE_RECTS:
        region = FACE_RECTS[key]
        label = ",".join("%.3f" % v for v in region)
    else:
        region = tuple(float(v) for v in key.split(","))
        assert len(region) == 4, "rect is x0,y0,x1,y1 as fractions of the frame"
        label = ",".join("%.3f" % v for v in region)
    for path in sys.argv[2:]:
        clipped, flat, mean, n = measure(path, region)
        print("%s  clipped=%.4f flat=%.4f mean=%.4f n=%d region=%s"
              % (path, clipped, flat, mean, n, label))


if __name__ == "__main__":
    main()
