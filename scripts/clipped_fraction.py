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
    # the dragon is judged on `flat`, not on `clipped` — see `measure`
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
    # ... and `phoboman_dragon` is not a face at all (bead godot-test1-9k9n.8).
    # It is the widest all-red square that fits inside the serpent on the web
    # `18_body_3m` frame, found by scanning for it rather than by eye, so the
    # rect holds no blue shell and no gold. It is the one thing in this cast that
    # fails a DIFFERENT way from a face: its luma never approaches white, because
    # green and blue stay low — what clips is the RED CHANNEL, on its own, which
    # is the second number `measure()` returns.
    "phoboman_dragon": (0.528, 0.549, 0.544, 0.578),
}


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


def measure(path, rect, threshold=THRESHOLD):
    """(clipped fraction, flat-channel fraction, mean luma, pixel count) in `rect`.

    TWO NUMBERS BECAUSE THERE ARE TWO FAILURES (the second added by bead
    godot-test1-9k9n.8). `clipped` is the original one and the one a FACE is
    judged by: luma at or over `THRESHOLD`, i.e. the pixel has gone to paper
    white and the shape is gone. `flat` is the one a SATURATED colour fails
    instead — any single channel pegged at 255 while the others are nowhere near
    it, which never moves the luma and never trips the first number. Phoboman's
    dragon was 84% flat on red at `18_body_3m` and 0.00% clipped: a scarlet
    serpent whose whole red channel was one value, so every fold in it was drawn
    by green and blue alone.
    """
    width, height, nch, px = read_rgb(path)
    x0, x1 = int(rect[0] * width), int(rect[2] * width)
    y0, y1 = int(rect[1] * height), int(rect[3] * height)
    clipped, flat, total, n = 0, 0, 0.0, 0
    for y in range(y0, y1):
        row = y * width * nch
        for x in range(x0, x1):
            i = row + x * nch
            luma = (0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]) / 255.0
            total += luma
            n += 1
            if luma >= threshold:
                clipped += 1
            if max(px[i], px[i + 1], px[i + 2]) >= 255:
                flat += 1
    assert n, "empty rect"
    return clipped / n, flat / n, total / n, n


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: clipped_fraction.py <hero|x0,y0,x1,y1> <png>...")
    key = sys.argv[1]
    if key in FACE_RECTS:
        rect = FACE_RECTS[key]
    else:
        rect = tuple(float(v) for v in key.split(","))
        assert len(rect) == 4, "rect is x0,y0,x1,y1 as fractions of the frame"
    for path in sys.argv[2:]:
        clipped, flat, mean, n = measure(path, rect)
        print("%s  clipped=%.4f flat=%.4f mean=%.4f n=%d rect=%s"
              % (path, clipped, flat, mean, n, ",".join("%.3f" % v for v in rect)))


if __name__ == "__main__":
    main()
